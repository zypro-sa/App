-- =====================================================================
-- طلب لكل فاتورة جديدة تصل من دفترة
-- عند مزامنة فاتورة غير مرتبطة بطلب:
--  ١) تُربط بطلب عرض السعر المرتبط بها إن وُجد
--  ٢) أو بطلب مفتوح للعميل نفسه بلا فاتورة وقيمته قريبة (±٥٪)
--  ٣) وإلا يُنشأ «طلب جديد» بقيمتها، ويصل إشعار للمالك ومديري الطلبات
-- =====================================================================

create or replace function link_or_create_request_for_invoice(p_invoice uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  i record;
  net numeric;
  rid uuid;
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

  -- ١) عبر عرض السعر
  if i.quote_id is not null then
    select request_id into rid from quotes where id = i.quote_id and request_id is not null and deleted_at is null;
    if rid is not null then how := 'quote'; end if;
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

    -- إشعار المالك ومن يدير الطلبات
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

revoke all on function link_or_create_request_for_invoice(uuid) from public;
grant execute on function link_or_create_request_for_invoice(uuid) to service_role;

create or replace function invoices_auto_request()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- فقط الفواتير القادمة من دفترة وغير المرتبطة بطلب
  if new.daftra_id is not null and new.request_id is null then
    perform link_or_create_request_for_invoice(new.id);
  end if;
  return new;
end $$;

drop trigger if exists invoices_auto_request on invoices;
create trigger invoices_auto_request after insert on invoices
  for each row execute function invoices_auto_request();

-- تطبيقها مرة واحدة على فواتير دفترة الحديثة (آخر ٣٠ يومًا) غير المرتبطة بطلب
do $$
declare r record;
begin
  for r in
    select id from invoices
    where daftra_id is not null and request_id is null and deleted_at is null and status <> 'void'
      and client_id is not null and issue_date >= (now() at time zone 'Asia/Riyadh')::date - 30
    order by issue_date
  loop
    perform link_or_create_request_for_invoice(r.id);
  end loop;
end $$;
