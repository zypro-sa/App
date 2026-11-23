-- =====================================================================
-- جدول الأعمال: خطة عمل المكتب
-- plan_items       بنود الخطة (مسؤولون، حالة، تقدم، موعد، مؤشر مرتبط)
-- plan_topics      مواضيع للنقاش في الاجتماع القادم
-- initiatives      مشاريع وأفكار تطوير المكتب (مع التصويت)
-- القرارات والتكليفات تُقرأ من decisions (محاضر الاجتماعات)
-- الصلاحيات: plan.view (للجميع افتراضيًا) · plan.edit (للمدير افتراضيًا)
-- =====================================================================

create or replace function role_default_perm(r user_role, p text)
returns boolean language sql immutable as $$
  select case
    when r = 'owner' then true
    -- «المكلّف به» وجدول الأعمال متاحان للجميع افتراضيًا
    when p in ('requests.view_own', 'tasks.view_own', 'meetings.view_own', 'projects.view_own', 'clients.view', 'plan.view') then true
    when r = 'manager' then p in (
      'requests.view', 'requests.add', 'requests.edit', 'requests.delete',
      'tasks.view', 'tasks.add', 'tasks.edit', 'tasks.delete',
      'meetings.view', 'meetings.add', 'meetings.edit', 'meetings.delete',
      'clients.add', 'clients.edit', 'clients.delete',
      'projects.view', 'projects.add', 'projects.edit', 'projects.delete',
      'followups.view', 'followups.add', 'followups.edit', 'followups.delete',
      'reports.view', 'team.view', 'plan.edit',
      'settings_lists.view', 'settings_lists.add', 'settings_lists.edit', 'settings_lists.delete',
      'statuses.view', 'settings_fields.view')
    else false
  end
$$;

-- ---------------- بنود الخطة ----------------
create table if not exists plan_items (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (length(trim(title)) > 0),
  notes       text,
  status      text not null default 'todo' check (status in ('todo', 'on', 'risk', 'done')),
  progress    smallint not null default 0 check (progress between 0 and 100),
  due_date    date,
  kpi         text check (kpi in ('requests_closed', 'collected', 'on_time', 'new_clients', 'tasks_done', 'meetings_held')),
  kpi_target  numeric,
  sort        int not null default 0,
  created_by  uuid default auth.uid() references profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  done_at     timestamptz,
  deleted_at  timestamptz
);

create table if not exists plan_item_owners (
  item_id uuid not null references plan_items (id) on delete cascade,
  user_id uuid not null references profiles (id) on delete cascade,
  primary key (item_id, user_id)
);
create index if not exists plan_item_owners_user_idx on plan_item_owners (user_id);

create or replace function is_plan_owner(p_item uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from plan_item_owners where item_id = p_item and user_id = p_user);
$$;
grant execute on function is_plan_owner(uuid, uuid) to authenticated;

-- الحالة «منجز» تضبط التقدم 100 وتاريخ الإنجاز
create or replace function plan_items_rules()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if new.status = 'done' then
    new.progress := 100;
    new.done_at := coalesce(new.done_at, now());
  else
    new.done_at := null;
    if new.progress = 100 then new.status := 'done'; new.done_at := now(); end if;
  end if;
  return new;
end $$;
drop trigger if exists plan_items_rules on plan_items;
create trigger plan_items_rules before insert or update on plan_items
  for each row execute function plan_items_rules();

-- إشعار المسؤول عند إسناد بند إليه
create or replace function notify_plan_owner()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  t text;
  en boolean;
begin
  if auth.uid() is null or new.user_id = auth.uid() then return new; end if;
  select title into t from plan_items where id = new.item_id;
  en := user_is_en(new.user_id);
  perform notify_user(new.user_id, 'assigned',
    case when en then 'New item in the office plan' else 'بند جديد في خطة عمل المكتب' end,
    t, '/more/reports?tab=plan', null, null, null);
  return new;
end $$;
drop trigger if exists notify_plan_owner on plan_item_owners;
create trigger notify_plan_owner after insert on plan_item_owners
  for each row execute function notify_plan_owner();

-- ---------------- مواضيع النقاش ----------------
create table if not exists plan_topics (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (length(trim(title)) > 0),
  minutes     smallint check (minutes between 1 and 240),
  status      text not null default 'open' check (status in ('open', 'discussed', 'postponed')),
  proposed_by uuid not null default auth.uid() references profiles (id) on delete cascade,
  sort        int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- ---------------- المشاريع والأفكار ----------------
create table if not exists initiatives (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (length(trim(title)) > 0),
  description text,
  category    text not null default 'dev' check (category in ('dev', 'service', 'marketing', 'ops', 'improve')),
  stage       text not null default 'idea' check (stage in ('idea', 'active', 'waiting', 'done')),
  progress    smallint not null default 0 check (progress between 0 and 100),
  due_date    date,
  sort        int not null default 0,
  created_by  uuid default auth.uid() references profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create table if not exists initiative_owners (
  initiative_id uuid not null references initiatives (id) on delete cascade,
  user_id       uuid not null references profiles (id) on delete cascade,
  primary key (initiative_id, user_id)
);

create table if not exists initiative_votes (
  initiative_id uuid not null references initiatives (id) on delete cascade,
  user_id       uuid not null default auth.uid() references profiles (id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (initiative_id, user_id)
);

create or replace function is_initiative_owner(p_id uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from initiative_owners where initiative_id = p_id and user_id = p_user)
      or exists (select 1 from initiatives where id = p_id and created_by = p_user);
$$;
grant execute on function is_initiative_owner(uuid, uuid) to authenticated;

-- ---------------- الصلاحيات ----------------
alter table plan_items enable row level security;
alter table plan_item_owners enable row level security;
alter table plan_topics enable row level security;
alter table initiatives enable row level security;
alter table initiative_owners enable row level security;
alter table initiative_votes enable row level security;

do $$
declare t text;
begin
  foreach t in array array['plan_items', 'plan_item_owners', 'plan_topics', 'initiatives', 'initiative_owners', 'initiative_votes'] loop
    execute format('drop policy if exists %I on %I', t || '_select', t);
    execute format('drop policy if exists %I on %I', t || '_insert', t);
    execute format('drop policy if exists %I on %I', t || '_update', t);
    execute format('drop policy if exists %I on %I', t || '_delete', t);
    execute format('grant select, insert, update, delete on %I to authenticated', t);
    execute format('grant all on %I to service_role', t);
  end loop;
end $$;

-- بنود الخطة: يراها من له عرض جدول الأعمال؛ يديرها plan.edit؛ المسؤول يحدّث الحالة والتقدم
create policy plan_items_select on plan_items for select to authenticated using (has_perm('plan.view') or has_perm('plan.edit'));
create policy plan_items_insert on plan_items for insert to authenticated with check (has_perm('plan.edit'));
create policy plan_items_update on plan_items for update to authenticated
  using (has_perm('plan.edit') or is_plan_owner(id)) with check (has_perm('plan.edit') or is_plan_owner(id));
create policy plan_items_delete on plan_items for delete to authenticated using (has_perm('plan.edit'));

create policy plan_item_owners_select on plan_item_owners for select to authenticated using (has_perm('plan.view') or has_perm('plan.edit'));
create policy plan_item_owners_insert on plan_item_owners for insert to authenticated with check (has_perm('plan.edit'));
create policy plan_item_owners_delete on plan_item_owners for delete to authenticated using (has_perm('plan.edit'));

-- المواضيع: يقترحها أي عضو؛ يعدّلها صاحبها أو plan.edit
create policy plan_topics_select on plan_topics for select to authenticated using (has_perm('plan.view') or has_perm('plan.edit'));
create policy plan_topics_insert on plan_topics for insert to authenticated with check (proposed_by = auth.uid());
create policy plan_topics_update on plan_topics for update to authenticated
  using (has_perm('plan.edit') or proposed_by = auth.uid()) with check (has_perm('plan.edit') or proposed_by = auth.uid());
create policy plan_topics_delete on plan_topics for delete to authenticated using (has_perm('plan.edit') or proposed_by = auth.uid());

-- المشاريع والأفكار: أي عضو يضيف فكرة؛ يديرها صاحبها والمسؤولون عنها وplan.edit
create policy initiatives_select on initiatives for select to authenticated using (has_perm('plan.view') or has_perm('plan.edit'));
create policy initiatives_insert on initiatives for insert to authenticated with check (created_by = auth.uid());
create policy initiatives_update on initiatives for update to authenticated
  using (has_perm('plan.edit') or is_initiative_owner(id)) with check (has_perm('plan.edit') or is_initiative_owner(id));
create policy initiatives_delete on initiatives for delete to authenticated using (has_perm('plan.edit') or created_by = auth.uid());

create policy initiative_owners_select on initiative_owners for select to authenticated using (has_perm('plan.view') or has_perm('plan.edit'));
create policy initiative_owners_insert on initiative_owners for insert to authenticated with check (has_perm('plan.edit') or is_initiative_owner(initiative_id));
create policy initiative_owners_delete on initiative_owners for delete to authenticated using (has_perm('plan.edit') or is_initiative_owner(initiative_id));

create policy initiative_votes_select on initiative_votes for select to authenticated using (true);
create policy initiative_votes_insert on initiative_votes for insert to authenticated with check (user_id = auth.uid());
create policy initiative_votes_delete on initiative_votes for delete to authenticated using (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- كل بيانات التبويب في استدعاء واحد (للجوال وشاشة المكتب)
-- p_from/p_to: فترة الخطة. البنود المفتوحة المتأخرة من قبلها تظهر أيضًا.
-- ---------------------------------------------------------------------
create or replace function work_plan(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Riyadh')::date;
  m_from date := date_trunc('month', p_to)::date;
  fin boolean := has_perm('finance.view');
begin
  if not (has_perm('plan.view') or has_perm('plan.edit')) then
    raise exception 'ليست لديك صلاحية جدول الأعمال';
  end if;
  return jsonb_build_object(
    'can_edit', has_perm('plan.edit'),
    'items', (select coalesce(jsonb_agg(x order by x.sort_key, x.sort, x.due_date nulls last), '[]') from (
      select i.id, i.title, i.notes, i.status, i.progress, i.due_date, i.kpi, i.kpi_target, i.sort, i.done_at,
        case when i.status = 'done' then 2 when i.status = 'risk' then 0 else 1 end as sort_key,
        (i.status <> 'done' and i.due_date < today) as overdue,
        (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'avatar_url', p.avatar_url) order by p.name), '[]')
           from plan_item_owners o join profiles p on p.id = o.user_id where o.item_id = i.id) as owners,
        -- المؤشر المرتبط: القيمة الحالية للشهر من التقارير
        case i.kpi
          when 'requests_closed' then (select count(*) from requests r where r.deleted_at is null and r.status = 'closed' and not r.imported
                                        and (r.closed_at at time zone 'Asia/Riyadh')::date between m_from and today)::numeric
          when 'collected' then case when fin then (select coalesce(sum(amount), 0) from payments pa where pa.deleted_at is null
                                        and pa.paid_at between m_from and today) end
          when 'on_time' then (select round(100.0 * count(*) filter (where r.closed_at::date <= r.due_date) / nullif(count(*), 0))
                                 from requests r where r.deleted_at is null and r.status = 'closed' and r.due_date is not null
                                 and not r.imported and (r.closed_at at time zone 'Asia/Riyadh')::date between m_from and today)
          when 'new_clients' then (select count(*) from clients c where c.deleted_at is null
                                    and (c.created_at at time zone 'Asia/Riyadh')::date between m_from and today)::numeric
          when 'tasks_done' then (select count(*) from tasks t where t.deleted_at is null and t.status = 'done'
                                   and (t.completed_at at time zone 'Asia/Riyadh')::date between m_from and today)::numeric
          when 'meetings_held' then (select count(*) from meetings mt where mt.deleted_at is null and mt.status = 'done'
                                      and (mt.start_at at time zone 'Asia/Riyadh')::date between m_from and today)::numeric
        end as kpi_value
      from plan_items i
      where i.deleted_at is null
        and (i.due_date is null
             or i.due_date between p_from and p_to
             or (i.status <> 'done' and i.due_date < p_from)
             or (i.status = 'done' and (i.done_at at time zone 'Asia/Riyadh')::date between p_from and p_to))
    ) x),
    'decisions', (select coalesce(jsonb_agg(x order by x.state_order, x.due_date nulls last), '[]') from (
      select d.id, d.text, d.due_date, m.title as meeting, (m.start_at at time zone 'Asia/Riyadh')::date as meeting_date,
             p.name as owner, d.task_id,
             case when t.status = 'done' then 'done'
                  when d.due_date < today then 'late'
                  else 'on' end as state,
             case when t.status = 'done' then 2 when d.due_date < today then 0 else 1 end as state_order
      from decisions d
      join meetings m on m.id = d.meeting_id and m.deleted_at is null
      left join tasks t on t.id = d.task_id and t.deleted_at is null
      left join profiles p on p.id = coalesce(t.assignee_id, d.owner_id)
      where d.deleted_at is null
        and (m.start_at at time zone 'Asia/Riyadh')::date > today - 60
        and (t.status is distinct from 'done' or (t.completed_at at time zone 'Asia/Riyadh')::date >= p_from)
      limit 30
    ) x),
    'topics', (select coalesce(jsonb_agg(x order by x.sort, x.created_at), '[]') from (
      select tp.id, tp.title, tp.minutes, tp.status, tp.sort, tp.created_at, tp.proposed_by, p.name as proposer
      from plan_topics tp left join profiles p on p.id = tp.proposed_by
      where tp.deleted_at is null and tp.status in ('open', 'postponed')
    ) x),
    'initiatives', (select coalesce(jsonb_agg(x order by x.stage_order, x.votes desc, x.created_at desc), '[]') from (
      select n.id, n.title, n.description, n.category, n.stage, n.progress, n.due_date, n.created_at, n.created_by,
             cp.name as creator,
             array_position(array['active', 'waiting', 'idea', 'done'], n.stage) as stage_order,
             (select count(*) from initiative_votes v where v.initiative_id = n.id) as votes,
             exists (select 1 from initiative_votes v where v.initiative_id = n.id and v.user_id = auth.uid()) as voted,
             (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'avatar_url', p.avatar_url) order by p.name), '[]')
                from initiative_owners o join profiles p on p.id = o.user_id where o.initiative_id = n.id) as owners
      from initiatives n left join profiles cp on cp.id = n.created_by
      where n.deleted_at is null
        and (n.stage <> 'done' or n.updated_at > now() - interval '60 days')
    ) x)
  );
end $$;

grant execute on function work_plan(date, date) to authenticated;
