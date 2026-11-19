-- =====================================================================
-- المساعد الشخصي — الهيكل الأولي لقاعدة البيانات
-- مبني على docs/data-model.md
-- =====================================================================

-- ---------------------------------------------------------------------
-- القوائم (Enums)
-- ---------------------------------------------------------------------
create type user_role          as enum ('owner', 'manager', 'employee');
create type client_type        as enum ('company', 'government', 'individual');
create type client_status      as enum ('lead', 'active', 'inactive');
create type client_source      as enum ('referral', 'website', 'exhibition', 'direct', 'other');
create type request_status     as enum ('new', 'in_progress', 'waiting_client', 'on_hold', 'closed', 'cancelled');
create type priority_level     as enum ('low', 'medium', 'high', 'urgent');
create type request_channel    as enum ('email', 'call', 'whatsapp', 'meeting', 'website');
create type task_status        as enum ('todo', 'in_progress', 'done');
create type meeting_type       as enum ('in_person', 'online', 'call');
create type meeting_status     as enum ('scheduled', 'done', 'cancelled', 'postponed');
create type attendance_status  as enum ('invited', 'confirmed', 'attended', 'absent');
create type project_status     as enum ('planning', 'active', 'on_hold', 'completed', 'cancelled');
create type followup_direction as enum ('promised', 'waiting');
create type followup_status    as enum ('open', 'done', 'snoozed');
create type followup_source    as enum ('manual', 'meeting', 'auto');
create type quote_status       as enum ('draft', 'sent', 'accepted', 'rejected', 'expired');
create type invoice_status     as enum ('issued', 'partially_paid', 'paid', 'overdue', 'void');
create type payment_method     as enum ('bank_transfer', 'cash', 'cheque', 'other');
create type note_type          as enum ('idea', 'call', 'general');
create type notification_type  as enum ('meeting_soon', 'task_due', 'request_overdue', 'followup_due', 'assigned', 'quote_no_reply');
create type related_entity     as enum ('client', 'contact', 'request', 'task', 'meeting', 'project', 'quote', 'invoice', 'note', 'followup');

-- ---------------------------------------------------------------------
-- دالة تحديث updated_at تلقائيًا
-- ---------------------------------------------------------------------
create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- ١. المستخدمون (مرتبطون بحسابات Supabase Auth)
-- ---------------------------------------------------------------------
create table profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  name        text not null,
  email       text not null unique,
  phone       text,
  role        user_role not null default 'employee',
  job_title   text,
  avatar_url  text,
  timezone    text not null default 'Asia/Riyadh',
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- إنشاء ملف المستخدم تلقائيًا عند التسجيل
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- أول مستخدم يسجّل يصبح المالك تلقائيًا
  insert into public.profiles (id, name, email, role)
  values (new.id,
          coalesce(new.raw_user_meta_data ->> 'name', new.email),
          new.email,
          case when exists (select 1 from public.profiles) then 'employee'::user_role
               else 'owner'::user_role end);
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- دوال مساعدة للصلاحيات
create or replace function current_user_role() returns user_role
language sql stable security definer set search_path = public as $$
  select role from profiles where id = auth.uid() and is_active
$$;

create or replace function is_manager_or_owner() returns boolean
language sql stable as $$
  select coalesce(current_user_role() in ('owner', 'manager'), false)
$$;

create or replace function is_owner() returns boolean
language sql stable as $$
  select coalesce(current_user_role() = 'owner', false)
$$;

-- ---------------------------------------------------------------------
-- الأعمدة المشتركة تُكرَّر في كل جدول:
-- id, created_at, updated_at, created_by, deleted_at
-- ---------------------------------------------------------------------

-- ٢. العملاء
create table clients (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  type                client_type not null default 'company',
  status              client_status not null default 'lead',
  sector              text,
  cr_number           text,
  vat_number          text,
  city                text,
  address             text,
  source              client_source,
  account_manager_id  uuid references profiles (id) on delete set null,
  tags                text[] not null default '{}',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at          timestamptz
);

-- ٣. جهات التواصل
create table contacts (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references clients (id) on delete cascade,
  name        text not null,
  position    text,
  phone       text,
  email       text,
  is_primary  boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at  timestamptz
);

-- ٧. المشاريع (قبل الطلبات لأنها تشير إليها)
create table projects (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  client_id       uuid not null references clients (id) on delete restrict,
  manager_id      uuid references profiles (id) on delete set null,
  status          project_status not null default 'planning',
  start_date      date,
  end_date        date,
  contract_value  numeric(14, 2),
  currency        char(3) not null default 'SAR',
  progress        smallint not null default 0 check (progress between 0 and 100),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at      timestamptz
);

create table milestones (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references projects (id) on delete cascade,
  title       text not null,
  due_date    date,
  is_done     boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at  timestamptz
);

-- ٤. الطلبات
create sequence request_number_seq start 1001;

create table requests (
  id               uuid primary key default gen_random_uuid(),
  number           integer not null unique default nextval('request_number_seq'),
  title            text not null,
  description      text,
  client_id        uuid not null references clients (id) on delete restrict,
  contact_id       uuid references contacts (id) on delete set null,
  project_id       uuid references projects (id) on delete set null,
  service_type     text,
  status           request_status not null default 'new',
  priority         priority_level not null default 'medium',
  assignee_id      uuid references profiles (id) on delete set null,
  received_at      timestamptz not null default now(),
  due_date         date,
  closed_at        timestamptz,
  progress         smallint not null default 0 check (progress between 0 and 100),
  estimated_value  numeric(14, 2),
  currency         char(3) not null default 'SAR',
  channel          request_channel,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at       timestamptz
);
alter sequence request_number_seq owned by requests.number;

-- ٥. المهام
create table tasks (
  id                  uuid primary key default gen_random_uuid(),
  title               text not null,
  description         text,
  status              task_status not null default 'todo',
  priority            priority_level not null default 'medium',
  assignee_id         uuid not null references profiles (id) on delete restrict default auth.uid(),
  assigned_by_id      uuid references profiles (id) on delete set null default auth.uid(),
  due_at              timestamptz,
  completed_at        timestamptz,
  request_id          uuid references requests (id) on delete set null,
  project_id          uuid references projects (id) on delete set null,
  client_id           uuid references clients (id) on delete set null,
  source_decision_id  uuid,  -- يُربط بجدول القرارات أدناه
  reminder_at         timestamptz,
  recurrence          text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at          timestamptz
);

-- ٦. الاجتماعات
create table meetings (
  id                    uuid primary key default gen_random_uuid(),
  title                 text not null,
  start_at              timestamptz not null,
  end_at                timestamptz not null,
  type                  meeting_type not null default 'in_person',
  location              text,
  meeting_url           text,
  client_id             uuid references clients (id) on delete set null,
  request_id            uuid references requests (id) on delete set null,
  project_id            uuid references projects (id) on delete set null,
  status                meeting_status not null default 'scheduled',
  minutes               text,
  external_calendar_id  text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  created_by            uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at            timestamptz,
  check (end_at > start_at)
);

create table agenda_items (
  id          uuid primary key default gen_random_uuid(),
  meeting_id  uuid not null references meetings (id) on delete cascade,
  "order"     smallint not null,
  title       text not null,
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at  timestamptz
);

create table meeting_attendees (
  id          uuid primary key default gen_random_uuid(),
  meeting_id  uuid not null references meetings (id) on delete cascade,
  user_id     uuid references profiles (id) on delete cascade,
  contact_id  uuid references contacts (id) on delete cascade,
  attendance  attendance_status not null default 'invited',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at  timestamptz,
  check (num_nonnulls(user_id, contact_id) = 1)
);

create table decisions (
  id          uuid primary key default gen_random_uuid(),
  meeting_id  uuid not null references meetings (id) on delete cascade,
  text        text not null,
  owner_id    uuid references profiles (id) on delete set null,
  due_date    date,
  task_id     uuid references tasks (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at  timestamptz
);

alter table tasks
  add constraint tasks_source_decision_fk
  foreign key (source_decision_id) references decisions (id) on delete set null;

-- ٨. المتابعات
create table followups (
  id             uuid primary key default gen_random_uuid(),
  title          text not null,
  direction      followup_direction not null,
  owner_id       uuid not null references profiles (id) on delete cascade default auth.uid(),
  counterpart    text,
  due_at         timestamptz not null,
  status         followup_status not null default 'open',
  snoozed_until  timestamptz,
  related_type   related_entity,
  related_id     uuid,
  source         followup_source not null default 'manual',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at     timestamptz,
  check ((related_type is null) = (related_id is null))
);

-- ٩. المالية المختصرة
create table quotes (
  id           uuid primary key default gen_random_uuid(),
  number       text not null unique,
  client_id    uuid not null references clients (id) on delete restrict,
  request_id   uuid references requests (id) on delete set null,
  amount       numeric(14, 2) not null check (amount >= 0),
  vat_amount   numeric(14, 2) not null default 0 check (vat_amount >= 0),
  currency     char(3) not null default 'SAR',
  status       quote_status not null default 'draft',
  sent_at      date,
  valid_until  date,
  file_url     text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at   timestamptz
);

create table invoices (
  id          uuid primary key default gen_random_uuid(),
  number      text not null unique,
  client_id   uuid not null references clients (id) on delete restrict,
  project_id  uuid references projects (id) on delete set null,
  quote_id    uuid references quotes (id) on delete set null,
  total       numeric(14, 2) not null check (total >= 0),
  currency    char(3) not null default 'SAR',
  issue_date  date not null default current_date,
  due_date    date not null,
  status      invoice_status not null default 'issued',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at  timestamptz
);

create table payments (
  id          uuid primary key default gen_random_uuid(),
  invoice_id  uuid not null references invoices (id) on delete cascade,
  amount      numeric(14, 2) not null check (amount > 0),
  paid_at     date not null default current_date,
  method      payment_method,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at  timestamptz
);

-- ١٠. الملاحظات
create table notes (
  id                 uuid primary key default gen_random_uuid(),
  content            text not null,
  type               note_type not null default 'general',
  is_pinned          boolean not null default false,
  related_type       related_entity,
  related_id         uuid,
  converted_task_id  uuid references tasks (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at         timestamptz,
  check ((related_type is null) = (related_id is null))
);

-- ١١. كيانات مساندة
create table attachments (
  id            uuid primary key default gen_random_uuid(),
  file_name     text not null,
  file_url      text not null,
  mime_type     text,
  size          bigint,
  related_type  related_entity not null,
  related_id    uuid not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at    timestamptz
);

create table notifications (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles (id) on delete cascade,
  type          notification_type not null,
  title         text not null,
  related_type  related_entity,
  related_id    uuid,
  send_at       timestamptz not null default now(),
  read_at       timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table activity_log (
  id            uuid primary key default gen_random_uuid(),
  actor_id      uuid references profiles (id) on delete set null default auth.uid(),
  action        text not null,
  related_type  related_entity not null,
  related_id    uuid not null,
  client_id     uuid references clients (id) on delete cascade,
  changes       jsonb,
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- الفهارس (للشاشات الأكثر استخدامًا)
-- ---------------------------------------------------------------------
create index on contacts (client_id);
create index on projects (client_id);
create index on milestones (project_id);
create index on requests (client_id);
create index on requests (status, due_date) where deleted_at is null;
create index on requests (assignee_id) where deleted_at is null;
create index on tasks (assignee_id, status, due_at) where deleted_at is null;
create index on tasks (assigned_by_id) where deleted_at is null;
create index on tasks (request_id);
create index on meetings (start_at) where deleted_at is null;
create index on meetings (client_id);
create index on agenda_items (meeting_id, "order");
create index on meeting_attendees (meeting_id);
create index on meeting_attendees (user_id);
create index on decisions (meeting_id);
create index on followups (owner_id, status, due_at) where deleted_at is null;
create index on followups (related_type, related_id);
create index on quotes (client_id, status);
create index on invoices (client_id, status);
create index on payments (invoice_id);
create index on notes (related_type, related_id);
create index on attachments (related_type, related_id);
create index on notifications (user_id, read_at, send_at);
create index on activity_log (client_id, created_at desc);
create index on activity_log (related_type, related_id);

-- ---------------------------------------------------------------------
-- محفّزات updated_at
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'profiles', 'clients', 'contacts', 'projects', 'milestones', 'requests',
    'tasks', 'meetings', 'agenda_items', 'meeting_attendees', 'decisions',
    'followups', 'quotes', 'invoices', 'payments', 'notes', 'attachments',
    'notifications'
  ] loop
    execute format(
      'create trigger set_updated_at before update on %I
         for each row execute function set_updated_at()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- قواعد تلقائية
-- ---------------------------------------------------------------------

-- تاريخ إغلاق الطلب، ومتابعة تلقائية عند «بانتظار العميل»
create or replace function requests_status_rules() returns trigger
language plpgsql as $$
begin
  if new.status = 'closed' and (tg_op = 'INSERT' or old.status is distinct from 'closed') then
    new.closed_at := now();
    new.progress  := 100;
  elsif new.status <> 'closed' then
    new.closed_at := null;
  end if;

  if new.status = 'waiting_client'
     and (tg_op = 'INSERT' or old.status is distinct from 'waiting_client')
     and coalesce(new.assignee_id, auth.uid()) is not null then
    insert into followups (title, direction, owner_id, due_at, related_type, related_id, source)
    values ('متابعة رد العميل على الطلب #' || new.number, 'waiting',
            coalesce(new.assignee_id, auth.uid()), now() + interval '3 days',
            'request', new.id, 'auto');
  end if;
  return new;
end $$;

create trigger requests_status_rules
  before insert or update of status on requests
  for each row execute function requests_status_rules();

-- وقت إنجاز المهمة
create or replace function tasks_completion() returns trigger
language plpgsql as $$
begin
  if new.status = 'done' and (tg_op = 'INSERT' or old.status is distinct from 'done') then
    new.completed_at := now();
  elsif new.status <> 'done' then
    new.completed_at := null;
  end if;
  return new;
end $$;

create trigger tasks_completion
  before insert or update of status on tasks
  for each row execute function tasks_completion();

-- ---------------------------------------------------------------------
-- عروض جاهزة للشاشات
-- ---------------------------------------------------------------------

-- الطلبات مع حالة التأخر
create view requests_view with (security_invoker = true) as
select r.*,
       c.name as client_name,
       coalesce(r.due_date < current_date and r.status not in ('closed', 'cancelled'), false) as is_overdue
from requests r
join clients c on c.id = r.client_id
where r.deleted_at is null;

-- ملخص ملف العميل
create view client_summary with (security_invoker = true) as
select c.id,
       c.name,
       (select count(*) from requests r
         where r.client_id = c.id and r.deleted_at is null
           and r.status not in ('closed', 'cancelled'))                    as open_requests,
       (select coalesce(sum(p.contract_value), 0) from projects p
         where p.client_id = c.id and p.deleted_at is null)               as contracts_value,
       (select coalesce(sum(i.total - (select coalesce(sum(pm.amount), 0) from payments pm
                                         where pm.invoice_id = i.id and pm.deleted_at is null)), 0)
          from invoices i
         where i.client_id = c.id and i.deleted_at is null
           and i.status not in ('paid', 'void'))                          as amount_due,
       (select max(a.created_at) from activity_log a where a.client_id = c.id) as last_activity_at
from clients c
where c.deleted_at is null;

-- ---------------------------------------------------------------------
-- الصلاحيات (Row Level Security)
-- المالك والمدير: كل البيانات التشغيلية
-- الموظف: المسند إليه فقط، وقراءة العملاء
-- المالية: المالك فقط
-- ---------------------------------------------------------------------
alter table profiles          enable row level security;
alter table clients           enable row level security;
alter table contacts          enable row level security;
alter table projects          enable row level security;
alter table milestones        enable row level security;
alter table requests          enable row level security;
alter table tasks             enable row level security;
alter table meetings          enable row level security;
alter table agenda_items      enable row level security;
alter table meeting_attendees enable row level security;
alter table decisions         enable row level security;
alter table followups         enable row level security;
alter table quotes            enable row level security;
alter table invoices          enable row level security;
alter table payments          enable row level security;
alter table notes             enable row level security;
alter table attachments       enable row level security;
alter table notifications     enable row level security;
alter table activity_log      enable row level security;

-- المستخدمون: الجميع يرى الفريق، وكلٌّ يعدّل ملفه، والمالك يدير الكل
create policy profiles_select on profiles for select to authenticated using (true);
create policy profiles_update_self on profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and role = current_user_role());  -- لا يغيّر دوره بنفسه
create policy profiles_owner_all on profiles for all to authenticated
  using (is_owner()) with check (is_owner());

-- العملاء وجهات التواصل: قراءة للجميع، تعديل للمالك والمدير
create policy clients_select on clients for select to authenticated using (true);
create policy clients_write  on clients for all    to authenticated
  using (is_manager_or_owner()) with check (is_manager_or_owner());
create policy contacts_select on contacts for select to authenticated using (true);
create policy contacts_write  on contacts for all    to authenticated
  using (is_manager_or_owner()) with check (is_manager_or_owner());

-- المشاريع: المالك والمدير، ومدير المشروع يقرأ مشروعه
create policy projects_manage on projects for all to authenticated
  using (is_manager_or_owner()) with check (is_manager_or_owner());
create policy projects_select_own on projects for select to authenticated
  using (manager_id = auth.uid());
create policy milestones_manage on milestones for all to authenticated
  using (is_manager_or_owner()) with check (is_manager_or_owner());

-- الطلبات: المالك والمدير كاملًا، والموظف يرى ويحدّث المسند إليه
create policy requests_manage on requests for all to authenticated
  using (is_manager_or_owner()) with check (is_manager_or_owner());
create policy requests_select_assigned on requests for select to authenticated
  using (assignee_id = auth.uid());
create policy requests_update_assigned on requests for update to authenticated
  using (assignee_id = auth.uid()) with check (assignee_id = auth.uid());

-- المهام: الموظف يرى ما أُسند إليه أو ما أسنده، وينشئ مهامه لنفسه
create policy tasks_manage on tasks for all to authenticated
  using (is_manager_or_owner()) with check (is_manager_or_owner());
create policy tasks_select_own on tasks for select to authenticated
  using (assignee_id = auth.uid() or assigned_by_id = auth.uid());
create policy tasks_insert_self on tasks for insert to authenticated
  with check (assignee_id = auth.uid());
create policy tasks_update_own on tasks for update to authenticated
  using (assignee_id = auth.uid()) with check (assignee_id = auth.uid());

-- الاجتماعات: المالك والمدير كاملًا، والموظف يرى ما يحضره
create policy meetings_manage on meetings for all to authenticated
  using (is_manager_or_owner()) with check (is_manager_or_owner());
create policy meetings_select_attendee on meetings for select to authenticated
  using (exists (select 1 from meeting_attendees ma
                  where ma.meeting_id = meetings.id and ma.user_id = auth.uid()));

create policy agenda_manage on agenda_items for all to authenticated
  using (is_manager_or_owner()) with check (is_manager_or_owner());
create policy agenda_select_attendee on agenda_items for select to authenticated
  using (exists (select 1 from meeting_attendees ma
                  where ma.meeting_id = agenda_items.meeting_id and ma.user_id = auth.uid()));

create policy attendees_manage on meeting_attendees for all to authenticated
  using (is_manager_or_owner()) with check (is_manager_or_owner());
create policy attendees_select_self on meeting_attendees for select to authenticated
  using (user_id = auth.uid());

create policy decisions_manage on decisions for all to authenticated
  using (is_manager_or_owner()) with check (is_manager_or_owner());
create policy decisions_select_owner on decisions for select to authenticated
  using (owner_id = auth.uid());

-- المتابعات: كل مستخدم يدير متابعاته، والمالك والمدير يرون الجميع
create policy followups_own on followups for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy followups_manage on followups for all to authenticated
  using (is_manager_or_owner()) with check (is_manager_or_owner());

-- المالية: المالك فقط
create policy quotes_owner   on quotes   for all to authenticated using (is_owner()) with check (is_owner());
create policy invoices_owner on invoices for all to authenticated using (is_owner()) with check (is_owner());
create policy payments_owner on payments for all to authenticated using (is_owner()) with check (is_owner());

-- الملاحظات: شخصية لكاتبها
create policy notes_own on notes for all to authenticated
  using (created_by = auth.uid()) with check (created_by = auth.uid());

-- المرفقات: يراها من يرى العنصر (مبسّط: كاتبها أو المالك والمدير)
create policy attachments_own on attachments for all to authenticated
  using (created_by = auth.uid()) with check (created_by = auth.uid());
create policy attachments_manage on attachments for all to authenticated
  using (is_manager_or_owner()) with check (is_manager_or_owner());

-- الإشعارات: لصاحبها فقط (تُنشأ من الخادم)
create policy notifications_own_select on notifications for select to authenticated
  using (user_id = auth.uid());
create policy notifications_own_update on notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- سجل النشاط: قراءة للمالك والمدير، وإضافة من أي مستخدم باسمه
create policy activity_select on activity_log for select to authenticated
  using (is_manager_or_owner());
create policy activity_insert on activity_log for insert to authenticated
  with check (actor_id = auth.uid());
