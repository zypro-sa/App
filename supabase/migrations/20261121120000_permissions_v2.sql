-- =====================================================================
-- الصلاحيات (الإصدار الثاني)
-- - نطاق العرض: «الكل» أو «المكلّف به فقط» للطلبات والمهام والاجتماعات والمشاريع
-- - المتابعات والفريق: عرض/إضافة/تعديل/حذف
-- - القوائم والحقول: عرض/إضافة/تعديل/حذف، والحالات: عرض/تعديل
-- =====================================================================

-- صلاحية عضو معيّن (للدوال على الخادم)
create or replace function perm_of(p_user uuid, p text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select case when role = 'owner' then true
                else coalesce((permissions ->> p)::boolean, role_default_perm(role, p)) end
    from profiles where id = p_user and is_active
  ), false)
$$;

revoke execute on function perm_of(uuid, text) from public, anon, authenticated;
grant execute on function perm_of(uuid, text) to service_role;

create or replace function has_perm_raw(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select perm_of(auth.uid(), p)
$$;

create or replace function role_default_perm(r user_role, p text) returns boolean
language sql immutable as $$
  select case
    when r = 'owner' then true
    -- «المكلّف به» متاح للجميع افتراضيًا
    when p in ('requests.view_own', 'tasks.view_own', 'meetings.view_own', 'projects.view_own', 'clients.view') then true
    when r = 'manager' then p in (
      'requests.view', 'requests.add', 'requests.edit', 'requests.delete',
      'tasks.view', 'tasks.add', 'tasks.edit', 'tasks.delete',
      'meetings.view', 'meetings.add', 'meetings.edit', 'meetings.delete',
      'clients.add', 'clients.edit', 'clients.delete',
      'projects.view', 'projects.add', 'projects.edit', 'projects.delete',
      'followups.view', 'followups.add', 'followups.edit', 'followups.delete',
      'reports.view', 'team.view',
      'settings_lists.view', 'settings_lists.add', 'settings_lists.edit', 'settings_lists.delete',
      'statuses.view', 'settings_fields.view')
    else false
  end
$$;

create or replace function has_perm(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select case p
    when 'requests.view_all' then has_perm_raw('requests.view')
    when 'requests.manage'   then has_perm_raw('requests.add') or has_perm_raw('requests.edit')
    when 'tasks.view_all'    then has_perm_raw('tasks.view')
    when 'tasks.assign'      then has_perm_raw('tasks.add') or has_perm_raw('tasks.edit')
    when 'clients.manage'    then has_perm_raw('clients.add') or has_perm_raw('clients.edit')
    when 'projects.manage'   then has_perm_raw('projects.add') or has_perm_raw('projects.edit')
    when 'meetings.manage'   then has_perm_raw('meetings.add') or has_perm_raw('meetings.edit')
    when 'finance.manage'    then has_perm_raw('finance.view')
    when 'settings.lists'    then has_perm_raw('settings_lists.add') or has_perm_raw('settings_lists.edit')
                               or has_perm_raw('settings_lists.delete')
    when 'settings.fields'   then has_perm_raw('settings_fields.add') or has_perm_raw('settings_fields.edit')
                               or has_perm_raw('settings_fields.delete') or has_perm_raw('statuses.edit')
    when 'data.delete'       then has_perm_raw('requests.delete') or has_perm_raw('tasks.delete')
                               or has_perm_raw('meetings.delete') or has_perm_raw('clients.delete')
                               or has_perm_raw('projects.delete') or has_perm_raw('finance.delete')
    else has_perm_raw(p)
  end
$$;

-- تحويل التخصيصات السابقة
update profiles set permissions = permissions
  || case when permissions ? 'settings_lists.edit' then jsonb_build_object(
       'settings_lists.view', permissions -> 'settings_lists.edit',
       'settings_lists.add', permissions -> 'settings_lists.edit',
       'settings_lists.delete', permissions -> 'settings_lists.edit') else '{}'::jsonb end
  || case when permissions ? 'settings_fields.edit' then jsonb_build_object(
       'settings_fields.view', permissions -> 'settings_fields.edit',
       'settings_fields.add', permissions -> 'settings_fields.edit',
       'settings_fields.delete', permissions -> 'settings_fields.edit',
       'statuses.view', permissions -> 'settings_fields.edit',
       'statuses.edit', permissions -> 'settings_fields.edit') else '{}'::jsonb end
  || case when permissions ? 'followups.edit' then jsonb_build_object(
       'followups.add', permissions -> 'followups.edit',
       'followups.delete', permissions -> 'followups.edit') else '{}'::jsonb end
where role <> 'owner';

-- ---------------------------------------------------------------------
-- نطاق العرض
-- ---------------------------------------------------------------------
drop policy if exists requests_select_all on requests;
drop policy if exists requests_select_assigned on requests;
create policy requests_select_all on requests for select to authenticated using (has_perm('requests.view'));
create policy requests_select_assigned on requests for select to authenticated
  using (has_perm('requests.view_own') and (assignee_id = auth.uid() or created_by = auth.uid()));

drop policy if exists tasks_select_own on tasks;
create policy tasks_select_own on tasks for select to authenticated
  using (has_perm('tasks.view_own') and (assignee_id = auth.uid() or assigned_by_id = auth.uid()));

drop policy if exists meetings_select_all on meetings;
drop policy if exists meetings_select_attendee on meetings;
create policy meetings_select_all on meetings for select to authenticated using (has_perm('meetings.view'));
create policy meetings_select_attendee on meetings for select to authenticated
  using (has_perm('meetings.view_own') and (created_by = auth.uid() or exists (
    select 1 from meeting_attendees ma where ma.meeting_id = meetings.id and ma.user_id = auth.uid())));

drop policy if exists agenda_select_attendee on agenda_items;
create policy agenda_select_attendee on agenda_items for select to authenticated
  using (has_perm('meetings.view_own') and exists (
    select 1 from meeting_attendees ma where ma.meeting_id = agenda_items.meeting_id and ma.user_id = auth.uid()));
drop policy if exists attendees_select_self on meeting_attendees;
create policy attendees_select_self on meeting_attendees for select to authenticated
  using (has_perm('meetings.view_own') and user_id = auth.uid());

drop policy if exists projects_select_all on projects;
drop policy if exists projects_select_own on projects;
create policy projects_select_all on projects for select to authenticated using (has_perm('projects.view'));
create policy projects_select_own on projects for select to authenticated
  using (has_perm('projects.view_own') and (manager_id = auth.uid() or created_by = auth.uid()));

-- ---------------------------------------------------------------------
-- المتابعات: كلٌّ يدير متابعاته دائمًا، والصلاحيات تخص متابعات الفريق
-- ---------------------------------------------------------------------
drop policy if exists followups_view_team on followups;
drop policy if exists followups_manage on followups;
drop policy if exists followups_insert_team on followups;
drop policy if exists followups_update_team on followups;
drop policy if exists followups_delete_team on followups;
create policy followups_view_team on followups for select to authenticated using (has_perm('followups.view'));
create policy followups_insert_team on followups for insert to authenticated with check (has_perm('followups.add'));
create policy followups_update_team on followups for update to authenticated
  using (has_perm('followups.edit') or has_perm('followups.delete'))
  with check (has_perm('followups.edit') or has_perm('followups.delete'));
create policy followups_delete_team on followups for delete to authenticated using (has_perm('followups.delete'));

create or replace function guard_soft_delete() returns trigger
language plpgsql as $$
declare
  module text := coalesce(tg_argv[0], tg_table_name);
begin
  if new.deleted_at is distinct from old.deleted_at
     and auth.uid() is not null
     and not has_perm(module || '.delete')
     and not (tg_table_name = 'tasks' and old.created_by = auth.uid())
     and not (tg_table_name = 'followups' and old.owner_id = auth.uid()) then
    raise exception 'ليست لديك صلاحية الحذف';
  end if;
  return new;
end $$;

drop trigger if exists guard_soft_delete on followups;
create trigger guard_soft_delete before update of deleted_at on followups
  for each row execute function guard_soft_delete('followups');

-- ---------------------------------------------------------------------
-- الفريق: الإضافة (الدعوة) والتعديل والحذف يمكن تفويضها لغير المالك
-- لا أحد يعدّل نفسه أو المالك، ولا يمنح دور المالك
-- ---------------------------------------------------------------------
drop policy if exists profiles_team_manage on profiles;
create policy profiles_team_manage on profiles for update to authenticated
  using (id <> auth.uid() and role <> 'owner' and (has_perm('team.edit') or has_perm('team.delete')))
  with check (id <> auth.uid() and role <> 'owner');

create or replace function guard_profile_privileges() returns trigger
language plpgsql as $$
declare
  privileged boolean := new.permissions is distinct from old.permissions
                     or new.role is distinct from old.role
                     or new.email is distinct from old.email
                     or new.job_title is distinct from old.job_title;
begin
  if auth.uid() is null or is_owner() then
    return new;
  end if;
  if new.id = auth.uid() then
    if privileged or new.is_active is distinct from old.is_active then
      raise exception 'هذا التعديل للمالك أو لمن يملك صلاحية الفريق';
    end if;
    return new;
  end if;
  if old.role = 'owner' or new.role = 'owner' then
    raise exception 'لا يمكن تعديل حساب المالك';
  end if;
  if privileged and not has_perm('team.edit') then
    raise exception 'ليست لديك صلاحية تعديل الأعضاء';
  end if;
  if new.is_active is distinct from old.is_active and not has_perm('team.delete') then
    raise exception 'ليست لديك صلاحية إيقاف الأعضاء';
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------
-- لوحة التحكم: القوائم والحقول والحالات
-- ---------------------------------------------------------------------
drop policy if exists field_settings_fields on field_settings;
drop policy if exists field_settings_lists on field_settings;
drop policy if exists field_settings_insert on field_settings;
drop policy if exists field_settings_update on field_settings;
create policy field_settings_insert on field_settings for insert to authenticated
  with check (has_perm('settings_fields.add'));
create policy field_settings_update on field_settings for update to authenticated
  using (has_perm('settings_fields.edit') or has_perm('settings_fields.delete')
         or has_perm('settings_lists.add') or has_perm('settings_lists.edit') or has_perm('settings_lists.delete'))
  with check (true);

drop policy if exists status_labels_fields on status_labels;
create policy status_labels_fields on status_labels for update to authenticated
  using (has_perm('statuses.edit')) with check (has_perm('statuses.edit'));

-- التحقق الدقيق: أي جزء من الحقل تغيّر، وهل يملك صلاحيته؟
create or replace function field_settings_lists_only() returns trigger
language plpgsql as $$
declare
  old_opts text[];
  new_opts text[];
  added int;
  removed int;
begin
  if auth.uid() is null or is_owner() then
    return new;
  end if;
  if (new.label is distinct from old.label
      or new.label_en is distinct from old.label_en
      or new.type is distinct from old.type
      or new.required is distinct from old.required
      or new.visible is distinct from old.visible
      or new.show_on_card is distinct from old.show_on_card
      or new.sort_order is distinct from old.sort_order)
     and not has_perm('settings_fields.edit') then
    raise exception 'ليست لديك صلاحية تعديل الحقول';
  end if;
  if new.deleted_at is distinct from old.deleted_at and not has_perm('settings_fields.delete') then
    raise exception 'ليست لديك صلاحية حذف الحقول';
  end if;
  if new.options is distinct from old.options and not has_perm('settings_fields.edit') then
    old_opts := coalesce(old.options, '{}');
    new_opts := coalesce(new.options, '{}');
    select count(*) into added from unnest(new_opts) x where not x = any(old_opts);
    select count(*) into removed from unnest(old_opts) x where not x = any(new_opts);
    if added > 0 and removed > 0 and not has_perm('settings_lists.edit') then
      raise exception 'ليست لديك صلاحية تعديل الخيارات';
    elsif added > 0 and removed = 0 and not (has_perm('settings_lists.add') or has_perm('settings_lists.edit')) then
      raise exception 'ليست لديك صلاحية إضافة الخيارات';
    elsif removed > 0 and added = 0 and not (has_perm('settings_lists.delete') or has_perm('settings_lists.edit')) then
      raise exception 'ليست لديك صلاحية حذف الخيارات';
    elsif added = 0 and removed = 0 and not has_perm('settings_lists.edit') then
      raise exception 'ليست لديك صلاحية ترتيب الخيارات';
    end if;
  end if;
  return new;
end $$;
