-- =====================================================================
-- المرحلة الثانية: لوحة التحكم (الحقول والقوائم)، الحقول المخصصة،
-- سلة المحذوفات، المالية، المشاريع، التقارير، الفريق
-- =====================================================================

-- ---------------------------------------------------------------------
-- ١. إعدادات الحقول (الأساسية والمخصصة) لكل قسم
-- ---------------------------------------------------------------------
create type field_type    as enum ('text', 'number', 'date', 'list', 'bool', 'money');
create type config_entity as enum ('request', 'task', 'meeting', 'client', 'project');

create table field_settings (
  id            uuid primary key default gen_random_uuid(),
  entity        config_entity not null,
  key           text not null,             -- اسم العمود للحقول الأساسية، أو cf_xxx للمخصصة
  label         text not null,
  type          field_type not null default 'text',
  options       text[] not null default '{}',
  is_system     boolean not null default false,  -- حقل أساسي في الجدول
  is_locked     boolean not null default false,  -- لا يمكن إخفاؤه أو جعله اختياريًا
  required      boolean not null default false,
  visible       boolean not null default true,
  show_on_card  boolean not null default false,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at    timestamptz,
  unique (entity, key)
);

create trigger set_updated_at before update on field_settings
  for each row execute function set_updated_at();

-- منع تعديل خصائص الحقول المقفلة أو تحويل حقل أساسي لمخصص
create or replace function field_settings_guard() returns trigger
language plpgsql as $$
begin
  if old.is_locked and (new.visible is distinct from old.visible
                        or new.required is distinct from old.required
                        or new.deleted_at is not null) then
    raise exception 'هذا الحقل أساسي ولا يمكن إخفاؤه أو حذفه';
  end if;
  if old.is_system and new.deleted_at is not null then
    raise exception 'الحقول الأساسية لا تُحذف، يمكن إخفاؤها فقط';
  end if;
  new.is_system := old.is_system;
  new.is_locked := old.is_locked;
  new.key := old.key;
  new.entity := old.entity;
  return new;
end $$;

create trigger field_settings_guard before update on field_settings
  for each row execute function field_settings_guard();

-- الحقول الأساسية الافتراضية
insert into field_settings (entity, key, label, type, options, is_system, is_locked, required, visible, show_on_card, sort_order, created_by) values
  ('request', 'title',           'العنوان',          'text',  '{}', true, true,  true,  true,  true,  1, null),
  ('request', 'client_id',       'العميل',           'list',  '{}', true, true,  true,  true,  true,  2, null),
  ('request', 'status',          'الحالة',           'list',  '{}', true, true,  true,  true,  true,  3, null),
  ('request', 'service_type',    'نوع الخدمة',       'list',  '{"استشارات إدارية","دراسات جدوى","سياسات وإجراءات","تدريب"}', true, false, false, true, false, 4, null),
  ('request', 'priority',        'الأولوية',         'list',  '{}', true, false, false, true,  true,  5, null),
  ('request', 'due_date',        'الموعد النهائي',   'date',  '{}', true, false, false, true,  true,  6, null),
  ('request', 'estimated_value', 'القيمة التقديرية', 'money', '{}', true, false, false, false, false, 7, null),
  ('request', 'description',     'التفاصيل',         'text',  '{}', true, false, false, true,  false, 8, null),

  ('task', 'title',     'العنوان',      'text', '{}', true, true,  true,  true, true, 1, null),
  ('task', 'priority',  'الأولوية',     'list', '{}', true, false, false, true, true, 2, null),
  ('task', 'due_at',    'الموعد',       'date', '{}', true, false, false, true, true, 3, null),
  ('task', 'client_id', 'العميل',       'list', '{}', true, false, false, true, true, 4, null),
  ('task', 'assignee_id','المسؤول',     'list', '{}', true, false, false, true, true, 5, null),

  ('meeting', 'title',     'العنوان', 'text', '{}', true, true,  true,  true, true, 1, null),
  ('meeting', 'start_at',  'الموعد',  'date', '{}', true, true,  true,  true, true, 2, null),
  ('meeting', 'type',      'النوع',   'list', '{}', true, false, false, true, true, 3, null),
  ('meeting', 'location',  'المكان',  'text', '{}', true, false, false, true, true, 4, null),
  ('meeting', 'client_id', 'العميل',  'list', '{}', true, false, false, true, true, 5, null),

  ('client', 'name',       'الاسم',            'text', '{}', true, true,  true,  true,  true,  1, null),
  ('client', 'sector',     'القطاع',           'list', '{"تقنية","تجزئة","صناعة","حكومي","خدمات مالية"}', true, false, false, true, true, 2, null),
  ('client', 'city',       'المدينة',          'text', '{}', true, false, false, true,  true,  3, null),
  ('client', 'cr_number',  'السجل التجاري',    'text', '{}', true, false, false, true,  false, 4, null),
  ('client', 'vat_number', 'الرقم الضريبي',    'text', '{}', true, false, false, true,  false, 5, null),

  ('project', 'name',           'اسم المشروع', 'text',  '{}', true, true,  true,  true, true,  1, null),
  ('project', 'client_id',      'العميل',      'list',  '{}', true, true,  true,  true, true,  2, null),
  ('project', 'end_date',       'تاريخ التسليم','date', '{}', true, false, false, true, true,  3, null),
  ('project', 'contract_value', 'قيمة العقد',  'money', '{}', true, false, false, true, false, 4, null);

-- ---------------------------------------------------------------------
-- ٢. أسماء الحالات وألوانها (قابلة للتعديل، غير قابلة للحذف)
-- ---------------------------------------------------------------------
create table status_labels (
  entity      config_entity not null,
  status      text not null,
  label       text not null,
  color       text not null default 'neutral',  -- info | neutral | waiting | done | urgent
  sort_order  integer not null default 0,
  primary key (entity, status)
);

insert into status_labels (entity, status, label, color, sort_order) values
  ('request', 'new',            'جديد',            'info',    1),
  ('request', 'in_progress',    'قيد التنفيذ',     'neutral', 2),
  ('request', 'waiting_client', 'بانتظار العميل',  'waiting', 3),
  ('request', 'on_hold',        'معلّق',           'neutral', 4),
  ('request', 'closed',         'مغلق',            'done',    5),
  ('request', 'cancelled',      'ملغى',            'urgent',  6),
  ('project', 'planning',       'تخطيط',           'info',    1),
  ('project', 'active',         'جارٍ',            'done',    2),
  ('project', 'on_hold',        'معلّق',           'waiting', 3),
  ('project', 'completed',      'مكتمل',           'neutral', 4),
  ('project', 'cancelled',      'ملغى',            'urgent',  5);

-- ---------------------------------------------------------------------
-- ٣. قيم الحقول المخصصة
-- ---------------------------------------------------------------------
alter table requests add column custom jsonb not null default '{}';
alter table tasks    add column custom jsonb not null default '{}';
alter table meetings add column custom jsonb not null default '{}';
alter table clients  add column custom jsonb not null default '{}';
alter table projects add column custom jsonb not null default '{}';

-- ---------------------------------------------------------------------
-- ٤. سلة المحذوفات: من حذف، ومتى، والحذف النهائي بعد ٣٠ يومًا
-- ---------------------------------------------------------------------
create or replace function track_deleted_by() returns trigger
language plpgsql as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    new.deleted_by := auth.uid();
  elsif new.deleted_at is null then
    new.deleted_by := null;
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['requests', 'tasks', 'meetings', 'clients', 'projects',
                           'notes', 'followups', 'quotes', 'invoices'] loop
    execute format('alter table %I add column deleted_by uuid references profiles (id) on delete set null', t);
    execute format(
      'create trigger track_deleted_by before update of deleted_at on %I
         for each row execute function track_deleted_by()', t);
  end loop;
end $$;

create view trash_items with (security_invoker = true) as
          select 'request'::text as entity, id, '#' || number || ' · ' || title as title, deleted_at, deleted_by from requests where deleted_at is not null
union all select 'task',     id, title,   deleted_at, deleted_by from tasks     where deleted_at is not null
union all select 'meeting',  id, title,   deleted_at, deleted_by from meetings  where deleted_at is not null
union all select 'client',   id, name,    deleted_at, deleted_by from clients   where deleted_at is not null
union all select 'project',  id, name,    deleted_at, deleted_by from projects  where deleted_at is not null
union all select 'note',     id, left(content, 60), deleted_at, deleted_by from notes where deleted_at is not null
union all select 'followup', id, title,   deleted_at, deleted_by from followups where deleted_at is not null
union all select 'quote',    id, number,  deleted_at, deleted_by from quotes    where deleted_at is not null
union all select 'invoice',  id, number,  deleted_at, deleted_by from invoices  where deleted_at is not null;

-- الحذف النهائي لما مضى عليه ٣٠ يومًا (يعمل يوميًا إن توفر pg_cron)
create or replace function purge_trash(older_than interval default interval '30 days')
returns integer language plpgsql security definer set search_path = public as $$
declare
  cutoff timestamptz := now() - older_than;
  n integer := 0;
  c integer;
begin
  delete from tasks     where deleted_at < cutoff; get diagnostics c = row_count; n := n + c;
  delete from followups where deleted_at < cutoff; get diagnostics c = row_count; n := n + c;
  delete from notes     where deleted_at < cutoff; get diagnostics c = row_count; n := n + c;
  delete from meetings  where deleted_at < cutoff; get diagnostics c = row_count; n := n + c;
  delete from invoices  where deleted_at < cutoff; get diagnostics c = row_count; n := n + c;
  delete from quotes    where deleted_at < cutoff
    and not exists (select 1 from invoices i where i.quote_id = quotes.id);
  get diagnostics c = row_count; n := n + c;
  delete from requests  where deleted_at < cutoff
    and not exists (select 1 from quotes q where q.request_id = requests.id); -- يبقى إن ارتبط بعرض سعر
  get diagnostics c = row_count; n := n + c;
  delete from projects  where deleted_at < cutoff
    and not exists (select 1 from requests r where r.project_id = projects.id);
  get diagnostics c = row_count; n := n + c;
  delete from clients   where deleted_at < cutoff
    and not exists (select 1 from requests r where r.client_id = clients.id)
    and not exists (select 1 from projects p where p.client_id = clients.id)
    and not exists (select 1 from quotes q where q.client_id = clients.id)
    and not exists (select 1 from invoices i where i.client_id = clients.id);
  get diagnostics c = row_count; n := n + c;
  return n;
end $$;

revoke execute on function purge_trash(interval) from public, anon, authenticated;

do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('purge-trash-daily', '0 1 * * *', 'select public.purge_trash()');
exception when others then
  raise notice 'pg_cron غير متاح، فعّله من Database › Extensions ثم شغّل: select cron.schedule(''purge-trash-daily'', ''0 1 * * *'', ''select public.purge_trash()'');';
end $$;

-- ---------------------------------------------------------------------
-- ٥. المالية: ترقيم تلقائي وتحديث حالة الفاتورة مع كل دفعة
-- ---------------------------------------------------------------------
create sequence invoice_number_seq start 1001;
create sequence quote_number_seq start 1001;
alter table invoices alter column number set default 'INV-' || nextval('invoice_number_seq');
alter table quotes   alter column number set default 'Q-' || nextval('quote_number_seq');

create or replace function recalc_invoice_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  inv_id uuid := coalesce(new.invoice_id, old.invoice_id);
  paid numeric;
  inv_total numeric;
  inv_status invoice_status;
begin
  select total, status into inv_total, inv_status from invoices where id = inv_id;
  if inv_status = 'void' then return null; end if;
  select coalesce(sum(amount), 0) into paid from payments where invoice_id = inv_id and deleted_at is null;
  update invoices set status = case
      when paid >= inv_total then 'paid'::invoice_status
      when paid > 0 then 'partially_paid'::invoice_status
      else 'issued'::invoice_status end
  where id = inv_id;
  return null;
end $$;

create trigger payments_recalc_invoice
  after insert or update or delete on payments
  for each row execute function recalc_invoice_status();

-- ---------------------------------------------------------------------
-- ٦. المشاريع: نسبة الإنجاز من المراحل، والموظف يرى مراحل مشروعه
-- ---------------------------------------------------------------------
create or replace function recalc_project_progress() returns trigger
language plpgsql security definer set search_path = public as $$
declare pid uuid := coalesce(new.project_id, old.project_id);
begin
  update projects set progress = coalesce((
    select round(100.0 * count(*) filter (where is_done) / nullif(count(*), 0))
    from milestones where project_id = pid and deleted_at is null), 0)
  where id = pid;
  return null;
end $$;

create trigger milestones_recalc_project
  after insert or update or delete on milestones
  for each row execute function recalc_project_progress();

create policy milestones_select_project_manager on milestones for select to authenticated
  using (exists (select 1 from projects p where p.id = milestones.project_id and p.manager_id = auth.uid()));
create policy milestones_update_project_manager on milestones for update to authenticated
  using (exists (select 1 from projects p where p.id = milestones.project_id and p.manager_id = auth.uid()))
  with check (exists (select 1 from projects p where p.id = milestones.project_id and p.manager_id = auth.uid()));

-- ---------------------------------------------------------------------
-- ٧. الفريق
-- ---------------------------------------------------------------------
-- قائمة الفريق مع حالة الدعوة (للمالك والمدير)
create or replace function team_members()
returns table (
  id uuid, name text, email text, role user_role, job_title text,
  is_active boolean, pending boolean, open_tasks bigint, open_requests bigint
)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.email, p.role, p.job_title, p.is_active,
         (u.last_sign_in_at is null) as pending,
         (select count(*) from tasks t where t.assignee_id = p.id and t.status <> 'done' and t.deleted_at is null),
         (select count(*) from requests r where r.assignee_id = p.id and r.deleted_at is null
            and r.status not in ('closed', 'cancelled'))
  from profiles p
  left join auth.users u on u.id = p.id
  where is_manager_or_owner() or p.id = auth.uid()
  order by (p.role = 'owner') desc, p.role, p.name
$$;

grant execute on function team_members() to authenticated;

-- يبقى دائمًا مالك نشط واحد على الأقل
create or replace function keep_one_owner() returns trigger
language plpgsql as $$
begin
  if old.role = 'owner' and (new.role <> 'owner' or not new.is_active)
     and not exists (select 1 from profiles where role = 'owner' and is_active and id <> old.id) then
    raise exception 'يجب أن يبقى مالك نشط واحد على الأقل';
  end if;
  return new;
end $$;

create trigger keep_one_owner before update of role, is_active on profiles
  for each row execute function keep_one_owner();

-- ---------------------------------------------------------------------
-- ٨. التقارير
-- ---------------------------------------------------------------------
create or replace function report_summary(p_from date, p_to date)
returns jsonb language sql stable security invoker set search_path = public as $$
  with closed as (
    select * from requests
    where deleted_at is null and status = 'closed'
      and closed_at >= p_from and closed_at < p_to + 1
  ),
  prev_closed as (
    select count(*) as c from requests
    where deleted_at is null and status = 'closed'
      and closed_at >= p_from - (p_to - p_from + 1) and closed_at < p_from
  ),
  done_tasks as (
    select * from tasks
    where deleted_at is null and status = 'done'
      and completed_at >= p_from and completed_at < p_to + 1
  )
  select jsonb_build_object(
    'closed_requests', (select count(*) from closed),
    'previous_closed_requests', (select c from prev_closed),
    'avg_days', (select round((avg(extract(epoch from closed_at - received_at)) / 86400)::numeric, 1) from closed),
    'on_time_pct', (select round(100.0 * count(*) filter (where due_date is null or closed_at::date <= due_date)
                                / nullif(count(*), 0)) from closed),
    'tasks_done', (select count(*) from done_tasks),
    'tasks_total', (select count(*) from tasks where deleted_at is null
                      and ((due_at >= p_from and due_at < p_to + 1)
                           or (completed_at >= p_from and completed_at < p_to + 1))),
    'weekly', (select coalesce(jsonb_agg(jsonb_build_object('week', wk, 'count', c) order by wk), '[]'::jsonb)
               from (select date_trunc('week', closed_at)::date as wk, count(*) as c from closed group by 1) w),
    'team', (select coalesce(jsonb_agg(jsonb_build_object('name', p.name, 'done', t.done, 'on_time_pct', t.on_time)
                                       order by t.on_time desc nulls last), '[]'::jsonb)
             from (select assignee_id, count(*) as done,
                          round(100.0 * count(*) filter (where due_at is null or completed_at <= due_at + interval '1 day')
                                / count(*)) as on_time
                   from done_tasks group by assignee_id) t
             join profiles p on p.id = t.assignee_id)
  )
$$;

grant execute on function report_summary(date, date) to authenticated;

-- ---------------------------------------------------------------------
-- ٩. صلاحيات الجداول الجديدة
-- ---------------------------------------------------------------------
alter table field_settings enable row level security;
alter table status_labels  enable row level security;

create policy field_settings_select on field_settings for select to authenticated using (true);
create policy field_settings_owner  on field_settings for all to authenticated
  using (is_owner()) with check (is_owner());
create policy field_settings_manager_update on field_settings for update to authenticated
  using (current_user_role() = 'manager') with check (current_user_role() = 'manager');

create policy status_labels_select on status_labels for select to authenticated using (true);
create policy status_labels_owner  on status_labels for update to authenticated
  using (is_owner()) with check (is_owner());

grant select, insert, update, delete on field_settings, status_labels to authenticated;
grant select on trash_items to authenticated;
grant usage, select on sequence invoice_number_seq, quote_number_seq to authenticated;
