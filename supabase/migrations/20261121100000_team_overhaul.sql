-- =====================================================================
-- الفريق والصلاحيات: صلاحيات تفصيلية (عرض/إضافة/تعديل/حذف) لكل قسم،
-- وحساب شخصي لكل عضو (الجوال، البريد، الصورة)، وإدارة المالك للأعضاء.
-- =====================================================================

-- ---------------------------------------------------------------------
-- ١. الصلاحيات: القسم.الإجراء
--    requests | tasks | meetings | clients | projects | followups |
--    finance | reports | team | settings_lists | settings_fields
--    × view | add | edit | delete
-- ---------------------------------------------------------------------
create or replace function role_default_perm(r user_role, p text) returns boolean
language sql immutable as $$
  select case
    when r = 'owner' then true
    when r = 'manager' then p in (
      'requests.view', 'requests.add', 'requests.edit', 'requests.delete',
      'tasks.view', 'tasks.add', 'tasks.edit', 'tasks.delete',
      'meetings.view', 'meetings.add', 'meetings.edit', 'meetings.delete',
      'clients.view', 'clients.add', 'clients.edit', 'clients.delete',
      'projects.view', 'projects.add', 'projects.edit', 'projects.delete',
      'followups.view', 'followups.edit',
      'reports.view', 'team.view', 'settings_lists.edit')
    else p in ('clients.view')
  end
$$;

-- الصلاحية كما هي (بلا أسماء قديمة)
create or replace function has_perm_raw(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select case when role = 'owner' then true
                else coalesce((permissions ->> p)::boolean, role_default_perm(role, p)) end
    from profiles where id = auth.uid() and is_active
  ), false)
$$;

-- has_perm يفهم الأسماء القديمة أيضًا حتى لا يتعطل أي جزء قديم
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
    when 'settings.lists'    then has_perm_raw('settings_lists.edit')
    when 'settings.fields'   then has_perm_raw('settings_fields.edit')
    when 'data.delete'       then has_perm_raw('requests.delete') or has_perm_raw('tasks.delete')
                               or has_perm_raw('meetings.delete') or has_perm_raw('clients.delete')
                               or has_perm_raw('projects.delete') or has_perm_raw('finance.delete')
    else has_perm_raw(p)
  end
$$;

grant execute on function has_perm(text), has_perm_raw(text), role_default_perm(user_role, text) to authenticated;

-- تحويل التخصيصات الحالية للأسماء الجديدة (تبقى القديمة كما هي)
update profiles set permissions = permissions || (
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) from (
    select n.k, (permissions ->> o.old)::boolean as v
    from (values
      ('requests.view_all', array['requests.view']),
      ('requests.manage',   array['requests.add', 'requests.edit']),
      ('tasks.view_all',    array['tasks.view']),
      ('tasks.assign',      array['tasks.add', 'tasks.edit']),
      ('clients.manage',    array['clients.add', 'clients.edit']),
      ('projects.manage',   array['projects.view', 'projects.add', 'projects.edit']),
      ('meetings.manage',   array['meetings.view', 'meetings.add', 'meetings.edit']),
      ('team.view',         array['team.view', 'followups.view', 'followups.edit']),
      ('finance.manage',    array['finance.view', 'finance.add', 'finance.edit']),
      ('settings.lists',    array['settings_lists.edit']),
      ('settings.fields',   array['settings_fields.edit']),
      ('data.delete',       array['requests.delete', 'tasks.delete', 'meetings.delete',
                                  'clients.delete', 'projects.delete'])
    ) as o(old, news)
    cross join lateral unnest(o.news) as n(k)
    where permissions ? o.old
  ) x
)
where role <> 'owner' and permissions <> '{}'::jsonb;

-- من كان يملك المالية والحذف معًا: يحذف في المالية أيضًا
update profiles set permissions = permissions || '{"finance.delete": true}'::jsonb
where role <> 'owner'
  and coalesce((permissions ->> 'finance.manage')::boolean, false)
  and coalesce((permissions ->> 'data.delete')::boolean, role = 'manager');

-- ---------------------------------------------------------------------
-- ٢. سياسات الوصول لكل قسم
-- ---------------------------------------------------------------------

-- الطلبات: المسؤول عن الطلب ومنشئه يريانه ويحدّثانه دائمًا
drop policy if exists requests_select_all on requests;
drop policy if exists requests_insert on requests;
drop policy if exists requests_update_all on requests;
drop policy if exists requests_delete on requests;
create policy requests_select_all on requests for select to authenticated
  using (has_perm('requests.view') or created_by = auth.uid());
create policy requests_insert on requests for insert to authenticated with check (has_perm('requests.add'));
create policy requests_update_all on requests for update to authenticated
  using (has_perm('requests.edit') or has_perm('requests.delete'))
  with check (has_perm('requests.edit') or has_perm('requests.delete'));
create policy requests_delete on requests for delete to authenticated using (has_perm('requests.delete'));

drop policy if exists request_steps_write on request_steps;
create policy request_steps_write on request_steps for all to authenticated
  using (has_perm('requests.edit') or has_perm('requests.add')
         or exists (select 1 from requests r where r.id = request_steps.request_id and r.assignee_id = auth.uid()))
  with check (has_perm('requests.edit') or has_perm('requests.add')
         or exists (select 1 from requests r where r.id = request_steps.request_id and r.assignee_id = auth.uid()));

drop policy if exists attachments_manage on attachments;
create policy attachments_manage on attachments for all to authenticated
  using (has_perm('requests.edit')) with check (has_perm('requests.edit'));

-- المهام: الجميع يضيف مهامه لنفسه ويحدّثها؛ «الإضافة» تعني الإسناد للآخرين
drop policy if exists tasks_select_all on tasks;
drop policy if exists tasks_insert_any on tasks;
drop policy if exists tasks_update_any on tasks;
drop policy if exists tasks_delete on tasks;
create policy tasks_select_all on tasks for select to authenticated using (has_perm('tasks.view'));
create policy tasks_insert_any on tasks for insert to authenticated with check (has_perm('tasks.add'));
create policy tasks_update_any on tasks for update to authenticated
  using (has_perm('tasks.edit') or has_perm('tasks.delete'))
  with check (has_perm('tasks.edit') or has_perm('tasks.delete'));
create policy tasks_delete on tasks for delete to authenticated using (has_perm('tasks.delete'));

-- الاجتماعات: الحاضر ومنشئ الاجتماع يريانه دائمًا
drop policy if exists meetings_manage on meetings;
drop policy if exists meetings_select_all on meetings;
drop policy if exists meetings_insert on meetings;
drop policy if exists meetings_update on meetings;
drop policy if exists meetings_delete on meetings;
create policy meetings_select_all on meetings for select to authenticated
  using (has_perm('meetings.view') or created_by = auth.uid());
create policy meetings_insert on meetings for insert to authenticated with check (has_perm('meetings.add'));
create policy meetings_update on meetings for update to authenticated
  using (has_perm('meetings.edit') or has_perm('meetings.delete') or created_by = auth.uid())
  with check (has_perm('meetings.edit') or has_perm('meetings.delete') or created_by = auth.uid());
create policy meetings_delete on meetings for delete to authenticated using (has_perm('meetings.delete'));

drop policy if exists agenda_manage on agenda_items;
create policy agenda_manage on agenda_items for all to authenticated
  using (has_perm('meetings.view') or has_perm('meetings.add') or has_perm('meetings.edit'))
  with check (has_perm('meetings.add') or has_perm('meetings.edit'));
drop policy if exists attendees_manage on meeting_attendees;
create policy attendees_manage on meeting_attendees for all to authenticated
  using (has_perm('meetings.view') or has_perm('meetings.add') or has_perm('meetings.edit'))
  with check (has_perm('meetings.add') or has_perm('meetings.edit'));
drop policy if exists decisions_manage on decisions;
create policy decisions_manage on decisions for all to authenticated
  using (has_perm('meetings.view') or has_perm('meetings.add') or has_perm('meetings.edit'))
  with check (has_perm('meetings.add') or has_perm('meetings.edit'));

-- العملاء: العرض للجميع افتراضيًا (يمكن إيقافه)، والإضافة والتعديل والحذف منفصلة
drop policy if exists clients_select on clients;
drop policy if exists clients_write on clients;
drop policy if exists clients_insert on clients;
drop policy if exists clients_update on clients;
drop policy if exists clients_delete on clients;
create policy clients_select on clients for select to authenticated
  using (has_perm('clients.view') or has_perm('clients.edit') or has_perm('requests.add'));
create policy clients_insert on clients for insert to authenticated with check (has_perm('clients.add'));
create policy clients_update on clients for update to authenticated
  using (has_perm('clients.edit') or has_perm('clients.delete'))
  with check (has_perm('clients.edit') or has_perm('clients.delete'));
create policy clients_delete on clients for delete to authenticated using (has_perm('clients.delete'));

drop policy if exists contacts_write on contacts;
create policy contacts_write on contacts for all to authenticated
  using (has_perm('clients.add') or has_perm('clients.edit'))
  with check (has_perm('clients.add') or has_perm('clients.edit'));

-- المشاريع: مدير المشروع يرى مشروعه دائمًا
drop policy if exists projects_manage on projects;
drop policy if exists projects_select_all on projects;
drop policy if exists projects_insert on projects;
drop policy if exists projects_update on projects;
drop policy if exists projects_delete on projects;
create policy projects_select_all on projects for select to authenticated
  using (has_perm('projects.view') or created_by = auth.uid());
create policy projects_insert on projects for insert to authenticated with check (has_perm('projects.add'));
create policy projects_update on projects for update to authenticated
  using (has_perm('projects.edit') or has_perm('projects.delete'))
  with check (has_perm('projects.edit') or has_perm('projects.delete'));
create policy projects_delete on projects for delete to authenticated using (has_perm('projects.delete'));

drop policy if exists milestones_manage on milestones;
create policy milestones_manage on milestones for all to authenticated
  using (has_perm('projects.view') or has_perm('projects.add') or has_perm('projects.edit'))
  with check (has_perm('projects.add') or has_perm('projects.edit'));

-- المتابعات: كلٌّ يدير متابعاته؛ «العرض» = رؤية متابعات الفريق، «التعديل» = إدارتها
drop policy if exists followups_manage on followups;
drop policy if exists followups_view_team on followups;
create policy followups_view_team on followups for select to authenticated using (has_perm('followups.view'));
create policy followups_manage on followups for all to authenticated
  using (has_perm('followups.edit')) with check (has_perm('followups.edit'));

-- المالية
do $$
declare t text;
begin
  foreach t in array array['quotes', 'invoices', 'payments', 'invoice_returns'] loop
    execute format('drop policy if exists %I on %I', t || '_finance', t);
    execute format('drop policy if exists %I on %I', t || '_select', t);
    execute format('drop policy if exists %I on %I', t || '_insert', t);
    execute format('drop policy if exists %I on %I', t || '_update', t);
    execute format('drop policy if exists %I on %I', t || '_delete', t);
    execute format('create policy %I on %I for select to authenticated using (has_perm(''finance.view''))', t || '_select', t);
    execute format('create policy %I on %I for insert to authenticated with check (has_perm(''finance.add''))', t || '_insert', t);
    execute format('create policy %I on %I for update to authenticated
                      using (has_perm(''finance.edit'') or has_perm(''finance.add'') or has_perm(''finance.delete''))
                      with check (has_perm(''finance.edit'') or has_perm(''finance.add'') or has_perm(''finance.delete''))',
                   t || '_update', t);
    execute format('create policy %I on %I for delete to authenticated using (has_perm(''finance.delete''))', t || '_delete', t);
  end loop;
end $$;

-- الحذف (النقل للسلة) حسب صلاحية حذف القسم
create or replace function guard_soft_delete() returns trigger
language plpgsql as $$
declare
  module text := coalesce(tg_argv[0], tg_table_name);
begin
  if new.deleted_at is distinct from old.deleted_at
     and auth.uid() is not null
     and not has_perm(module || '.delete')
     and not (tg_table_name = 'tasks' and old.created_by = auth.uid()) then
    raise exception 'ليست لديك صلاحية الحذف';
  end if;
  return new;
end $$;

do $$
declare
  t text;
  m text;
begin
  for t, m in select * from (values
      ('requests', 'requests'), ('tasks', 'tasks'), ('clients', 'clients'),
      ('projects', 'projects'), ('meetings', 'meetings'),
      ('quotes', 'finance'), ('invoices', 'finance')) as v(t, m)
  loop
    execute format('drop trigger if exists guard_soft_delete on %I', t);
    execute format(
      'create trigger guard_soft_delete before update of deleted_at on %I
         for each row execute function guard_soft_delete(%L)', t, m);
  end loop;
end $$;

-- لوحة التحكم
create or replace function field_settings_lists_only() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and not has_perm('settings_fields.edit') and (
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

-- ---------------------------------------------------------------------
-- ٣. الحساب الشخصي
-- ---------------------------------------------------------------------

-- العضو يعدّل اسمه وجواله وصورته فقط؛ البريد يتغير عبر تأكيد البريد الجديد
create or replace function guard_profile_privileges() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and not is_owner() and (
       new.permissions is distinct from old.permissions
       or new.role is distinct from old.role
       or new.is_active is distinct from old.is_active
       or new.email is distinct from old.email
       or (new.job_title is distinct from old.job_title and new.id = auth.uid())) then
    raise exception 'هذا التعديل للمالك فقط';
  end if;
  return new;
end $$;

-- مزامنة البريد في ملف العضو بعد تأكيد البريد الجديد
create or replace function sync_profile_email() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.email is distinct from old.email and new.email is not null then
    update profiles set email = new.email where id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists sync_profile_email on auth.users;
create trigger sync_profile_email after update of email on auth.users
  for each row execute function sync_profile_email();

-- صور الأعضاء (عامة للقراءة، وكلٌّ يرفع في مجلده فقط)
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('avatars', 'avatars', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do update set public = true;

    execute 'drop policy if exists avatars_read on storage.objects';
    execute 'drop policy if exists avatars_write_own on storage.objects';
    execute 'drop policy if exists avatars_update_own on storage.objects';
    execute 'drop policy if exists avatars_delete_own on storage.objects';
    execute $p$create policy avatars_read on storage.objects for select to public
               using (bucket_id = 'avatars')$p$;
    execute $p$create policy avatars_write_own on storage.objects for insert to authenticated
               with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)$p$;
    execute $p$create policy avatars_update_own on storage.objects for update to authenticated
               using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)$p$;
    execute $p$create policy avatars_delete_own on storage.objects for delete to authenticated
               using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)$p$;
  end if;
end $$;

-- قائمة الفريق مع الجوال والصورة
drop function team_members();
create function team_members()
returns table (
  id uuid, name text, email text, role user_role, job_title text,
  is_active boolean, pending boolean, open_tasks bigint, open_requests bigint,
  permissions jsonb, locale text, phone text, avatar_url text
)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.email, p.role, p.job_title, p.is_active,
         (u.last_sign_in_at is null) as pending,
         (select count(*) from tasks t where t.assignee_id = p.id and t.status <> 'done' and t.deleted_at is null),
         (select count(*) from requests r where r.assignee_id = p.id and r.deleted_at is null
            and r.status not in ('closed', 'cancelled')),
         p.permissions,
         p.locale,
         p.phone,
         p.avatar_url
  from profiles p
  left join auth.users u on u.id = p.id
  where has_perm('team.view') or p.id = auth.uid()
  order by (p.role = 'owner') desc, p.role, p.name
$$;

grant execute on function team_members() to authenticated;

-- ---------------------------------------------------------------------
-- ٤. حذف عضو نهائيًا: نقل أعماله لعضو آخر (تستدعيها دالة admin-users)
-- ---------------------------------------------------------------------
create or replace function transfer_member_work(p_from uuid, p_to uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_from = p_to then raise exception 'اختر عضوًا آخر'; end if;
  update tasks     set assignee_id = p_to where assignee_id = p_from;
  update requests  set assignee_id = p_to where assignee_id = p_from;
  update projects  set manager_id  = p_to where manager_id  = p_from;
  update followups set owner_id    = p_to where owner_id    = p_from;
  update decisions set owner_id    = p_to where owner_id    = p_from;
end $$;

revoke execute on function transfer_member_work(uuid, uuid) from public, anon, authenticated;
grant execute on function transfer_member_work(uuid, uuid) to service_role;
