-- =====================================================================
-- مهمة واحدة لأكثر من شخص
-- task_assignees: كل المسندة إليهم المهمة. tasks.assignee_id يبقى «المسؤول الأول»
-- (للتوافق مع التقارير والإشعارات الحالية) ويُضاف تلقائيًا إلى القائمة.
-- =====================================================================

create table if not exists task_assignees (
  task_id    uuid not null references tasks (id) on delete cascade,
  user_id    uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (task_id, user_id)
);
create index if not exists task_assignees_user_idx on task_assignees (user_id);

-- نقل المسؤولين الحاليين
insert into task_assignees (task_id, user_id)
select id, assignee_id from tasks where assignee_id is not null
on conflict do nothing;

-- دوال مساعدة (security definer لتجنّب التكرار في سياسات RLS)
create or replace function is_task_assignee(p_task uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from task_assignees where task_id = p_task and user_id = p_user);
$$;

create or replace function task_assigned_by(p_task uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select assigned_by_id from tasks where id = p_task;
$$;

grant execute on function is_task_assignee(uuid, uuid) to authenticated;
grant execute on function task_assigned_by(uuid) to authenticated;

-- المسؤول الأول يُضاف دائمًا إلى القائمة
create or replace function sync_primary_assignee()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.assignee_id is not null then
    insert into task_assignees (task_id, user_id) values (new.id, new.assignee_id) on conflict do nothing;
  end if;
  return new;
end $$;

drop trigger if exists sync_primary_assignee on tasks;
create trigger sync_primary_assignee after insert or update of assignee_id on tasks
  for each row execute function sync_primary_assignee();

-- إشعار المشاركين الإضافيين (المسؤول الأول يصله إشعار notify_on_assign)
create or replace function notify_task_coassignee()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  t record;
  who text;
  en boolean;
begin
  if auth.uid() is null or new.user_id = auth.uid() then return new; end if;
  select id, title, assignee_id into t from tasks where id = new.task_id;
  if t.id is null or t.assignee_id = new.user_id then return new; end if;
  select name into who from profiles where id = auth.uid();
  en := user_is_en(new.user_id);
  perform notify_user(new.user_id, 'assigned',
    case when en then 'Shared task from ' || coalesce(who, 'the team')
         else 'مهمة مشتركة من ' || coalesce(who, 'الفريق') end,
    t.title, '/tasks', 'task', t.id, null);
  return new;
end $$;

drop trigger if exists notify_task_coassignee on task_assignees;
create trigger notify_task_coassignee after insert on task_assignees
  for each row execute function notify_task_coassignee();

-- الصلاحيات
alter table task_assignees enable row level security;
drop policy if exists task_assignees_select on task_assignees;
drop policy if exists task_assignees_insert on task_assignees;
drop policy if exists task_assignees_delete on task_assignees;
-- يراها من يرى المهمة
create policy task_assignees_select on task_assignees for select to authenticated
  using (exists (select 1 from tasks t where t.id = task_id));
-- يضيف/يزيل: من يملك إضافة أو تعديل المهام، أو من أسند المهمة
create policy task_assignees_insert on task_assignees for insert to authenticated
  with check (has_perm('tasks.add') or has_perm('tasks.edit') or task_assigned_by(task_id) = auth.uid());
create policy task_assignees_delete on task_assignees for delete to authenticated
  using (has_perm('tasks.edit') or task_assigned_by(task_id) = auth.uid());
grant select, insert, delete on task_assignees to authenticated;
grant all on task_assignees to service_role;

-- المهام: كل المشاركين يرونها ويحدّثونها (مثل المسؤول الأول)
drop policy if exists tasks_select_own on tasks;
create policy tasks_select_own on tasks for select to authenticated
  using (has_perm('tasks.view_own') and (assignee_id = auth.uid() or assigned_by_id = auth.uid() or is_task_assignee(id)));

drop policy if exists tasks_update_own on tasks;
create policy tasks_update_own on tasks for update to authenticated
  using (assignee_id = auth.uid() or is_task_assignee(id))
  with check (assignee_id = auth.uid() or is_task_assignee(id));
