-- =====================================================================
-- المرتجعات الجزئية على الفواتير
-- صافي الفاتورة = الإجمالي − المرتجعات، والحالة والمستحق يُحسبان من الصافي
-- =====================================================================

create table invoice_returns (
  id           uuid primary key default gen_random_uuid(),
  invoice_id   uuid not null references invoices (id) on delete cascade,
  amount       numeric(14, 2) not null check (amount > 0),
  returned_at  date not null default current_date,
  reason       text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references profiles (id) on delete set null default auth.uid(),
  deleted_at   timestamptz
);

create index on invoice_returns (invoice_id);

create trigger set_updated_at before update on invoice_returns
  for each row execute function set_updated_at();

alter table invoice_returns enable row level security;
create policy invoice_returns_finance on invoice_returns for all to authenticated
  using (has_perm('finance.manage')) with check (has_perm('finance.manage'));

grant select, insert, update, delete on invoice_returns to authenticated;
grant all on invoice_returns to service_role;

-- صافي الفاتورة
create or replace function invoice_net_total(inv_id uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select i.total - coalesce((select sum(r.amount) from invoice_returns r
                             where r.invoice_id = i.id and r.deleted_at is null), 0)
  from invoices i where i.id = inv_id
$$;

-- الحالة من الصافي عند تعديل الفاتورة
create or replace function invoices_status_on_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  paid numeric;
  returned numeric;
  net numeric;
begin
  if new.status = 'void' then
    return new;
  end if;
  select coalesce(sum(amount), 0) into paid from payments where invoice_id = new.id and deleted_at is null;
  select coalesce(sum(amount), 0) into returned from invoice_returns where invoice_id = new.id and deleted_at is null;
  net := new.total - returned;
  new.status := case
    when paid >= net then 'paid'::invoice_status
    when paid > 0 then 'partially_paid'::invoice_status
    else 'issued'::invoice_status
  end;
  return new;
end $$;

-- الدفعات والمرتجعات تعيد حساب حالة الفاتورة
create or replace function recalc_invoice_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update invoices set status = status
  where id = coalesce(new.invoice_id, old.invoice_id) and status <> 'void';
  return null;
end $$;

create trigger invoice_returns_recalc
  after insert or update or delete on invoice_returns
  for each row execute function recalc_invoice_status();

-- المستحق على العميل يُحسب من الصافي
create or replace view client_summary with (security_invoker = true) as
select c.id,
       c.name,
       (select count(*) from requests r
         where r.client_id = c.id and r.deleted_at is null
           and r.status not in ('closed', 'cancelled'))                    as open_requests,
       (select coalesce(sum(p.contract_value), 0) from projects p
         where p.client_id = c.id and p.deleted_at is null)               as contracts_value,
       (select coalesce(sum(greatest(
                 i.total
                 - (select coalesce(sum(r.amount), 0) from invoice_returns r
                     where r.invoice_id = i.id and r.deleted_at is null)
                 - (select coalesce(sum(pm.amount), 0) from payments pm
                     where pm.invoice_id = i.id and pm.deleted_at is null), 0)), 0)
          from invoices i
         where i.client_id = c.id and i.deleted_at is null
           and i.status not in ('paid', 'void'))                          as amount_due,
       (select max(a.created_at) from activity_log a where a.client_id = c.id) as last_activity_at
from clients c
where c.deleted_at is null;
