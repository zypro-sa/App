-- تعديل الفواتير: ملاحظات/وصف، وإعادة حساب الحالة عند تغيير الإجمالي أو الاستعادة من الإلغاء

alter table invoices add column if not exists notes text;
alter table quotes   add column if not exists notes text;

create or replace function invoices_status_on_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare paid numeric;
begin
  if new.status = 'void' then
    return new;
  end if;
  select coalesce(sum(amount), 0) into paid
  from payments where invoice_id = new.id and deleted_at is null;
  new.status := case
    when new.total > 0 and paid >= new.total then 'paid'::invoice_status
    when paid > 0 then 'partially_paid'::invoice_status
    else 'issued'::invoice_status
  end;
  return new;
end $$;

create trigger invoices_status_on_change
  before update of total, status on invoices
  for each row execute function invoices_status_on_change();
