-- =====================================================================
-- المزامنة مع دفترة
-- دفترة هي المصدر الرسمي للعملاء والفواتير والدفعات والمرتجعات وعروض الأسعار.
-- التطبيق يقرأ منها فقط (لا يكتب فيها)، وتعمل المزامنة عبر الدالة daftra-sync.
-- =====================================================================

-- ربط كل سجل برقمه في دفترة
alter table clients         add column if not exists daftra_id bigint;
alter table invoices        add column if not exists daftra_id bigint;
alter table payments        add column if not exists daftra_id bigint;
alter table quotes          add column if not exists daftra_id bigint;
alter table invoice_returns add column if not exists daftra_id bigint;

create unique index if not exists clients_daftra_id_key  on clients (daftra_id)  where daftra_id is not null;
create unique index if not exists invoices_daftra_id_key on invoices (daftra_id) where daftra_id is not null;
create unique index if not exists payments_daftra_id_key on payments (daftra_id) where daftra_id is not null;
create unique index if not exists quotes_daftra_id_key   on quotes (daftra_id)   where daftra_id is not null;
create unique index if not exists invoice_returns_daftra_id_key on invoice_returns (daftra_id) where daftra_id is not null;

-- حالة المزامنة (صف واحد)
create table if not exists daftra_sync (
  id            int primary key default 1 check (id = 1),
  enabled       boolean not null default false,   -- تُفعّل بعد أول مزامنة ناجحة
  last_run_at   timestamptz,
  last_ok_at    timestamptz,
  running_since timestamptz,
  last_result   jsonb,
  last_error    text
);
insert into daftra_sync (id) values (1) on conflict do nothing;

alter table daftra_sync enable row level security;
create policy daftra_sync_read on daftra_sync for select to authenticated using (true);
grant select on daftra_sync to authenticated;
grant all on daftra_sync to service_role;
