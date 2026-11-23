-- =====================================================================
-- الطلبات السابقة من فواتير دفترة
-- كل فاتورة غير مرتبطة بطلب (قبل بدء استخدام التطبيق) تُنشأ لها «طلب منجز»
-- مُعلَّم imported، فتظهر قيمته وتحصيله في التقارير وملف العميل.
-- الطلبات المستوردة لا تدخل في متوسط زمن الإنجاز ولا نسبة الالتزام.
-- =====================================================================

alter table requests add column if not exists imported boolean not null default false;

create or replace function backfill_history_requests(p_dry boolean default true, p_all boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cutoff date;
  r record;
  nid uuid;
  made int := 0;
  later int := 0;
  total numeric := 0;
  sample jsonb := '[]';
  tag text;
begin
  if not (has_perm('finance.edit') or has_perm('finance.add')) or not has_perm('requests.add') then
    raise exception 'تحتاج صلاحية إضافة الطلبات وإدارة المالية';
  end if;
  -- تاريخ أول طلب أُدخل في التطبيق: الفواتير قبله لا طلبات لها
  cutoff := coalesce(
    (select min(coalesce(received_at, created_at))::date from requests where not imported and deleted_at is null),
    (now() at time zone 'Asia/Riyadh')::date + 1);

  for r in
    select i.id, i.number, i.client_id, i.issue_date, i.currency, i.notes, i.quote_id,
           invoice_net_total(i.id) as net
    from invoices i
    where i.deleted_at is null and i.status <> 'void' and i.request_id is null and i.client_id is not null
    order by i.issue_date, i.number
  loop
    if not p_all and r.issue_date >= cutoff then
      later := later + 1;
      continue;
    end if;
    made := made + 1;
    total := total + coalesce(r.net, 0);
    if jsonb_array_length(sample) < 8 then
      sample := sample || jsonb_build_object('number', r.number, 'date', r.issue_date, 'total', r.net,
                                             'client', (select name from clients where id = r.client_id));
    end if;
    if not p_dry then
      tag := case when user_is_en(auth.uid()) then 'Services on invoice ' else 'خدمات فاتورة ' end;
      insert into requests (title, description, client_id, status, priority, received_at, created_at,
                            estimated_value, currency, imported, custom, created_by)
      values (tag || r.number,
              nullif(left(trim(coalesce(r.notes, '')), 2000), ''),
              r.client_id, 'closed', 'medium',
              r.issue_date::timestamptz, r.issue_date::timestamptz,
              r.net, coalesce(r.currency, 'SAR'), true,
              jsonb_build_object('source', 'daftra_history', 'invoice', r.number),
              auth.uid())
      returning id into nid;
      -- تاريخ الإنجاز = تاريخ الفاتورة (المشغّل يضع «الآن» عند الإدراج)
      update requests set closed_at = r.issue_date::timestamptz where id = nid;
      update invoices set request_id = nid where id = r.id;
      if r.quote_id is not null then
        update quotes set request_id = nid where id = r.quote_id and request_id is null;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'dry_run', p_dry,
    'cutoff', cutoff,
    'requests', made,
    'total', round(total, 2),
    'later_unlinked', later,
    'sample', sample
  );
end $$;

grant execute on function backfill_history_requests(boolean, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- التقارير: استبعاد الطلبات المستوردة من متوسط زمن الإنجاز
-- ---------------------------------------------------------------------
create or replace function report_dashboard(p_from date, p_to date, p_member uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  len int := greatest(p_to - p_from + 1, 1);
  pf date := p_from - len;            -- الفترة السابقة
  pt date := p_from - 1;
  today date := (now() at time zone 'Asia/Riyadh')::date;
  fin boolean := has_perm('finance.view');
  res jsonb := '{}';
  m uuid := p_member;
begin
  if not (has_perm('reports.view') or (m is not null and m = auth.uid())) then
    raise exception 'ليست لديك صلاحية التقارير';
  end if;

  -- ١. المؤشرات الرئيسية (الحالية والسابقة)
  res := res || jsonb_build_object('kpi', (
    with r as (
      select * from requests where deleted_at is null and (m is null or assignee_id = m)
    ), t as (
      select * from tasks where deleted_at is null and (m is null or assignee_id = m)
    )
    select jsonb_build_object(
      'closed',      (select count(*) from r where status = 'closed' and closed_at::date between p_from and p_to),
      'closed_prev', (select count(*) from r where status = 'closed' and closed_at::date between pf and pt),
      'new',         (select count(*) from r where created_at::date between p_from and p_to),
      'new_prev',    (select count(*) from r where created_at::date between pf and pt),
      'on_time',     (select round(100.0 * count(*) filter (where closed_at::date <= due_date) / nullif(count(*), 0))
                        from r where status = 'closed' and due_date is not null and closed_at::date between p_from and p_to),
      'on_time_prev',(select round(100.0 * count(*) filter (where closed_at::date <= due_date) / nullif(count(*), 0))
                        from r where status = 'closed' and due_date is not null and closed_at::date between pf and pt),
      'avg_days',    (select round(avg(extract(epoch from case when not imported then closed_at - created_at end) / 86400)::numeric, 1)
                        from r where status = 'closed' and closed_at::date between p_from and p_to),
      'avg_days_prev',(select round(avg(extract(epoch from case when not imported then closed_at - created_at end) / 86400)::numeric, 1)
                        from r where status = 'closed' and closed_at::date between pf and pt),
      'tasks_done',  (select count(*) from t where completed_at::date between p_from and p_to),
      'tasks_done_prev', (select count(*) from t where completed_at::date between pf and pt),
      'meetings_held', (select count(*) from meetings where deleted_at is null and status = 'done' and start_at::date between p_from and p_to),
      'meetings_held_prev', (select count(*) from meetings where deleted_at is null and status = 'done' and start_at::date between pf and pt),
      'open',        (select count(*) from r where status not in ('closed', 'cancelled')),
      'new_clients', (select count(*) from clients where deleted_at is null and created_at::date between p_from and p_to),
      'new_clients_prev', (select count(*) from clients where deleted_at is null and created_at::date between pf and pt)
    )
  ));

  -- ٢. المنجز أسبوعيًا (آخر ١٢ أسبوعًا حتى نهاية الفترة)
  res := res || jsonb_build_object('weekly', (
    select coalesce(jsonb_agg(jsonb_build_object('week', w::date, 'count', (
             select count(*) from requests
             where deleted_at is null and status = 'closed' and (m is null or assignee_id = m)
               and closed_at::date >= w::date and closed_at::date < w::date + 7)) order by w), '[]')
    from generate_series(p_to - 83, p_to - 6, interval '7 days') w
  ));

  -- ٣. الطلبات المفتوحة حسب الحالة
  res := res || jsonb_build_object('by_status', (
    select coalesce(jsonb_object_agg(status, n), '{}') from (
      select status::text, count(*) n from requests
      where deleted_at is null and status not in ('closed', 'cancelled') and (m is null or assignee_id = m)
      group by status) x
  ));

  -- ٤. حسب نوع الخدمة: الطلبات الجديدة في الفترة + متوسط المدة (آخر ١٨٠ يومًا)
  res := res || jsonb_build_object('services', (
    select coalesce(jsonb_agg(row_to_json(x) order by x.count desc, x.avg_days desc nulls last), '[]') from (
      select coalesce(nullif(service_type, ''), 'غير محدد') as name,
             count(*) filter (where created_at::date between p_from and p_to) as count,
             coalesce(sum(estimated_value) filter (where created_at::date between p_from and p_to), 0) as value,
             round(avg(extract(epoch from case when not imported then closed_at - created_at end) / 86400)
                   filter (where status = 'closed' and closed_at::date > p_to - 180)::numeric, 1) as avg_days
      from requests
      where deleted_at is null and (m is null or assignee_id = m)
      group by 1
      having count(*) filter (where created_at::date between p_from and p_to) > 0
          or count(*) filter (where status = 'closed' and closed_at::date > p_to - 180) > 0
    ) x
  ));

  -- ٥. التنبيهات
  res := res || jsonb_build_object('alerts', jsonb_build_object(
    'overdue', (select count(*) from requests where deleted_at is null and (m is null or assignee_id = m)
                  and status not in ('closed', 'cancelled') and due_date < today),
    'overdue_max_days', (select max(today - due_date) from requests where deleted_at is null and (m is null or assignee_id = m)
                  and status not in ('closed', 'cancelled') and due_date < today),
    'waiting_long', (select count(*) from requests where deleted_at is null and (m is null or assignee_id = m)
                  and status = 'waiting_client' and updated_at < now() - interval '7 days'),
    'unpaid_closed', case when fin then (select count(distinct r.id) from requests r join invoices i on i.request_id = r.id
                  where r.deleted_at is null and r.status = 'closed' and i.deleted_at is null and i.status <> 'void'
                    and invoice_remaining(i.id) > 0) end,
    'unpaid_closed_amount', case when fin then (select coalesce(sum(invoice_remaining(i.id)), 0) from requests r join invoices i on i.request_id = r.id
                  where r.deleted_at is null and r.status = 'closed' and i.deleted_at is null and i.status <> 'void') end,
    'quotes_no_reply', case when fin then (select count(*) from quotes where deleted_at is null and status = 'sent'
                  and sent_at <= today - 3) end
  ));

  -- ٦. الأطول تعطلًا
  res := res || jsonb_build_object('stuck', (
    select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
      select r.id, r.number, r.title, c.name as client, p.name as assignee, r.status::text as status, r.progress,
             case when r.due_date < today then today - r.due_date else null end as overdue_days,
             (today - r.updated_at::date) as idle_days
      from requests r
      left join clients c on c.id = r.client_id
      left join profiles p on p.id = r.assignee_id
      where r.deleted_at is null and r.status not in ('closed', 'cancelled') and (m is null or r.assignee_id = m)
      order by (r.due_date < today) desc nulls last, (today - r.due_date) desc nulls last, r.updated_at asc
      limit 5) x
  ));

  -- ٧. الفريق
  if m is null then
    res := res || jsonb_build_object('team', (
      select coalesce(jsonb_agg(row_to_json(x) order by x.open_tasks desc), '[]') from (
        select p.id, p.name, p.avatar_url,
               (select count(*) from tasks t where t.assignee_id = p.id and t.deleted_at is null and t.status <> 'done') as open_tasks,
               (select count(*) from tasks t where t.assignee_id = p.id and t.deleted_at is null and t.status <> 'done' and t.due_at < now()) as overdue_tasks,
               (select count(*) from tasks t where t.assignee_id = p.id and t.deleted_at is null and t.completed_at::date between p_from and p_to) as done_tasks,
               (select round(100.0 * count(*) filter (where t.completed_at <= t.due_at) / nullif(count(*), 0))
                  from tasks t where t.assignee_id = p.id and t.deleted_at is null and t.due_at is not null
                    and t.completed_at::date between p_from and p_to) as on_time,
               (select count(*) from requests r where r.assignee_id = p.id and r.deleted_at is null and r.status not in ('closed', 'cancelled')) as open_requests,
               (select round(avg(extract(epoch from case when not r.imported then r.closed_at - r.created_at end) / 86400)::numeric, 1)
                  from requests r where r.assignee_id = p.id and r.deleted_at is null and r.status = 'closed'
                    and r.closed_at::date between p_from and p_to) as avg_days
        from profiles p where p.is_active) x
    ));
  end if;

  -- ٨. العملاء
  if m is null then
    res := res || jsonb_build_object('clients', jsonb_build_object(
      'active', (select count(*) from clients c where c.deleted_at is null and (
                   exists (select 1 from requests r where r.client_id = c.id and r.deleted_at is null and r.updated_at > now() - interval '60 days')
                or exists (select 1 from meetings mt where mt.client_id = c.id and mt.deleted_at is null and mt.start_at > now() - interval '60 days'))),
      'idle', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
                 select c.id, c.name, (today - greatest(
                          coalesce((select max(r.updated_at) from requests r where r.client_id = c.id and r.deleted_at is null), c.created_at),
                          coalesce((select max(mt.start_at) from meetings mt where mt.client_id = c.id and mt.deleted_at is null), c.created_at))::date) as days
                 from clients c where c.deleted_at is null
                 order by days desc limit 50) x where x.days > 60),
      'top', case when fin then (select coalesce(jsonb_agg(row_to_json(x) order by x.value desc), '[]') from (
                 select c.id, c.name, sum(invoice_net_total(i.id)) as value,
                        (select count(*) from requests r where r.client_id = c.id and r.deleted_at is null) as requests
                 from clients c join invoices i on i.client_id = c.id and i.deleted_at is null and i.status <> 'void'
                   and i.issue_date > p_to - 365
                 group by c.id, c.name order by value desc limit 5) x)
             else (select coalesce(jsonb_agg(row_to_json(x) order by x.requests desc), '[]') from (
                 select c.id, c.name, null::numeric as value, count(r.id) as requests
                 from clients c join requests r on r.client_id = c.id and r.deleted_at is null
                 group by c.id, c.name order by requests desc limit 5) x) end
    ));
  end if;

  -- ٩. الاجتماعات والمتابعات
  res := res || jsonb_build_object('meetings', (
    select jsonb_build_object(
      'done', count(*) filter (where status = 'done'),
      'postponed', count(*) filter (where status = 'postponed'),
      'cancelled', count(*) filter (where status = 'cancelled'),
      'scheduled', count(*) filter (where status = 'scheduled'))
    from meetings where deleted_at is null and start_at::date between p_from and p_to
      and (m is null or created_by = m or exists (select 1 from meeting_attendees a where a.meeting_id = meetings.id and a.user_id = m))
  ), 'decision_tasks', (
    select jsonb_build_object('total', count(*), 'done', count(*) filter (where status = 'done'))
    from tasks where deleted_at is null and source_decision_id is not null and created_at::date between p_from and p_to
      and (m is null or assignee_id = m)
  ), 'promises', (
    select jsonb_build_object('total', count(*), 'on_time', count(*) filter (where status = 'done' and updated_at <= due_at + interval '1 day'))
    from followups where deleted_at is null and direction = 'promised' and due_at::date between p_from and p_to
      and (m is null or owner_id = m)
  ));

  -- ١٠. المالية (لمن يملك صلاحيتها)
  if fin and m is null then
    res := res || jsonb_build_object('finance', jsonb_build_object(
      'collected', (select coalesce(sum(amount), 0) from payments where deleted_at is null and paid_at between p_from and p_to),
      'collected_prev', (select coalesce(sum(amount), 0) from payments where deleted_at is null and paid_at between pf and pt),
      'billed', (select coalesce(sum(invoice_net_total(id)), 0) from invoices where deleted_at is null and status <> 'void' and issue_date between p_from and p_to),
      'due', (select coalesce(sum(invoice_remaining(id)), 0) from invoices where deleted_at is null and status <> 'void'),
      'aging', (select jsonb_build_object(
                  'a0_30', coalesce(sum(rem) filter (where age <= 30), 0),
                  'a31_60', coalesce(sum(rem) filter (where age between 31 and 60), 0),
                  'a60', coalesce(sum(rem) filter (where age > 60), 0))
                from (select invoice_remaining(id) rem, greatest(today - due_date, 0) age
                      from invoices where deleted_at is null and status <> 'void') x where rem > 0),
      'monthly', (select coalesce(jsonb_agg(jsonb_build_object('month', mo::date,
                    'billed', (select coalesce(sum(invoice_net_total(i.id)), 0) from invoices i where i.deleted_at is null and i.status <> 'void'
                               and i.issue_date >= mo::date and i.issue_date < (mo + interval '1 month')::date),
                    'collected', (select coalesce(sum(amount), 0) from payments pa where pa.deleted_at is null
                               and pa.paid_at >= mo::date and pa.paid_at < (mo + interval '1 month')::date)) order by mo), '[]')
                  from generate_series(date_trunc('month', p_to::timestamp) - interval '5 months', date_trunc('month', p_to::timestamp), interval '1 month') mo),
      'quotes', (select jsonb_build_object('total', count(*) filter (where status in ('sent', 'accepted', 'rejected', 'expired')),
                                           'accepted', count(*) filter (where status = 'accepted'))
                 from quotes where deleted_at is null and coalesce(sent_at, created_at::date) > p_to - 90),
      'late', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
                 select i.id, i.number, c.name as client, invoice_remaining(i.id) as remaining, today - i.due_date as days
                 from invoices i join clients c on c.id = i.client_id
                 where i.deleted_at is null and i.status <> 'void' and i.due_date < today and invoice_remaining(i.id) > 0
                 order by days desc limit 5) x)
    ));
  end if;

  -- ١١. الأهداف لشهر نهاية الفترة
  res := res || jsonb_build_object('goals', (
    select coalesce(jsonb_object_agg(metric, target), '{}') from report_goals
    where month = date_trunc('month', p_to::timestamp)::date
  ), 'can_finance', fin, 'from', p_from, 'to', p_to);

  return res;
end $$;

create or replace function report_custom(p jsonb)
returns jsonb
language plpgsql stable security invoker set search_path = public as $$
declare
  src   text := coalesce(nullif(p->>'source', ''), 'requests');
  grp   text := coalesce(nullif(p->>'group_by', ''), 'none');
  met   text := coalesce(nullif(p->>'metric', ''), 'count');
  basis text := coalesce(nullif(p->>'date_basis', ''), 'created');
  d_from date := coalesce(nullif(p->>'from', '')::date, (now() at time zone 'Asia/Riyadh')::date - 29);
  d_to   date := coalesce(nullif(p->>'to', '')::date, (now() at time zone 'Asia/Riyadh')::date);
  f     jsonb := coalesce(p->'filters', '{}');
  lim   int := least(greatest(coalesce(nullif(p->>'limit', '')::int, 50), 1), 500);
  f_status text[] := nullif(array(select jsonb_array_elements_text(coalesce(f->'status', '[]'))), '{}');
  f_prio   text[] := nullif(array(select jsonb_array_elements_text(coalesce(f->'priority', '[]'))), '{}');
  f_person uuid := nullif(f->>'person', '')::uuid;
  f_client uuid := nullif(f->>'client', '')::uuid;
  f_service text := nullif(f->>'service', '');
  base text; datecol text; valexpr text; dueexpr text; daysexpr text; ontimeexpr text;
  statuscol text; personcol text; clientcol text; priocol text; servicecol text; typecol text;
  keyexpr text; labelexpr text; joins text := ''; cond text; metexpr text; ord text;
  rows_ jsonb; total jsonb;
begin
  if d_to < d_from then raise exception 'تاريخ النهاية قبل البداية'; end if;

  case src
    when 'requests' then
      base := 'requests x';
      datecol := case basis when 'closed' then 'x.closed_at' when 'due' then 'x.due_date::timestamptz' else 'x.created_at' end;
      valexpr := 'x.estimated_value';
      daysexpr := 'case when x.closed_at is not null and not x.imported then extract(epoch from x.closed_at - x.created_at) / 86400 end';
      ontimeexpr := 'case when x.status = ''closed'' and x.due_date is not null then (x.closed_at::date <= x.due_date)::int end';
      statuscol := 'x.status::text'; personcol := 'x.assignee_id'; clientcol := 'x.client_id';
      priocol := 'x.priority::text'; servicecol := 'x.service_type'; typecol := 'x.channel::text';
    when 'tasks' then
      base := 'tasks x';
      datecol := case basis when 'closed' then 'x.completed_at' when 'due' then 'x.due_at' else 'x.created_at' end;
      daysexpr := 'case when x.completed_at is not null then extract(epoch from x.completed_at - x.created_at) / 86400 end';
      ontimeexpr := 'case when x.completed_at is not null and x.due_at is not null then (x.completed_at <= x.due_at)::int end';
      statuscol := 'x.status::text'; personcol := 'x.assignee_id'; clientcol := 'x.client_id'; priocol := 'x.priority::text';
    when 'meetings' then
      base := 'meetings x';
      datecol := case basis when 'created' then 'x.created_at' else 'x.start_at' end;
      statuscol := 'x.status::text'; personcol := 'x.created_by'; clientcol := 'x.client_id'; typecol := 'x.type::text';
    when 'clients' then
      base := 'clients x';
      datecol := 'x.created_at';
      statuscol := 'x.status::text'; personcol := 'x.account_manager_id'; typecol := 'x.type::text';
    when 'invoices' then
      base := 'invoices x';
      datecol := case basis when 'due' then 'x.due_date::timestamptz' else 'x.issue_date::timestamptz' end;
      valexpr := 'invoice_net_total(x.id)';
      dueexpr := 'invoice_remaining(x.id)';
      statuscol := 'x.status::text'; clientcol := 'x.client_id'; personcol := 'x.created_by';
    when 'quotes' then
      base := 'quotes x';
      datecol := case basis when 'created' then 'x.created_at' else 'coalesce(x.sent_at::timestamptz, x.created_at)' end;
      valexpr := '(x.amount + coalesce(x.vat_amount, 0))';
      statuscol := 'x.status::text'; clientcol := 'x.client_id'; personcol := 'x.created_by';
    when 'followups' then
      base := 'followups x';
      datecol := case basis when 'created' then 'x.created_at' else 'x.due_at' end;
      ontimeexpr := 'case when x.status = ''done'' then (x.updated_at <= x.due_at + interval ''1 day'')::int end';
      statuscol := 'x.status::text'; personcol := 'x.owner_id'; typecol := 'x.direction::text';
    else
      raise exception 'مصدر غير مدعوم: %', src;
  end case;

  -- التجميع
  case grp
    when 'none' then keyexpr := '''all'''; labelexpr := '''all''';
    when 'status' then keyexpr := statuscol; labelexpr := statuscol;
    when 'priority' then keyexpr := priocol; labelexpr := priocol;
    when 'service' then keyexpr := 'coalesce(nullif(' || servicecol || ', ''''), ''—'')'; labelexpr := keyexpr;
    when 'type' then keyexpr := typecol; labelexpr := typecol;
    when 'city' then
      if src <> 'clients' then raise exception 'تجميع غير مدعوم لهذا المصدر'; end if;
      keyexpr := 'coalesce(nullif(x.city, ''''), ''—'')'; labelexpr := keyexpr;
    when 'sector' then
      if src <> 'clients' then raise exception 'تجميع غير مدعوم لهذا المصدر'; end if;
      keyexpr := 'coalesce(nullif(x.sector, ''''), ''—'')'; labelexpr := keyexpr;
    when 'person' then
      keyexpr := 'coalesce(' || personcol || '::text, ''—'')'; labelexpr := 'coalesce(pp.name, ''—'')';
      joins := ' left join profiles pp on pp.id = ' || personcol;
    when 'client' then
      keyexpr := 'coalesce(' || clientcol || '::text, ''—'')'; labelexpr := 'coalesce(cc.name, ''—'')';
      joins := ' left join clients cc on cc.id = ' || clientcol;
    when 'day' then keyexpr := 'to_char((' || datecol || ' at time zone ''Asia/Riyadh'')::date, ''YYYY-MM-DD'')'; labelexpr := keyexpr;
    when 'week' then keyexpr := 'to_char(date_trunc(''week'', (' || datecol || ' at time zone ''Asia/Riyadh'')), ''YYYY-MM-DD'')'; labelexpr := keyexpr;
    when 'month' then keyexpr := 'to_char(date_trunc(''month'', (' || datecol || ' at time zone ''Asia/Riyadh'')), ''YYYY-MM'')'; labelexpr := keyexpr;
    when 'weekday' then keyexpr := 'extract(isodow from (' || datecol || ' at time zone ''Asia/Riyadh''))::int::text'; labelexpr := keyexpr;
    else raise exception 'تجميع غير مدعوم: %', grp;
  end case;
  if keyexpr is null then raise exception 'تجميع غير مدعوم لهذا المصدر'; end if;

  -- المقياس
  metexpr := case met
    when 'count' then 'count(*)'
    when 'sum_value' then case when valexpr is not null then 'round(coalesce(sum(' || valexpr || '), 0), 2)' end
    when 'sum_due' then case when dueexpr is not null then 'round(coalesce(sum(' || dueexpr || '), 0), 2)' end
    when 'avg_value' then case when valexpr is not null then 'round(avg(' || valexpr || ')::numeric, 2)' end
    when 'avg_days' then case when daysexpr is not null then 'round(avg(' || daysexpr || ')::numeric, 1)' end
    when 'on_time' then case when ontimeexpr is not null then 'round(100.0 * sum(' || ontimeexpr || ') / nullif(count(' || ontimeexpr || '), 0))' end
  end;
  if metexpr is null then raise exception 'المقياس غير متاح لهذا المصدر'; end if;

  -- الشروط (القيم معاملات $1..$7)
  cond := 'x.deleted_at is null and ' || datecol || ' is not null'
       || ' and (' || datecol || ' at time zone ''Asia/Riyadh'')::date between $1 and $2'
       || ' and ($3::text[] is null or ' || statuscol || ' = any($3))'
       || case when personcol is not null then ' and ($4::uuid is null or ' || personcol || ' = $4)' else ' and ($4::uuid is null or false)' end
       || case when clientcol is not null then ' and ($5::uuid is null or ' || clientcol || ' = $5)'
               when src = 'clients' then ' and ($5::uuid is null or x.id = $5)' else ' and ($5::uuid is null or false)' end
       || case when servicecol is not null then ' and ($6::text is null or ' || servicecol || ' = $6)' else ' and ($6::text is null or false)' end
       || case when priocol is not null then ' and ($7::text[] is null or ' || priocol || ' = any($7))' else ' and ($7::text[] is null or false)' end;

  ord := case when grp in ('day', 'week', 'month', 'weekday') then 'k asc' else 'v desc nulls last, c desc' end;

  execute format(
    'select coalesce(jsonb_agg(jsonb_build_object(''key'', k, ''label'', l, ''value'', v, ''count'', c) order by %s), ''[]'')
       from (select %s as k, %s as l, %s as v, count(*) as c
               from %s %s where %s group by 1, 2 order by %s limit %s) t',
    ord, keyexpr, labelexpr, metexpr, base, joins, cond, ord, lim)
  into rows_ using d_from, d_to, f_status, f_person, f_client, f_service, f_prio;

  execute format('select jsonb_build_object(''value'', %s, ''count'', count(*)) from %s where %s', metexpr, base, cond)
  into total using d_from, d_to, f_status, f_person, f_client, f_service, f_prio;

  return jsonb_build_object('rows', rows_, 'total', total, 'source', src, 'group_by', grp, 'metric', met,
                            'from', d_from, 'to', d_to);
end $$;
