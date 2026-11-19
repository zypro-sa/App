-- =====================================================================
-- صلاحيات تفصيلية لكل عضو
-- الدور (مدير/موظف) يعطي صلاحيات افتراضية، والمالك يستطيع تشغيل أو
-- إيقاف أي صلاحية لكل عضو. المالك يملك كل الصلاحيات دائمًا.
-- =====================================================================

alter table profiles add column permissions jsonb not null default '{}';

-- الصلاحيات الافتراضية لكل دور
create or replace function role_default_perm(r user_role, p text) returns boolean
language sql immutable as $$
  select case
    when r = 'owner' then true
    when r = 'manager' then p in (
      'requests.view_all', 'requests.manage',
      'tasks.view_all', 'tasks.assign',
      'clients.manage', 'projects.manage', 'meetings.manage',
      'reports.view', 'team.view', 'settings.lists', 'data.delete')
    else false
  end
$$;

-- هل يملك المستخدم الحالي هذه الصلاحية؟
create or replace function has_perm(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select case when role = 'owner' then true
                else coalesce((permissions ->> p)::boolean, role_default_perm(role, p)) end
    from profiles where id = auth.uid() and is_active
  ), false)
$$;

grant execute on function has_perm(text), role_default_perm(user_role, text) to authenticated;

-- لا يغيّر أحد غير المالك الأدوار أو الصلاحيات أو حالة الحساب
create or replace function guard_profile_privileges() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and not is_owner() and (
       new.permissions is distinct from old.permissions
       or new.role is distinct from old.role
       or new.is_active is distinct from old.is_active) then
    raise exception 'تعديل الصلاحيات للمالك فقط';
  end if;
  return new;
end $$;

create trigger guard_profile_privileges before update on profiles
  for each row execute function guard_profile_privileges();

-- ---------------------------------------------------------------------
-- الطلبات
-- ---------------------------------------------------------------------
drop policy requests_manage on requests;
create policy requests_select_all on requests for select to authenticated using (has_perm('requests.view_all'));
create policy requests_insert     on requests for insert to authenticated with check (has_perm('requests.manage'));
create policy requests_update_all on requests for update to authenticated
  using (has_perm('requests.manage')) with check (has_perm('requests.manage'));
create policy requests_delete     on requests for delete to authenticated using (has_perm('data.delete'));

-- ---------------------------------------------------------------------
-- المهام
-- ---------------------------------------------------------------------
drop policy tasks_manage on tasks;
create policy tasks_select_all on tasks for select to authenticated using (has_perm('tasks.view_all'));
create policy tasks_insert_any on tasks for insert to authenticated with check (has_perm('tasks.assign'));
create policy tasks_update_any on tasks for update to authenticated
  using (has_perm('tasks.assign')) with check (has_perm('tasks.assign'));
create policy tasks_delete     on tasks for delete to authenticated using (has_perm('data.delete'));

-- ---------------------------------------------------------------------
-- العملاء وجهات التواصل
-- ---------------------------------------------------------------------
drop policy clients_write on clients;
create policy clients_write on clients for all to authenticated
  using (has_perm('clients.manage')) with check (has_perm('clients.manage'));
drop policy contacts_write on contacts;
create policy contacts_write on contacts for all to authenticated
  using (has_perm('clients.manage')) with check (has_perm('clients.manage'));

-- ---------------------------------------------------------------------
-- المشاريع
-- ---------------------------------------------------------------------
drop policy projects_manage on projects;
create policy projects_manage on projects for all to authenticated
  using (has_perm('projects.manage')) with check (has_perm('projects.manage'));
drop policy milestones_manage on milestones;
create policy milestones_manage on milestones for all to authenticated
  using (has_perm('projects.manage')) with check (has_perm('projects.manage'));

-- ---------------------------------------------------------------------
-- الاجتماعات
-- ---------------------------------------------------------------------
drop policy meetings_manage on meetings;
create policy meetings_manage on meetings for all to authenticated
  using (has_perm('meetings.manage')) with check (has_perm('meetings.manage'));
drop policy agenda_manage on agenda_items;
create policy agenda_manage on agenda_items for all to authenticated
  using (has_perm('meetings.manage')) with check (has_perm('meetings.manage'));
drop policy attendees_manage on meeting_attendees;
create policy attendees_manage on meeting_attendees for all to authenticated
  using (has_perm('meetings.manage')) with check (has_perm('meetings.manage'));
drop policy decisions_manage on decisions;
create policy decisions_manage on decisions for all to authenticated
  using (has_perm('meetings.manage')) with check (has_perm('meetings.manage'));

-- ---------------------------------------------------------------------
-- المتابعات والمرفقات وسجل النشاط
-- ---------------------------------------------------------------------
drop policy followups_manage on followups;
create policy followups_manage on followups for all to authenticated
  using (has_perm('team.view')) with check (has_perm('team.view'));
drop policy attachments_manage on attachments;
create policy attachments_manage on attachments for all to authenticated
  using (has_perm('requests.manage')) with check (has_perm('requests.manage'));
drop policy activity_select on activity_log;
create policy activity_select on activity_log for select to authenticated using (has_perm('reports.view'));

-- ---------------------------------------------------------------------
-- المالية
-- ---------------------------------------------------------------------
drop policy quotes_owner on quotes;
drop policy invoices_owner on invoices;
drop policy payments_owner on payments;
create policy quotes_finance   on quotes   for all to authenticated using (has_perm('finance.manage')) with check (has_perm('finance.manage'));
create policy invoices_finance on invoices for all to authenticated using (has_perm('finance.manage')) with check (has_perm('finance.manage'));
create policy payments_finance on payments for all to authenticated using (has_perm('finance.manage')) with check (has_perm('finance.manage'));

-- ---------------------------------------------------------------------
-- لوحة التحكم
-- ---------------------------------------------------------------------
drop policy field_settings_owner on field_settings;
drop policy field_settings_manager_update on field_settings;
create policy field_settings_fields on field_settings for all to authenticated
  using (has_perm('settings.fields')) with check (has_perm('settings.fields'));
create policy field_settings_lists on field_settings for update to authenticated
  using (has_perm('settings.lists')) with check (has_perm('settings.lists'));

drop policy status_labels_owner on status_labels;
create policy status_labels_fields on status_labels for update to authenticated
  using (has_perm('settings.fields')) with check (has_perm('settings.fields'));

-- صلاحية «القوائم» تعدّل الخيارات فقط، لا خصائص الحقل
create or replace function field_settings_lists_only() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and not has_perm('settings.fields') and (
       new.label is distinct from old.label
       or new.type is distinct from old.type
       or new.required is distinct from old.required
       or new.visible is distinct from old.visible
       or new.show_on_card is distinct from old.show_on_card
       or new.sort_order is distinct from old.sort_order
       or new.deleted_at is distinct from old.deleted_at) then
    raise exception 'صلاحيتك تسمح بتعديل خيارات القوائم فقط';
  end if;
  return new;
end $$;

create trigger field_settings_lists_only before update on field_settings
  for each row execute function field_settings_lists_only();

-- ---------------------------------------------------------------------
-- الحذف (النقل للسلة) والاسترجاع
-- المهمة التي أنشأها الشخص لنفسه يستطيع حذفها دائمًا.
-- الملاحظات والمتابعات شخصية ولا تخضع لهذه الصلاحية.
-- ---------------------------------------------------------------------
create or replace function guard_soft_delete() returns trigger
language plpgsql as $$
begin
  if new.deleted_at is distinct from old.deleted_at
     and auth.uid() is not null
     and not has_perm('data.delete')
     and not (tg_table_name = 'tasks' and old.created_by = auth.uid()) then
    raise exception 'ليست لديك صلاحية الحذف';
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['requests', 'tasks', 'clients', 'projects', 'meetings', 'quotes', 'invoices'] loop
    execute format(
      'create trigger guard_soft_delete before update of deleted_at on %I
         for each row execute function guard_soft_delete()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- قائمة الفريق مع الصلاحيات
-- ---------------------------------------------------------------------
drop function team_members();
create function team_members()
returns table (
  id uuid, name text, email text, role user_role, job_title text,
  is_active boolean, pending boolean, open_tasks bigint, open_requests bigint,
  permissions jsonb
)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.email, p.role, p.job_title, p.is_active,
         (u.last_sign_in_at is null) as pending,
         (select count(*) from tasks t where t.assignee_id = p.id and t.status <> 'done' and t.deleted_at is null),
         (select count(*) from requests r where r.assignee_id = p.id and r.deleted_at is null
            and r.status not in ('closed', 'cancelled')),
         p.permissions
  from profiles p
  left join auth.users u on u.id = p.id
  where has_perm('team.view') or p.id = auth.uid()
  order by (p.role = 'owner') desc, p.role, p.name
$$;

grant execute on function team_members() to authenticated;

-- المتابعة التلقائية عند «بانتظار العميل» تُنشأ للمسؤول عن الطلب أيًا كانت صلاحيات من غيّر الحالة
alter function requests_status_rules() security definer set search_path = public;
