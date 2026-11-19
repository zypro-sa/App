-- =====================================================================
-- الإشعارات والتذكيرات
-- - تذكيرات تُولَّد كل ١٥ دقيقة (pg_cron) وإشعار فوري عند الإسناد
-- - كل إشعار يُحفظ في notifications، ويُرسل للجوال عبر Webhook ← send-push
-- - كل عضو يختار أنواع التذكيرات من الإعدادات (profiles.notify_prefs)
-- =====================================================================

-- ١. توسيع جدول الإشعارات
alter table notifications alter column type type text using type::text;
alter table notifications add column if not exists body text;
alter table notifications add column if not exists url text;

-- المستخدم يستطيع إنشاء إشعار لنفسه (الإشعار التجريبي)
create policy notifications_insert_self on notifications for insert to authenticated
  with check (user_id = auth.uid());
create policy notifications_delete_self on notifications for delete to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete on notifications to authenticated;
grant all on notifications to service_role;

-- ٢. تفضيلات الإشعارات لكل عضو: {"meeting_soon": false, ...} (الافتراضي: مفعّل)
alter table profiles add column if not exists notify_prefs jsonb not null default '{}';

-- ٣. أجهزة العضو المشتركة في الإشعارات (Web Push)
create table push_subscriptions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles (id) on delete cascade default auth.uid(),
  endpoint     text not null unique,
  p256dh       text not null,
  auth         text not null,
  user_agent   text,
  created_at   timestamptz not null default now(),
  last_used_at timestamptz
);

create index on push_subscriptions (user_id);
alter table push_subscriptions enable row level security;
create policy push_subscriptions_own on push_subscriptions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on push_subscriptions to authenticated;
grant all on push_subscriptions to service_role;

-- ٤. إنشاء إشعار لعضو (مع احترام تفضيلاته ومنع التكرار)
create or replace function notify_user(
  p_user uuid, p_type text, p_title text, p_body text, p_url text,
  p_related_type related_entity default null, p_related_id uuid default null,
  p_dedupe_since timestamptz default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_user is null then return; end if;
  if not exists (select 1 from profiles
                 where id = p_user and is_active
                   and coalesce((notify_prefs ->> p_type)::boolean, true)) then
    return;
  end if;
  if p_dedupe_since is not null and exists (
       select 1 from notifications n
       where n.user_id = p_user and n.type = p_type
         and n.related_id is not distinct from p_related_id
         and n.created_at >= p_dedupe_since) then
    return;
  end if;
  insert into notifications (user_id, type, title, body, url, related_type, related_id, send_at)
  values (p_user, p_type, p_title, p_body, p_url, p_related_type, p_related_id, now());
end $$;

revoke execute on function notify_user(uuid, text, text, text, text, related_entity, uuid, timestamptz) from public, anon, authenticated;

-- ٥. توليد التذكيرات (كل ١٥ دقيقة)
create or replace function generate_notifications() returns integer
language plpgsql security definer set search_path = public as $$
declare
  ksa_now   timestamp := now() at time zone 'Asia/Riyadh';
  day_start timestamptz := date_trunc('day', ksa_now) at time zone 'Asia/Riyadh';
  day_end   timestamptz := day_start + interval '1 day';
  n_before  integer;
  r record;
  u uuid;
begin
  select count(*) into n_before from notifications;

  -- اجتماع خلال ٣٥ دقيقة: للحضور ومنشئ الاجتماع
  for r in
    select m.id, m.title, m.start_at, m.created_by, c.name as client
    from meetings m left join clients c on c.id = m.client_id
    where m.deleted_at is null and m.status = 'scheduled'
      and m.start_at > now() and m.start_at <= now() + interval '35 minutes'
  loop
    for u in
      select a.user_id from meeting_attendees a where a.meeting_id = r.id and a.user_id is not null and a.deleted_at is null
      union select r.created_by
    loop
      perform notify_user(u, 'meeting_soon',
        'اجتماع بعد ' || greatest(1, ceil(extract(epoch from r.start_at - now()) / 60))::int || ' دقيقة',
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
      perform notify_user(r.assignee_id, 'task_due',
        case when r.today > 0 then 'لديك ' || r.today || ' مهام اليوم' else 'لديك مهام متأخرة' end,
        case when r.overdue > 0 then r.overdue || ' مهام متأخرة تحتاج متابعتك' else 'ابدأ يومك من تبويب المهام' end,
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
      perform notify_user(r.assignee_id, 'request_overdue',
        case when r.n = 1 then 'طلب متأخر عن موعده' else r.n || ' طلبات متأخرة عن موعدها' end,
        case when r.n = 1 then r.sample else 'منها: ' || r.sample end,
        '/requests', null, null, day_start);
    end loop;
  end if;

  -- متابعات حان موعدها
  for r in
    select f.id, f.title, f.owner_id, f.due_at, f.counterpart
    from followups f
    where f.deleted_at is null and f.status = 'open' and f.due_at <= now()
  loop
    perform notify_user(r.owner_id, 'followup_due', 'متابعة حان موعدها',
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
      perform notify_user(u, 'quote_no_reply', 'عرض سعر بلا رد',
        r.number || ' · ' || r.client || ' — حان وقت التذكير', '/more/finance', 'quote', r.id, now() - interval '7 days');
    end loop;
  end loop;

  return (select count(*) from notifications) - n_before;
end $$;

revoke execute on function generate_notifications() from public, anon, authenticated;

-- ٦. إشعار فوري عند إسناد مهمة أو طلب لعضو آخر
create or replace function notify_on_assign() returns trigger
language plpgsql security definer set search_path = public as $$
declare who text;
begin
  if auth.uid() is null or new.assignee_id is null or new.assignee_id = auth.uid() then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.assignee_id is not distinct from new.assignee_id then
    return new;
  end if;
  select name into who from profiles where id = auth.uid();
  if tg_table_name = 'tasks' then
    perform notify_user(new.assignee_id, 'assigned', 'مهمة جديدة من ' || coalesce(who, 'الفريق'),
      new.title, '/tasks', 'task', new.id, null);
  else
    perform notify_user(new.assignee_id, 'assigned', 'طلب جديد مُسند إليك من ' || coalesce(who, 'الفريق'),
      '#' || new.number || ' · ' || new.title, '/requests/' || new.id, 'request', new.id, null);
  end if;
  return new;
end $$;

create trigger notify_on_assign after insert or update of assignee_id on tasks
  for each row execute function notify_on_assign();
create trigger notify_on_assign after insert or update of assignee_id on requests
  for each row execute function notify_on_assign();

-- ٧. الجدولة كل ١٥ دقيقة (pg_cron مفعّل مسبقًا)
do $$
begin
  perform cron.schedule('generate-notifications', '*/15 * * * *', 'select public.generate_notifications()');
exception when others then
  raise notice 'فعّل pg_cron ثم شغّل: select cron.schedule(''generate-notifications'', ''*/15 * * * *'', ''select public.generate_notifications()'');';
end $$;
