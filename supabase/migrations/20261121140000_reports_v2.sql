-- =====================================================================
-- التقارير (الإصدار الثاني)
-- report_dashboard: كل أرقام التقارير في استدعاء واحد
-- report_list: القوائم التفصيلية خلف كل رقم
-- report_goals: أهداف الشهر
-- الملخص الأسبوعي: إشعار صباح كل أحد
-- =====================================================================

create table if not exists report_goals (
  id          uuid primary key default gen_random_uuid(),
  month       date not null,                 -- أول يوم في الشهر
  metric      text not null check (metric in
                ('requests_closed', 'collected', 'on_time', 'new_clients', 'tasks_done', 'meetings_held')),
  target      numeric not null check (target > 0),
  created_at  timestamptz not null default now(),
  created_by  uuid references profiles (id) on delete set null default auth.uid(),
  unique (month, metric)
);

alter table report_goals enable row level security;
create policy report_goals_select on report_goals for select to authenticated using (has_perm('reports.view'));
create policy report_goals_write on report_goals for all to authenticated
  using (has_perm('reports.view')) with check (has_perm('reports.view'));
grant select, insert, update, delete on report_goals to authenticated;
grant all on report_goals to service_role;

-- المتبقي على فاتورة (بعد المرتجعات والدفعات)
create or replace function invoice_remaining(p_invoice uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select greatest(invoice_net_total(p_invoice)
         - coalesce((select sum(amount) from payments where invoice_id = p_invoice and deleted_at is null), 0), 0)
$$;

-- ---------------------------------------------------------------------
-- لوحة التقارير
-- p_member: تقرير عضو واحد (يراه العضو لنفسه دائمًا)
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
      'avg_days',    (select round(avg(extract(epoch from closed_at - created_at) / 86400)::numeric, 1)
                        from r where status = 'closed' and closed_at::date between p_from and p_to),
      'avg_days_prev',(select round(avg(extract(epoch from closed_at - created_at) / 86400)::numeric, 1)
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
             round(avg(extract(epoch from closed_at - created_at) / 86400)
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
               (select round(avg(extract(epoch from r.closed_at - r.created_at) / 86400)::numeric, 1)
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

grant execute on function report_dashboard(date, date, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- القوائم التفصيلية
-- ---------------------------------------------------------------------
create or replace function report_list(p_kind text, p_from date, p_to date, p_member uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Riyadh')::date;
  m uuid := p_member;
  fin boolean := has_perm('finance.view');
begin
  if not (has_perm('reports.view') or (m is not null and m = auth.uid())) then
    raise exception 'ليست لديك صلاحية التقارير';
  end if;
  if p_kind in ('unpaid_closed', 'quotes_no_reply', 'late_invoices') and not fin then
    raise exception 'ليست لديك صلاحية المالية';
  end if;

  return coalesce((
    select jsonb_agg(row_to_json(x)) from (
      -- الطلبات
      select r.id, 'request' as kind, '#' || r.number || ' · ' || r.title as title,
             concat_ws(' · ', c.name, p.name, r.service_type) as subtitle,
             case p_kind
               when 'overdue' then 'متأخر ' || (today - r.due_date) || ' يوم'
               when 'waiting_long' then (today - r.updated_at::date) || ' يوم بانتظار العميل'
               when 'closed' then to_char(r.closed_at, 'YYYY-MM-DD')
               else r.status::text end as badge,
             case when p_kind = 'overdue' or r.due_date < today then 'urgent'
                  when r.status = 'waiting_client' then 'waiting' else 'neutral' end as tone,
             coalesce(r.estimated_value, 0) as amount, r.due_date::text as date,
             c.name as client, p.name as assignee
      from requests r
      left join clients c on c.id = r.client_id
      left join profiles p on p.id = r.assignee_id
      where p_kind in ('overdue', 'waiting_long', 'closed', 'open', 'new')
        and r.deleted_at is null and (m is null or r.assignee_id = m)
        and case p_kind
              when 'overdue' then r.status not in ('closed', 'cancelled') and r.due_date < today
              when 'waiting_long' then r.status = 'waiting_client' and r.updated_at < now() - interval '7 days'
              when 'closed' then r.status = 'closed' and r.closed_at::date between p_from and p_to
              when 'new' then r.created_at::date between p_from and p_to
              else r.status not in ('closed', 'cancelled') end
      union all
      -- طلبات مكتملة لم تُحصّل
      select r.id, 'request', '#' || r.number || ' · ' || r.title, concat_ws(' · ', c.name, i.number),
             'متبقٍ ' || to_char(invoice_remaining(i.id), 'FM999,999,990'), 'waiting', invoice_remaining(i.id),
             i.due_date::text, c.name, null
      from requests r join invoices i on i.request_id = r.id left join clients c on c.id = r.client_id
      where p_kind = 'unpaid_closed' and r.deleted_at is null and r.status = 'closed'
        and i.deleted_at is null and i.status <> 'void' and invoice_remaining(i.id) > 0
      union all
      -- عروض بلا رد
      select q.id, 'quote', q.number, c.name, 'منذ ' || (today - q.sent_at) || ' يوم', 'waiting', q.amount + q.vat_amount,
             q.sent_at::text, c.name, null
      from quotes q left join clients c on c.id = q.client_id
      where p_kind = 'quotes_no_reply' and q.deleted_at is null and q.status = 'sent' and q.sent_at <= today - 3
      union all
      -- فواتير متأخرة
      select i.id, 'invoice', i.number, c.name, 'متأخرة ' || (today - i.due_date) || ' يوم', 'urgent', invoice_remaining(i.id),
             i.due_date::text, c.name, null
      from invoices i left join clients c on c.id = i.client_id
      where p_kind = 'late_invoices' and i.deleted_at is null and i.status <> 'void' and i.due_date < today and invoice_remaining(i.id) > 0
      union all
      -- مهام عضو
      select t.id, 'task', t.title, concat_ws(' · ', c.name, p.name),
             case when t.due_at < now() and t.status <> 'done' then 'متأخرة' when t.status = 'done' then 'منجزة' else 'مفتوحة' end,
             case when t.due_at < now() and t.status <> 'done' then 'urgent' when t.status = 'done' then 'done' else 'neutral' end,
             0, t.due_at::date::text, c.name, p.name
      from tasks t left join clients c on c.id = t.client_id left join profiles p on p.id = t.assignee_id
      where p_kind = 'member_tasks' and t.deleted_at is null and t.assignee_id = m
        and (t.status <> 'done' or t.completed_at::date between p_from and p_to)
    ) x
  ), '[]');
end $$;

grant execute on function report_list(text, date, date, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- الملخص الأسبوعي: صباح الأحد (بتوقيت السعودية) للمالك ومن يملك صلاحية التقارير
-- يُستدعى من generate_notifications (كل ١٥ دقيقة) ويمنع التكرار بنفسه
-- ---------------------------------------------------------------------
create or replace function weekly_summary_notifications() returns void
language plpgsql security definer set search_path = public as $$
declare
  ksa timestamp := now() at time zone 'Asia/Riyadh';
  week_start date := ksa::date - 7;
  closed int; prev int; collected numeric; overdue int; quotes int;
  u record; en boolean;
begin
  if extract(dow from ksa) <> 0 or extract(hour from ksa) < 8 then return; end if;
  select count(*) into closed from requests where deleted_at is null and status = 'closed' and closed_at::date >= week_start;
  select count(*) into prev from requests where deleted_at is null and status = 'closed'
    and closed_at::date >= week_start - 7 and closed_at::date < week_start;
  select coalesce(sum(amount), 0) into collected from payments where deleted_at is null and paid_at >= week_start;
  select count(*) into overdue from requests where deleted_at is null and status not in ('closed', 'cancelled') and due_date < ksa::date;
  select count(*) into quotes from quotes where deleted_at is null and status = 'sent' and sent_at <= ksa::date - 3;
  for u in select id, locale from profiles where is_active and (role = 'owner' or perm_of(id, 'reports.view')) loop
    en := u.locale = 'en';
    perform notify_user(u.id, 'weekly_summary',
      case when en then 'Zypro · Weekly summary' else 'Zypro · ملخص الأسبوع' end,
      case when en then
        closed || ' requests closed (last week ' || prev || ')'
        || case when perm_of(u.id, 'finance.view') then ' · SAR ' || to_char(collected, 'FM999,999,990') || ' collected' else '' end
        || case when overdue > 0 then ' · ' || overdue || ' overdue requests' else '' end
        || case when quotes > 0 and perm_of(u.id, 'finance.view') then ' · ' || quotes || ' quotes with no reply' else '' end
      else
        'أنجزتم ' || closed || ' طلبات (الأسبوع السابق ' || prev || ')'
        || case when perm_of(u.id, 'finance.view') then ' · حصّلتم ' || to_char(collected, 'FM999,999,990') || ' ر.س' else '' end
        || case when overdue > 0 then ' · ' || overdue || ' طلبات متأخرة' else '' end
        || case when quotes > 0 and perm_of(u.id, 'finance.view') then ' · ' || quotes || ' عروض بلا رد' else '' end
      end,
      '/more/reports', null, null, now() - interval '6 days');
  end loop;
end $$;

revoke execute on function weekly_summary_notifications() from public, anon, authenticated;

-- تشغيله ضمن المهمة المجدولة الحالية
do $$
begin
  perform cron.schedule('weekly-summary', '*/15 * * * *', 'select weekly_summary_notifications()');
exception when others then null;
end $$;
