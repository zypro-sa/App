-- =====================================================================
-- خطوات الطلب، وشروط الدفع، وخيارات جديدة لنوع الخدمة
-- =====================================================================

-- ١. خطوات الطلب: كل خطوة تُؤشَّر «تمت» أو «لم تتم»، ونسبة الإنجاز تُحسب منها
create table request_steps (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references requests (id) on delete cascade,
  title       text not null,
  is_done     boolean not null default false,
  done_at     timestamptz,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at  timestamptz
);

create index on request_steps (request_id, sort_order) where deleted_at is null;

create trigger set_updated_at before update on request_steps
  for each row execute function set_updated_at();

create or replace function request_steps_done_at() returns trigger
language plpgsql as $$
begin
  if new.is_done and (tg_op = 'INSERT' or not old.is_done) then
    new.done_at := now();
  elsif not new.is_done then
    new.done_at := null;
  end if;
  return new;
end $$;

create trigger request_steps_done_at before insert or update of is_done on request_steps
  for each row execute function request_steps_done_at();

create or replace function recalc_request_progress() returns trigger
language plpgsql security definer set search_path = public as $$
declare rid uuid := coalesce(new.request_id, old.request_id);
begin
  update requests set progress = coalesce((
    select round(100.0 * count(*) filter (where is_done) / nullif(count(*), 0))
    from request_steps where request_id = rid and deleted_at is null), progress)
  where id = rid and status not in ('closed', 'cancelled');
  return null;
end $$;

create trigger request_steps_recalc
  after insert or update or delete on request_steps
  for each row execute function recalc_request_progress();

alter table request_steps enable row level security;

-- يرى الخطوات من يرى الطلب
create policy request_steps_select on request_steps for select to authenticated
  using (exists (select 1 from requests r where r.id = request_steps.request_id));
-- يعدّلها من يدير الطلبات أو المسؤول عن الطلب
create policy request_steps_write on request_steps for all to authenticated
  using (has_perm('requests.manage')
         or exists (select 1 from requests r where r.id = request_steps.request_id and r.assignee_id = auth.uid()))
  with check (has_perm('requests.manage')
         or exists (select 1 from requests r where r.id = request_steps.request_id and r.assignee_id = auth.uid()));

grant select, insert, update, delete on request_steps to authenticated;
grant all on request_steps to service_role;

-- ٢. شروط الدفع
alter table requests add column payment_terms text;

insert into field_settings (entity, key, label, type, options, is_system, is_locked, required, visible, show_on_card, sort_order, created_by)
values ('request', 'payment_terms', 'شروط الدفع', 'list',
        '{"مقدم كامل قبل البدء","٥٠٪ مقدم و٥٠٪ عند التسليم","دفعات حسب المراحل","كامل المبلغ عند التسليم","أقساط شهرية"}',
        true, false, false, true, true, 9, null)
on conflict (entity, key) do nothing;

-- ٣. خيارات نوع الخدمة المناسبة لأعمال الشركة
update field_settings
set options = options || array(
  select o from unnest('{"تراخيص وتصاريح حكومية","باقات خدمات الأعمال"}'::text[]) as o
  where not o = any(options)
)
where entity = 'request' and key = 'service_type';
