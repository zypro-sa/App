-- =====================================================================
-- التقارير المتقدمة
-- saved_reports + report_custom: منشئ التقارير حسب المدخلات (يحترم صلاحيات كل عضو)
-- report_workload: خريطة ضغط العمل للأيام القادمة
-- report_funnel: مسار البيع من العرض حتى التحصيل
-- report_client_tiers: تصنيف العملاء
-- =====================================================================

create table if not exists saved_reports (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(trim(name)) > 0),
  config      jsonb not null,
  owner_id    uuid not null default auth.uid() references profiles (id) on delete cascade,
  shared      boolean not null default false,   -- يراه كل الفريق (كلٌّ حسب صلاحياته على البيانات)
  pinned      boolean not null default false,   -- يظهر في لوحة «نظرة عامة»
  on_tv       boolean not null default false,   -- شريحة على شاشة المكتب
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table saved_reports enable row level security;
drop policy if exists saved_reports_select on saved_reports;
drop policy if exists saved_reports_insert on saved_reports;
drop policy if exists saved_reports_update on saved_reports;
drop policy if exists saved_reports_delete on saved_reports;
create policy saved_reports_select on saved_reports for select to authenticated using (owner_id = auth.uid() or shared);
create policy saved_reports_insert on saved_reports for insert to authenticated with check (owner_id = auth.uid());
create policy saved_reports_update on saved_reports for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy saved_reports_delete on saved_reports for delete to authenticated using (owner_id = auth.uid());
grant select, insert, update, delete on saved_reports to authenticated;
grant all on saved_reports to service_role;

-- ---------------------------------------------------------------------
-- منشئ التقارير
-- p: {source, from, to, date_basis, group_by, metric, limit,
--     filters: {status: [], person: uuid, client: uuid, service: text, priority: []}}
-- يعمل بصلاحيات المستخدم نفسه (security invoker) فلا يرى إلا ما يحق له.
-- كل الأعمدة من قوائم ثابتة، والقيم تمرّر كمعاملات — لا يوجد نص حر داخل الاستعلام.
-- ---------------------------------------------------------------------
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
      daysexpr := 'case when x.closed_at is not null then extract(epoch from x.closed_at - x.created_at) / 86400 end';
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

grant execute on function report_custom(jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- خريطة ضغط العمل: المواعيد المستحقة لكل عضو في الأيام القادمة
-- ---------------------------------------------------------------------
create or replace function report_workload(p_days int default 14)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Riyadh')::date;
  n int := least(greatest(coalesce(p_days, 14), 7), 31);
begin
  if not has_perm('reports.view') then raise exception 'ليست لديك صلاحية التقارير'; end if;
  return jsonb_build_object(
    'days', (select jsonb_agg(d::date order by d) from generate_series(today, today + n - 1, interval '1 day') d),
    'members', (select coalesce(jsonb_agg(row_to_json(x) order by x.total desc, x.name), '[]') from (
      select p.id, p.name, p.avatar_url,
        (select count(*) from tasks t where t.assignee_id = p.id and t.deleted_at is null and t.status <> 'done'
           and (t.due_at at time zone 'Asia/Riyadh')::date < today)
        + (select count(*) from requests r where r.assignee_id = p.id and r.deleted_at is null
           and r.status not in ('closed', 'cancelled') and r.due_date < today) as overdue,
        (select jsonb_agg(jsonb_build_object(
            'tasks', (select count(*) from tasks t where t.assignee_id = p.id and t.deleted_at is null and t.status <> 'done'
                        and (t.due_at at time zone 'Asia/Riyadh')::date = d::date),
            'requests', (select count(*) from requests r where r.assignee_id = p.id and r.deleted_at is null
                        and r.status not in ('closed', 'cancelled') and r.due_date = d::date),
            'meetings', (select count(*) from meetings m where m.deleted_at is null and m.status = 'scheduled'
                        and (m.start_at at time zone 'Asia/Riyadh')::date = d::date
                        and (m.created_by = p.id or exists (select 1 from meeting_attendees a where a.meeting_id = m.id and a.user_id = p.id)))
          ) order by d) from generate_series(today, today + n - 1, interval '1 day') d) as cells,
        (select count(*) from tasks t where t.assignee_id = p.id and t.deleted_at is null and t.status <> 'done'
           and (t.due_at at time zone 'Asia/Riyadh')::date between today and today + n - 1)
        + (select count(*) from requests r where r.assignee_id = p.id and r.deleted_at is null
           and r.status not in ('closed', 'cancelled') and r.due_date between today and today + n - 1) as total
      from profiles p where p.is_active) x)
  );
end $$;

grant execute on function report_workload(int) to authenticated;

-- ---------------------------------------------------------------------
-- مسار البيع: عروض الفترة ← أُرسلت ← قُبلت ← فُوترت ← حُصّلت
-- ---------------------------------------------------------------------
create or replace function report_funnel(p_from date, p_to date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_perm('finance.view') then raise exception 'ليست لديك صلاحية المالية'; end if;
  return (
    with q as (
      select q.*, q.amount + coalesce(q.vat_amount, 0) as val,
             (select i.id from invoices i
               where i.deleted_at is null and i.status <> 'void'
                 and (i.quote_id = q.id or (q.request_id is not null and i.request_id = q.request_id))
               order by i.issue_date limit 1) as inv
      from quotes q
      where q.deleted_at is null and coalesce(q.sent_at, q.created_at::date) between p_from and p_to
    )
    select jsonb_build_object('stages', jsonb_build_array(
      jsonb_build_object('key', 'created', 'count', count(*), 'value', coalesce(sum(val), 0)),
      jsonb_build_object('key', 'sent', 'count', count(*) filter (where status <> 'draft'),
                         'value', coalesce(sum(val) filter (where status <> 'draft'), 0)),
      jsonb_build_object('key', 'accepted', 'count', count(*) filter (where status = 'accepted' or inv is not null),
                         'value', coalesce(sum(val) filter (where status = 'accepted' or inv is not null), 0)),
      jsonb_build_object('key', 'invoiced', 'count', count(*) filter (where inv is not null),
                         'value', coalesce(sum(invoice_net_total(inv)) filter (where inv is not null), 0)),
      jsonb_build_object('key', 'collected', 'count', count(*) filter (where inv is not null and invoice_remaining(inv) = 0),
                         'value', coalesce(sum(invoice_net_total(inv) - invoice_remaining(inv)) filter (where inv is not null), 0))
    ), 'lost', jsonb_build_object(
      'rejected', count(*) filter (where status = 'rejected'),
      'expired', count(*) filter (where status = 'expired'),
      'waiting', count(*) filter (where status = 'sent' and inv is null)
    ))
    from q
  );
end $$;

grant execute on function report_funnel(date, date) to authenticated;

-- ---------------------------------------------------------------------
-- تصنيف العملاء: ذهبي، نشط، جديد، معرّض للفقد، خامل
-- ---------------------------------------------------------------------
create or replace function report_client_tiers()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Riyadh')::date;
  fin boolean := has_perm('finance.view');
begin
  if not has_perm('reports.view') then raise exception 'ليست لديك صلاحية التقارير'; end if;
  return (
    with c as (
      select cl.id, cl.name, cl.created_at::date as created,
        (select coalesce(sum(invoice_net_total(i.id)), 0) from invoices i
          where i.client_id = cl.id and i.deleted_at is null and i.status <> 'void' and i.issue_date > today - 365) as value,
        (select count(*) from requests r where r.client_id = cl.id and r.deleted_at is null and r.created_at > now() - interval '365 days') as requests,
        today - greatest(
          cl.created_at::date,
          coalesce((select max(r.updated_at)::date from requests r where r.client_id = cl.id and r.deleted_at is null), '1900-01-01'),
          coalesce((select max(m.start_at)::date from meetings m where m.client_id = cl.id and m.deleted_at is null and m.start_at <= now()), '1900-01-01'),
          coalesce((select max(i.issue_date) from invoices i where i.client_id = cl.id and i.deleted_at is null), '1900-01-01')
        ) as days
      from clients cl where cl.deleted_at is null
    ), ranked as (
      select c.*, percent_rank() over (order by case when fin then c.value else c.requests end desc) as pr,
             (case when fin then c.value else c.requests end) > 0 as has_score
      from c
    ), t as (
      select id, name, case when fin then value end as value, requests, days,
        case
          when has_score and pr <= 0.2 and days <= 90 then 'gold'
          when created > today - 30 then 'new'
          when days <= 45 then 'active'
          when days <= 120 then 'at_risk'
          else 'dormant'
        end as tier
      from ranked
    )
    select jsonb_build_object(
      'counts', jsonb_build_object(
        'gold', count(*) filter (where tier = 'gold'), 'active', count(*) filter (where tier = 'active'),
        'new', count(*) filter (where tier = 'new'), 'at_risk', count(*) filter (where tier = 'at_risk'),
        'dormant', count(*) filter (where tier = 'dormant')),
      'clients', coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'tier', tier, 'value', value,
                                                       'requests', requests, 'days', days)
                 order by array_position(array['gold', 'at_risk', 'active', 'new', 'dormant'], tier),
                          value desc nulls last, requests desc), '[]'),
      'can_finance', fin)
    from t
  );
end $$;

grant execute on function report_client_tiers() to authenticated;
