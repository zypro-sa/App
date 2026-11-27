-- =====================================================================
-- ربط فواتير دفترة بعروض أسعارها وتوحيد الطلب
-- كانت المزامنة تحدّث حالة العرض فقط دون ربطه بالفاتورة، فلا تظهر الفاتورة
-- ودفعاتها في طلب العرض، وقد يُنشأ طلب مكرر للفاتورة.
-- =====================================================================

create or replace function link_invoice_quote(p_invoice uuid, p_quote uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  i record;
  q record;
  auto_req record;
  changed boolean := false;
begin
  select * into i from invoices where id = p_invoice and deleted_at is null;
  select * into q from quotes where id = p_quote and deleted_at is null;
  if i.id is null or q.id is null then return jsonb_build_object('changed', false); end if;

  if i.quote_id is distinct from q.id and i.quote_id is null then
    update invoices set quote_id = q.id where id = i.id;
    changed := true;
  end if;
  if q.status <> 'accepted' then
    update quotes set status = 'accepted' where id = q.id;
  end if;

  if q.request_id is not null and i.request_id is distinct from q.request_id then
    if i.request_id is null then
      update invoices set request_id = q.request_id where id = i.id;
      changed := true;
    else
      -- الفاتورة على طلب أُنشئ تلقائيًا من دفترة ولم يُعمل عليه → ننقلها لطلب العرض ونحذف المكرر
      select r.* into auto_req from requests r
      where r.id = i.request_id and r.deleted_at is null
        and r.custom ->> 'source' = 'daftra' and r.status = 'new' and r.assignee_id is null
        and not exists (select 1 from request_steps s where s.request_id = r.id)
        and not exists (select 1 from tasks t where t.request_id = r.id and t.deleted_at is null)
        and not exists (select 1 from invoices x where x.request_id = r.id and x.id <> i.id and x.deleted_at is null);
      if auto_req.id is not null then
        update invoices set request_id = q.request_id where id = i.id;
        update requests set deleted_at = now() where id = auto_req.id;
        changed := true;
      end if;
    end if;
  elsif q.request_id is null and i.request_id is not null then
    update quotes set request_id = i.request_id where id = q.id;
    changed := true;
  end if;

  return jsonb_build_object('changed', changed);
end $$;

revoke all on function link_invoice_quote(uuid, uuid) from public;
grant execute on function link_invoice_quote(uuid, uuid) to service_role;

-- عند وصول فاتورة جديدة: جرّب أيضًا عرض سعر للعميل نفسه بالمبلغ نفسه قبل إنشاء طلب جديد
create or replace function link_or_create_request_for_invoice(p_invoice uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  i record;
  net numeric;
  rid uuid;
  qid uuid;
  how text;
  owner_ids uuid[];
  u uuid;
  cname text;
begin
  select * into i from invoices where id = p_invoice;
  if i.id is null or i.request_id is not null or i.client_id is null or i.deleted_at is not null or i.status = 'void' then
    return jsonb_build_object('skipped', true);
  end if;
  net := coalesce(invoice_net_total(i.id), i.total);

  -- ١) عبر عرض السعر المرتبط
  if i.quote_id is not null then
    select request_id into rid from quotes where id = i.quote_id and request_id is not null and deleted_at is null;
    if rid is not null then how := 'quote'; end if;
  end if;

  -- ١ب) عرض سعر للعميل نفسه بالمبلغ نفسه (قبل الفاتورة) وله طلب
  if rid is null then
    select q.id, q.request_id into qid, rid from quotes q
    where q.client_id = i.client_id and q.deleted_at is null and q.request_id is not null
      and abs((q.amount + coalesce(q.vat_amount, 0)) - i.total) < 1
      and coalesce(q.sent_at, q.created_at::date) <= i.issue_date
      and not exists (select 1 from invoices x where x.quote_id = q.id and x.deleted_at is null and x.id <> i.id)
    order by coalesce(q.sent_at, q.created_at::date) desc
    limit 1;
    if rid is not null then
      how := 'quote_amount';
      update invoices set quote_id = qid where id = i.id and quote_id is null;
      update quotes set status = 'accepted' where id = qid;
    end if;
  end if;

  -- ٢) طلب مفتوح/حديث للعميل نفسه بلا فاتورة وقيمته قريبة
  if rid is null then
    select r.id into rid
    from requests r
    where r.client_id = i.client_id and r.deleted_at is null and r.status <> 'cancelled'
      and r.created_at > i.issue_date::timestamptz - interval '120 days'
      and not exists (select 1 from invoices x where x.request_id = r.id and x.deleted_at is null and x.status <> 'void')
      and r.estimated_value is not null and net > 0
      and abs(r.estimated_value - net) <= net * 0.05
    order by abs(r.estimated_value - net), r.created_at desc
    limit 1;
    if rid is not null then how := 'match'; end if;
  end if;

  -- ٣) طلب جديد
  if rid is null then
    insert into requests (title, description, client_id, status, priority, received_at, estimated_value, currency, custom)
    values ('خدمات فاتورة ' || i.number,
            nullif(left(trim(coalesce(i.notes, '')), 2000), ''),
            i.client_id, 'new', 'medium', i.issue_date::timestamptz, net, coalesce(i.currency, 'SAR'),
            jsonb_build_object('source', 'daftra', 'invoice', i.number))
    returning id into rid;
    how := 'created';

    select name into cname from clients where id = i.client_id;
    select array_agg(id) into owner_ids from profiles
      where is_active and (role = 'owner' or perm_of(id, 'requests.add') or perm_of(id, 'requests.edit'));
    foreach u in array coalesce(owner_ids, '{}') loop
      perform notify_user(u, 'assigned',
        case when user_is_en(u) then 'New request from Daftra invoice ' || i.number
             else 'طلب جديد من فاتورة دفترة ' || i.number end,
        coalesce(cname, '') || ' · ' || round(net)::text,
        '/requests/' || rid, 'request', rid, null);
    end loop;
  end if;

  update invoices set request_id = rid where id = i.id;
  if i.quote_id is not null then
    update quotes set request_id = rid where id = i.quote_id and request_id is null;
  end if;
  return jsonb_build_object('invoice', i.number, 'request', rid, 'how', how);
end $$;

-- إصلاح فوري: الفواتير غير المرتبطة بعرض، ولها عرض للعميل نفسه بالمبلغ نفسه
do $$
declare r record;
begin
  for r in
    select distinct on (i.id) i.id as inv, q.id as quote
    from invoices i
    join quotes q on q.client_id = i.client_id and q.deleted_at is null
      and abs((q.amount + coalesce(q.vat_amount, 0)) - i.total) < 1
      and coalesce(q.sent_at, q.created_at::date) <= i.issue_date
    where i.deleted_at is null and i.quote_id is null and i.daftra_id is not null and q.daftra_id is not null
      and not exists (select 1 from invoices x where x.quote_id = q.id and x.deleted_at is null)
    order by i.id, coalesce(q.sent_at, q.created_at::date) desc
  loop
    perform link_invoice_quote(r.inv, r.quote);
  end loop;
end $$;
