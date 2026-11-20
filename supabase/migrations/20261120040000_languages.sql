-- =====================================================================
-- لغتان في التطبيق: العربية والإنجليزية
-- - لغة كل عضو في ملفه (profiles.locale) وتصله الإشعارات بها
-- - أسماء إنجليزية للحالات والحقول (label_en) يعدّلها المالك من لوحة التحكم
-- - التذكيرات والمتابعات التلقائية تُكتب بلغة صاحبها
-- =====================================================================

-- ١. لغة العضو
alter table profiles add column if not exists locale text not null default 'ar'
  check (locale in ('ar', 'en'));

create or replace function user_is_en(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select locale = 'en' from profiles where id = p_user), false)
$$;

-- قائمة الفريق مع لغة كل عضو
drop function team_members();
create function team_members()
returns table (
  id uuid, name text, email text, role user_role, job_title text,
  is_active boolean, pending boolean, open_tasks bigint, open_requests bigint,
  permissions jsonb, locale text
)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.email, p.role, p.job_title, p.is_active,
         (u.last_sign_in_at is null) as pending,
         (select count(*) from tasks t where t.assignee_id = p.id and t.status <> 'done' and t.deleted_at is null),
         (select count(*) from requests r where r.assignee_id = p.id and r.deleted_at is null
            and r.status not in ('closed', 'cancelled')),
         p.permissions,
         p.locale
  from profiles p
  left join auth.users u on u.id = p.id
  where has_perm('team.view') or p.id = auth.uid()
  order by (p.role = 'owner') desc, p.role, p.name
$$;

grant execute on function team_members() to authenticated;

-- ٢. الأسماء الإنجليزية للحالات والحقول
alter table status_labels  add column if not exists label_en text;
alter table field_settings add column if not exists label_en text;

update status_labels s set label_en = v.en
from (values
  ('request', 'new', 'New'),
  ('request', 'in_progress', 'In progress'),
  ('request', 'waiting_client', 'Waiting on client'),
  ('request', 'on_hold', 'On hold'),
  ('request', 'closed', 'Closed'),
  ('request', 'cancelled', 'Cancelled'),
  ('project', 'planning', 'Planning'),
  ('project', 'active', 'Active'),
  ('project', 'on_hold', 'On hold'),
  ('project', 'completed', 'Completed'),
  ('project', 'cancelled', 'Cancelled')
) as v(entity, status, en)
where s.entity::text = v.entity and s.status = v.status and s.label_en is null;

update field_settings f set label_en = v.en
from (values
  ('request', 'title', 'Title'),
  ('request', 'client_id', 'Client'),
  ('request', 'status', 'Status'),
  ('request', 'service_type', 'Service type'),
  ('request', 'priority', 'Priority'),
  ('request', 'due_date', 'Due date'),
  ('request', 'estimated_value', 'Estimated value'),
  ('request', 'description', 'Details'),
  ('request', 'payment_terms', 'Payment terms'),
  ('task', 'title', 'Title'),
  ('task', 'priority', 'Priority'),
  ('task', 'due_at', 'Due'),
  ('task', 'client_id', 'Client'),
  ('task', 'assignee_id', 'Assignee'),
  ('meeting', 'title', 'Title'),
  ('meeting', 'start_at', 'Time'),
  ('meeting', 'type', 'Type'),
  ('meeting', 'location', 'Location'),
  ('meeting', 'client_id', 'Client'),
  ('client', 'name', 'Name'),
  ('client', 'sector', 'Sector'),
  ('client', 'city', 'City'),
  ('client', 'cr_number', 'CR number'),
  ('client', 'vat_number', 'VAT number'),
  ('project', 'name', 'Project name'),
  ('project', 'client_id', 'Client'),
  ('project', 'end_date', 'Delivery date'),
  ('project', 'contract_value', 'Contract value')
) as v(entity, key, en)
where f.entity::text = v.entity and f.key = v.key and f.label_en is null;

-- ٣. التذكيرات بلغة كل عضو
create or replace function generate_notifications() returns integer
language plpgsql security definer set search_path = public as $$
declare
  ksa_now   timestamp := now() at time zone 'Asia/Riyadh';
  day_start timestamptz := date_trunc('day', ksa_now) at time zone 'Asia/Riyadh';
  day_end   timestamptz := day_start + interval '1 day';
  n_before  integer;
  r record;
  u uuid;
  mins int;
  en boolean;
begin
  select count(*) into n_before from notifications;

  -- اجتماع خلال ٣٥ دقيقة: للحضور ومنشئ الاجتماع
  for r in
    select m.id, m.title, m.start_at, m.created_by, c.name as client
    from meetings m left join clients c on c.id = m.client_id
    where m.deleted_at is null and m.status = 'scheduled'
      and m.start_at > now() and m.start_at <= now() + interval '35 minutes'
  loop
    mins := greatest(1, ceil(extract(epoch from r.start_at - now()) / 60))::int;
    for u in
      select a.user_id from meeting_attendees a where a.meeting_id = r.id and a.user_id is not null and a.deleted_at is null
      union select r.created_by
    loop
      en := user_is_en(u);
      perform notify_user(u, 'meeting_soon',
        case when en then 'Meeting in ' || mins || ' min' else 'اجتماع بعد ' || mins || ' دقيقة' end,
        r.title || coalesce(' · ' || r.client, ''),
        '/meetings', 'meeting', r.id, now() - interval '3 hours');
    end loop;
  end loop;

  -- ملخص المهام صباحًا (من ٨ ص بتوقيت السعودية، مرة يوميًا)
  if extract(hour from ksa_now) >= 8 then
    for r in
      select assignee_id,
             count(*) filter (where due_at >= day_start) as today,
             count(*) filter (where due_at < day_start) as overdue
      from tasks
      where deleted_at is null and status <> 'done' and due_at < day_end
      group by assignee_id
    loop
      en := user_is_en(r.assignee_id);
      perform notify_user(r.assignee_id, 'task_due',
        case
          when en and r.today > 0 then 'You have ' || r.today || ' tasks today'
          when en then 'You have overdue tasks'
          when r.today > 0 then 'لديك ' || r.today || ' مهام اليوم'
          else 'لديك مهام متأخرة' end,
        case
          when en and r.overdue > 0 then r.overdue || ' overdue tasks need your attention'
          when en then 'Start your day from the Tasks tab'
          when r.overdue > 0 then r.overdue || ' مهام متأخرة تحتاج متابعتك'
          else 'ابدأ يومك من تبويب المهام' end,
        '/tasks', null, null, day_start);
    end loop;
  end if;

  -- الطلبات المتأخرة (من ٩ ص، مرة يوميًا للمسؤول)
  if extract(hour from ksa_now) >= 9 then
    for r in
      select assignee_id, count(*) as n, min(title) as sample
      from requests
      where deleted_at is null and status in ('new', 'in_progress', 'waiting_client', 'on_hold')
        and due_date < (ksa_now)::date
      group by assignee_id
    loop
      en := user_is_en(r.assignee_id);
      perform notify_user(r.assignee_id, 'request_overdue',
        case
          when en and r.n = 1 then 'A request is past its due date'
          when en then r.n || ' requests are past their due date'
          when r.n = 1 then 'طلب متأخر عن موعده'
          else r.n || ' طلبات متأخرة عن موعدها' end,
        case
          when r.n = 1 then r.sample
          when en then 'Including: ' || r.sample
          else 'منها: ' || r.sample end,
        '/requests', null, null, day_start);
    end loop;
  end if;

  -- متابعات حان موعدها
  for r in
    select f.id, f.title, f.owner_id, f.due_at, f.counterpart
    from followups f
    where f.deleted_at is null and f.status = 'open' and f.due_at <= now()
  loop
    perform notify_user(r.owner_id, 'followup_due',
      case when user_is_en(r.owner_id) then 'A follow-up is due' else 'متابعة حان موعدها' end,
      r.title || coalesce(' · ' || r.counterpart, ''), '/more/followups', 'followup', r.id, r.due_at);
  end loop;

  -- عروض أسعار بلا رد منذ ٣ أيام (أسبوعيًا لمن يملك صلاحية المالية)
  for r in
    select q.id, q.number, c.name as client
    from quotes q join clients c on c.id = q.client_id
    where q.deleted_at is null and q.status = 'sent' and q.sent_at <= current_date - 3
  loop
    for u in
      select p.id from profiles p
      where p.is_active and (p.role = 'owner' or coalesce((p.permissions ->> 'finance.manage')::boolean, false))
    loop
      en := user_is_en(u);
      perform notify_user(u, 'quote_no_reply',
        case when en then 'Quote with no reply' else 'عرض سعر بلا رد' end,
        r.number || ' · ' || r.client || case when en then ' — time for a reminder' else ' — حان وقت التذكير' end,
        '/more/finance', 'quote', r.id, now() - interval '7 days');
    end loop;
  end loop;

  return (select count(*) from notifications) - n_before;
end $$;

revoke execute on function generate_notifications() from public, anon, authenticated;

-- ٤. إشعار الإسناد بلغة المُسند إليه
create or replace function notify_on_assign() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  who text;
  en boolean;
begin
  if auth.uid() is null or new.assignee_id is null or new.assignee_id = auth.uid() then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.assignee_id is not distinct from new.assignee_id then
    return new;
  end if;
  select name into who from profiles where id = auth.uid();
  en := user_is_en(new.assignee_id);
  if tg_table_name = 'tasks' then
    perform notify_user(new.assignee_id, 'assigned',
      case when en then 'New task from ' || coalesce(who, 'the team')
           else 'مهمة جديدة من ' || coalesce(who, 'الفريق') end,
      new.title, '/tasks', 'task', new.id, null);
  else
    perform notify_user(new.assignee_id, 'assigned',
      case when en then 'New request assigned to you by ' || coalesce(who, 'the team')
           else 'طلب جديد مُسند إليك من ' || coalesce(who, 'الفريق') end,
      '#' || new.number || ' · ' || new.title, '/requests/' || new.id, 'request', new.id, null);
  end if;
  return new;
end $$;

-- ٥. المتابعات التلقائية بلغة صاحبها
create or replace function requests_status_rules() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  owner uuid;
begin
  if new.status = 'closed' and (tg_op = 'INSERT' or old.status is distinct from 'closed') then
    new.closed_at := now();
    new.progress  := 100;
  elsif new.status <> 'closed' then
    new.closed_at := null;
  end if;

  owner := coalesce(new.assignee_id, auth.uid());
  if new.status = 'waiting_client'
     and (tg_op = 'INSERT' or old.status is distinct from 'waiting_client')
     and owner is not null then
    insert into followups (title, direction, owner_id, due_at, related_type, related_id, source)
    values (case when user_is_en(owner) then 'Follow up on client reply to request #' || new.number
                 else 'متابعة رد العميل على الطلب #' || new.number end,
            'waiting', owner, now() + interval '3 days', 'request', new.id, 'auto');
  end if;
  return new;
end $$;

create or replace function collection_followup_on_close() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  owner uuid;
  en boolean;
begin
  if new.status = 'closed' and old.status is distinct from 'closed' then
    owner := coalesce(new.assignee_id,
                      (select id from profiles where role = 'owner' and is_active order by created_at limit 1));
    en := user_is_en(owner);
    insert into followups (title, direction, owner_id, counterpart, due_at, related_type, related_id, source)
    select case when en
                then 'Collect the balance of invoice ' || x.number || ': SAR ' || to_char(x.remaining, 'FM999,999,990.##')
                else 'تحصيل المتبقي من فاتورة ' || x.number || ': ' || to_char(x.remaining, 'FM999,999,990.##') || ' ر.س' end,
           'waiting', owner, c.name, now(), 'invoice', x.id, 'auto'
    from (
      select i.id, i.number, i.client_id,
             invoice_net_total(i.id)
               - coalesce((select sum(p.amount) from payments p
                           where p.invoice_id = i.id and p.deleted_at is null), 0) as remaining
      from invoices i
      where i.request_id = new.id and i.deleted_at is null and i.status <> 'void'
    ) x
    join clients c on c.id = x.client_id
    where x.remaining > 0
      and not exists (select 1 from followups f
                      where f.related_id = x.id and f.status <> 'done' and f.deleted_at is null);
  end if;
  return new;
end $$;
