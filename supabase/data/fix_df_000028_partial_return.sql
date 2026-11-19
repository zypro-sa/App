-- اختياري: تسجيل مرتجع فاتورة DF-000028 بشكل صحيح
-- (استُوردت بصافي 6,900؛ هذا يعيد إجماليها 13,800 ويسجّل مرتجعًا بـ 6,900)
begin;
update invoices set total = 13800
where number = 'DF-000028' and total = 6900
  and not exists (select 1 from invoice_returns r join invoices i on i.id = r.invoice_id where i.number = 'DF-000028');
insert into invoice_returns (invoice_id, amount, returned_at, reason)
select id, 6900, issue_date, 'مرتجع جزئي (منقول من دفترة)' from invoices
where number = 'DF-000028' and total = 13800
  and not exists (select 1 from invoice_returns r where r.invoice_id = invoices.id);
commit;
select number, total, invoice_net_total(id) as net, status from invoices where number = 'DF-000028';
