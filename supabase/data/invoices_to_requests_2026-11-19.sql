-- تحويل الفواتير غير المدفوعة بالكامل إلى طلبات قيد التنفيذ بخطواتها
-- يتطلب تشغيل migration: 20261119210000_request_steps.sql أولًا، وملف استيراد دفترة.
-- آمن للتشغيل أكثر من مرة.
begin;

-- DF-000007
insert into requests (title, description, client_id, status, priority, service_type, assignee_id, received_at, estimated_value)
select 'تطوير أرض صناعية: اعتماد المخطط وتعديل الاستخدام ورخصة النقل اللوجستي', 'من فاتورة دفترة DF-000007 · صافي الفاتورة 75,037.5 ر.س · المتبقي 42,412.5 ر.س', c.id, 'in_progress', 'medium', 'تراخيص وتصاريح حكومية', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), '2025-08-26', 75037.5
from clients c where c.custom->>'daftra_client_no' = '000009'
  and not exists (select 1 from requests r where r.description like '%DF-000007 %');
insert into request_steps (request_id, title, sort_order)
select r.id, s.title, s.ord from requests r,
  (values
  ('اعتماد المخطط العمراني للأرض الصناعية', 1),
  ('إضافة استخدام «سكني» لوصف استخدام الأرض في اشتراطات البناء', 2),
  ('إصدار رخصة بلدية لنشاط «النقل البري اللوجستي»', 3),
  ('المساعدة في طلب توصيل الكهرباء حسب المخطط المعتمد', 4),
  ('تسليم نسخ الموافقات والرخص', 5)) as s(title, ord)
where r.description like '%DF-000007 %'
  and not exists (select 1 from request_steps x where x.request_id = r.id);
insert into followups (title, direction, owner_id, counterpart, due_at, related_type, related_id, source)
select 'تحصيل المتبقي من فاتورة DF-000007: 42,412.5 ر.س', 'waiting', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), c.name, now(), 'invoice', i.id, 'manual'
from invoices i join clients c on c.id = i.client_id where i.number = 'DF-000007'
  and not exists (select 1 from followups f where f.related_id = i.id);

-- DF-000012
insert into requests (title, description, client_id, status, priority, service_type, assignee_id, received_at, estimated_value)
select 'طلب أرض لوجستية (٤٠٬٠٠٠ م²) عبر منصة فرص', 'من فاتورة دفترة DF-000012 · صافي الفاتورة 92,000 ر.س · المتبقي 76,000 ر.س', c.id, 'in_progress', 'medium', 'تراخيص وتصاريح حكومية', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), '2025-09-07', 92000
from clients c where c.custom->>'daftra_client_no' = '000010'
  and not exists (select 1 from requests r where r.description like '%DF-000012 %');
insert into request_steps (request_id, title, sort_order)
select r.id, s.title, s.ord from requests r,
  (values
  ('مراجعة المتطلبات وجاهزية المستندات', 1),
  ('إعداد الطلب وتقديمه إلكترونيًا عبر منصة فرص', 2),
  ('متابعة الطلب مع الجهة المختصة', 3),
  ('التنسيق مع العميل في أي متطلبات إضافية', 4),
  ('صدور الموافقة المبدئية', 5)) as s(title, ord)
where r.description like '%DF-000012 %'
  and not exists (select 1 from request_steps x where x.request_id = r.id);
insert into followups (title, direction, owner_id, counterpart, due_at, related_type, related_id, source)
select 'تحصيل المتبقي من فاتورة DF-000012: 76,000 ر.س', 'waiting', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), c.name, now(), 'invoice', i.id, 'manual'
from invoices i join clients c on c.id = i.client_id where i.number = 'DF-000012'
  and not exists (select 1 from followups f where f.related_id = i.id);

-- DF-000021
insert into requests (title, description, client_id, status, priority, service_type, assignee_id, received_at, estimated_value)
select 'تراخيص المصنع: البلدية والدفاع المدني والصناعي والبيئي وهيئة الغذاء والدواء', 'من فاتورة دفترة DF-000021 · صافي الفاتورة 35,700 ر.س · المتبقي 14,280 ر.س', c.id, 'in_progress', 'medium', 'تراخيص وتصاريح حكومية', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), '2026-04-08', 35700
from clients c where c.custom->>'daftra_client_no' = '000014'
  and not exists (select 1 from requests r where r.description like '%DF-000021 %');
insert into request_steps (request_id, title, sort_order)
select r.id, s.title, s.ord from requests r,
  (values
  ('إصدار الرخصة البلدية', 1),
  ('إصدار رخصة الدفاع المدني', 2),
  ('إصدار الترخيص الصناعي', 3),
  ('إصدار التصريح البيئي', 4),
  ('التسجيل في هيئة الغذاء والدواء واعتماد المنتجات', 5)) as s(title, ord)
where r.description like '%DF-000021 %'
  and not exists (select 1 from request_steps x where x.request_id = r.id);
insert into followups (title, direction, owner_id, counterpart, due_at, related_type, related_id, source)
select 'تحصيل المتبقي من فاتورة DF-000021: 14,280 ر.س', 'waiting', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), c.name, now(), 'invoice', i.id, 'manual'
from invoices i join clients c on c.id = i.client_id where i.number = 'DF-000021'
  and not exists (select 1 from followups f where f.related_id = i.id);

-- DF-000022
insert into requests (title, description, client_id, status, priority, service_type, assignee_id, received_at, estimated_value)
select 'الرخصة البلدية ورخصة الدفاع المدني', 'من فاتورة دفترة DF-000022 · صافي الفاتورة 11,471.25 ر.س · المتبقي 6,471.25 ر.س', c.id, 'in_progress', 'medium', 'تراخيص وتصاريح حكومية', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), '2026-04-08', 11471.25
from clients c where c.custom->>'daftra_client_no' = '000015'
  and not exists (select 1 from requests r where r.description like '%DF-000022 %');
insert into request_steps (request_id, title, sort_order)
select r.id, s.title, s.ord from requests r,
  (values
  ('إصدار الرخصة البلدية', 1),
  ('إصدار رخصة الدفاع المدني', 2),
  ('إعداد تقرير الفحص الفني', 3),
  ('إعداد عقد صيانة أنظمة ومعدات السلامة', 4),
  ('التنسيق مع الجهات ومتابعة الطلبات', 5),
  ('تجهيز الموقع قبل زيارات التفتيش', 6),
  ('معالجة الملاحظات حتى إصدار الرخصة النهائية', 7)) as s(title, ord)
where r.description like '%DF-000022 %'
  and not exists (select 1 from request_steps x where x.request_id = r.id);
insert into followups (title, direction, owner_id, counterpart, due_at, related_type, related_id, source)
select 'تحصيل المتبقي من فاتورة DF-000022: 6,471.25 ر.س', 'waiting', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), c.name, now(), 'invoice', i.id, 'manual'
from invoices i join clients c on c.id = i.client_id where i.number = 'DF-000022'
  and not exists (select 1 from followups f where f.related_id = i.id);

-- DF-000023
insert into requests (title, description, client_id, status, priority, service_type, assignee_id, received_at, estimated_value)
select 'تطوير أرض صناعية: المخطط وتصاريح البناء والدراسات ورخصة النقل', 'من فاتورة دفترة DF-000023 · صافي الفاتورة 75,037.5 ر.س · المتبقي 48,937.5 ر.س', c.id, 'in_progress', 'medium', 'تراخيص وتصاريح حكومية', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), '2026-04-08', 75037.5
from clients c where c.custom->>'daftra_client_no' = '000010'
  and not exists (select 1 from requests r where r.description like '%DF-000023 %');
insert into request_steps (request_id, title, sort_order)
select r.id, s.title, s.ord from requests r,
  (values
  ('اعتماد مخطط الأرض الصناعية', 1),
  ('إصدار تصاريح البناء (وحدة سكنية + ورشة)', 2),
  ('دراسات التربة والهيدرولوجيا', 3),
  ('التصاميم الهندسية ومخططات السلامة (الدفاع المدني)', 4),
  ('إصدار رخصة نشاط النقل', 5),
  ('المساعدة في توصيل الكهرباء', 6),
  ('تسليم نسخ الموافقات والتصاريح والدراسات', 7)) as s(title, ord)
where r.description like '%DF-000023 %'
  and not exists (select 1 from request_steps x where x.request_id = r.id);
insert into followups (title, direction, owner_id, counterpart, due_at, related_type, related_id, source)
select 'تحصيل المتبقي من فاتورة DF-000023: 48,937.5 ر.س', 'waiting', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), c.name, now(), 'invoice', i.id, 'manual'
from invoices i join clients c on c.id = i.client_id where i.number = 'DF-000023'
  and not exists (select 1 from followups f where f.related_id = i.id);

-- DF-000028
insert into requests (title, description, client_id, status, priority, service_type, assignee_id, received_at, estimated_value)
select 'تراخيص تشغيل مدارس الخبر وبقيق', 'من فاتورة دفترة DF-000028 · صافي الفاتورة 6,900 ر.س · المتبقي 900 ر.س', c.id, 'in_progress', 'medium', 'تراخيص وتصاريح حكومية', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), '2026-08-17', 6900
from clients c where c.custom->>'daftra_client_no' = '000017'
  and not exists (select 1 from requests r where r.description like '%DF-000028 %');
insert into request_steps (request_id, title, sort_order)
select r.id, s.title, s.ord from requests r,
  (values
  ('الموافقة المبدئية', 1),
  ('الرخصة البلدية', 2),
  ('رخصة الدفاع المدني', 3),
  ('رخصة التشغيل النهائية', 4)) as s(title, ord)
where r.description like '%DF-000028 %'
  and not exists (select 1 from request_steps x where x.request_id = r.id);
insert into followups (title, direction, owner_id, counterpart, due_at, related_type, related_id, source)
select 'تحصيل المتبقي من فاتورة DF-000028: 900 ر.س', 'waiting', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), c.name, now(), 'invoice', i.id, 'manual'
from invoices i join clients c on c.id = i.client_id where i.number = 'DF-000028'
  and not exists (select 1 from followups f where f.related_id = i.id);

-- DF-000030
insert into requests (title, description, client_id, status, priority, service_type, assignee_id, received_at, estimated_value)
select 'تجديد وتعديل ونقل الرخصة البلدية والترخيص الصناعي', 'من فاتورة دفترة DF-000030 · صافي الفاتورة 10,350 ر.س · المتبقي 5,350 ر.س', c.id, 'in_progress', 'medium', 'تراخيص وتصاريح حكومية', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), '2026-11-12', 10350
from clients c where c.custom->>'daftra_client_no' = '000018'
  and not exists (select 1 from requests r where r.description like '%DF-000030 %');
insert into request_steps (request_id, title, sort_order)
select r.id, s.title, s.ord from requests r,
  (values
  ('تجديد وتعديل ونقل الرخصة البلدية', 1),
  ('إصدار رخصة الدفاع المدني', 2),
  ('إصدار الترخيص الصناعي', 3),
  ('تحديث بيانات اتفاقية الاستثمار مع البلدية', 4)) as s(title, ord)
where r.description like '%DF-000030 %'
  and not exists (select 1 from request_steps x where x.request_id = r.id);
insert into followups (title, direction, owner_id, counterpart, due_at, related_type, related_id, source)
select 'تحصيل المتبقي من فاتورة DF-000030: 5,350 ر.س', 'waiting', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), c.name, now(), 'invoice', i.id, 'manual'
from invoices i join clients c on c.id = i.client_id where i.number = 'DF-000030'
  and not exists (select 1 from followups f where f.related_id = i.id);

-- باقة RAS Ambition الشهرية: مشروع واحد ومتابعة تحصيل للأقساط المتأخرة
insert into projects (name, client_id, manager_id, status, start_date)
select 'الباقة السنوية لخدمات الأعمال – RAS Ambition', c.id, (select id from profiles where role = 'owner' and is_active order by created_at limit 1), 'active', '2025-06-26'
from clients c where c.custom->>'daftra_client_no' = '000001'
  and not exists (select 1 from projects p where p.name = 'الباقة السنوية لخدمات الأعمال – RAS Ambition');
insert into followups (title, direction, owner_id, counterpart, due_at, related_type, related_id, source)
select 'تحصيل أقساط الباقة المتأخرة (DF-000016 إلى DF-000020): 17,012 ر.س', 'waiting', (select id from profiles where role = 'owner' and is_active order by created_at limit 1), c.name, now(), 'client', c.id, 'manual'
from clients c where c.custom->>'daftra_client_no' = '000001'
  and not exists (select 1 from followups f where f.related_id = c.id and f.title like 'تحصيل أقساط الباقة%');

commit;

select (select count(*) from requests where description like 'من فاتورة دفترة%') as requests,
       (select count(*) from request_steps) as steps,
       (select count(*) from followups where title like 'تحصيل%') as followups;
