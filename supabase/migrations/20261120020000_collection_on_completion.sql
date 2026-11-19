-- =====================================================================
-- متابعة التحصيل تبدأ عند اكتمال الطلب
-- الفاتورة تُربط بطلبها، وعند إغلاق الطلب تُنشأ متابعة تحصيل تلقائيًا
-- لكل فاتورة مرتبطة عليها مبلغ متبقٍ.
-- =====================================================================

alter table invoices add column if not exists request_id uuid references requests (id) on delete set null;
create index if not exists invoices_request_id_idx on invoices (request_id);

-- ربط فواتير دفترة بالطلبات التي حُوّلت منها
update invoices i set request_id = r.id
from requests r
where i.request_id is null
  and r.description like 'من فاتورة دفترة ' || i.number || ' %';

-- حذف متابعات التحصيل المبكرة للطلبات التي لم تكتمل (تذهب للسلة)
update followups f set deleted_at = now()
from invoices i join requests r on r.id = i.request_id
where f.related_type = 'invoice' and f.related_id = i.id
  and f.deleted_at is null and f.status <> 'done'
  and r.status not in ('closed', 'cancelled');

-- إنشاء متابعة التحصيل عند إغلاق الطلب
create or replace function collection_followup_on_close() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'closed' and old.status is distinct from 'closed' then
    insert into followups (title, direction, owner_id, counterpart, due_at, related_type, related_id, source)
    select 'تحصيل المتبقي من فاتورة ' || x.number || ': ' || to_char(x.remaining, 'FM999,999,990.##') || ' ر.س',
           'waiting',
           coalesce(new.assignee_id,
                    (select id from profiles where role = 'owner' and is_active order by created_at limit 1)),
           c.name, now(), 'invoice', x.id, 'auto'
    from (
      select i.id, i.number, i.client_id,
             invoice_net_total(i.id)
               - coalesce((select sum(p.amount) from payments p
                           where p.invoice_id = i.id and p.deleted_at is null), 0) as remaining
      from invoices i
      where i.request_id = new.id and i.deleted_at is null and i.status <> 'void'
    ) x
    join clients c on c.id = x.client_id
    where x.remaining > 0
      and not exists (select 1 from followups f
                      where f.related_id = x.id and f.status <> 'done' and f.deleted_at is null);
  end if;
  return new;
end $$;

create trigger collection_followup_on_close
  after update of status on requests
  for each row execute function collection_followup_on_close();
