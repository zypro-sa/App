-- استيراد بيانات دفترة: العملاء وجهات التواصل والفواتير والمدفوعات
-- آمن للتشغيل أكثر من مرة: لا يكرر عميلًا أو فاتورة موجودة.
-- الفواتير المرتجعة بالكامل مستبعدة، وذات المرتجع الجزئي بصافي قيمتها.
begin;

-- ١. العملاء
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'RAS Ambition', 'company', 'active', 'Jubail', null, '310508408100003', '7016074903', '{"daftra_client_no": "000001"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000001' or lower(trim(name)) = lower('RAS Ambition'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'Nexus Middle East', 'company', 'active', 'Jubail', null, '311187282600003', '7035258966', '{"daftra_client_no": "000004"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000004' or lower(trim(name)) = lower('Nexus Middle East'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'AMG Global', 'company', 'active', null, null, '311920491500003', '7011766651', '{"daftra_client_no": "000005"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000005' or lower(trim(name)) = lower('AMG Global'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'Jal Al-Jubail Cont. Est', 'company', 'active', 'Jubail', null, null, '7006463389', '{"daftra_client_no": "000006"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000006' or lower(trim(name)) = lower('Jal Al-Jubail Cont. Est'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'SST Infraproject Arabia Co', 'company', 'active', 'Jubail', null, '311666698600003', '7034990882', '{"daftra_client_no": "000007"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000007' or lower(trim(name)) = lower('SST Infraproject Arabia Co'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'TIM Construction Co', 'company', 'active', 'Jubail', '4113 12 - 6794 - Aldhabab - 35712', '311612274100003', '7035033435', '{"daftra_client_no": "000008"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000008' or lower(trim(name)) = lower('TIM Construction Co'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'Almuzain Gulf Saudi Contracting Co', 'company', 'active', 'Jubail', null, '310539035700003', '7001646913', '{"daftra_client_no": "000009"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000009' or lower(trim(name)) = lower('Almuzain Gulf Saudi Contracting Co'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'United Technology Co', 'company', 'active', 'Jubail', null, '310157378500003', '7009625224', '{"daftra_client_no": "000010"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000010' or lower(trim(name)) = lower('United Technology Co'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'Nuqaim Holdings', 'company', 'active', null, null, null, null, '{"daftra_client_no": "000011"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000011' or lower(trim(name)) = lower('Nuqaim Holdings'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'شركة مكشطة الأريج العالمية المحدودة', 'company', 'active', null, null, '311869495700003', '7037075699', '{"daftra_client_no": "000012"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000012' or lower(trim(name)) = lower('شركة مكشطة الأريج العالمية المحدودة'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'شركة نظام ربط الشبكات العربيه التجارية', 'company', 'active', 'الخبر', '2677 الامير بدر بن عبدالعزيز - 6375 - الخبر الشمالية - 34429', '311304444500003', '7006505270', '{"daftra_client_no": "000013"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000013' or lower(trim(name)) = lower('شركة نظام ربط الشبكات العربيه التجارية'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'Zaitoon Foods Company', 'company', 'active', null, null, null, '7037086795', '{"daftra_client_no": "000014"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000014' or lower(trim(name)) = lower('Zaitoon Foods Company'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'شركة السهم الثلاثي التجارية', 'company', 'active', 'الدمام', '7094 التاسع - 3097 - الدواسر - 32416', null, '7037313918', '{"daftra_client_no": "000015"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000015' or lower(trim(name)) = lower('شركة السهم الثلاثي التجارية'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'Barakah School', 'company', 'active', 'الجبيل', '8880 King Faisal West Road - ENAA8880 3248 - التعاون - 35518', '311953543100003', '7037506628', '{"daftra_client_no": "000016"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000016' or lower(trim(name)) = lower('Barakah School'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'Barakah Integrated Services And Maintenance International Company', 'company', 'active', 'Dammam', '3664 C5 - 7721 - Al Rakah - 34225', null, '7052846651', '{"daftra_client_no": "000017"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000017' or lower(trim(name)) = lower('Barakah Integrated Services And Maintenance International Company'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'Power Integrated Industrial Services LLC', 'company', 'active', 'Jubail', '4665 1023 - ENDB4665 7888 - C6 - 35521', null, '7007994580', '{"daftra_client_no": "000018"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000018' or lower(trim(name)) = lower('Power Integrated Industrial Services LLC'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'Akio Kuno Contracting Company', 'company', 'active', null, 'ENAA6867', null, '7001552392', '{"daftra_client_no": "000019"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000019' or lower(trim(name)) = lower('Akio Kuno Contracting Company'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'Creative Kids Company', 'company', 'active', null, null, null, '7051532831', '{"daftra_client_no": "000020"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000020' or lower(trim(name)) = lower('Creative Kids Company'));
insert into clients (name, type, status, city, address, vat_number, cr_number, custom)
select 'Best Gulf Overseas', 'company', 'active', null, 'ENDC3640', null, '7029245011', '{"daftra_client_no": "000021"}'::jsonb
where not exists (select 1 from clients where custom->>'daftra_client_no' = '000021' or lower(trim(name)) = lower('Best Gulf Overseas'));

-- ٢. جهات التواصل
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'Abdullattif', '0592166370', 'latheefkc123@gmail.com', true from clients
where custom->>'daftra_client_no' = '000005'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'Abdullattif');
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'Talib Kayani', '0566400934', 'atifkayani026@gmail.com', true from clients
where custom->>'daftra_client_no' = '000006'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'Talib Kayani');
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'Mohammed Irfaan', '0590466909', 'Info@sstsaudi.com', true from clients
where custom->>'daftra_client_no' = '000007'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'Mohammed Irfaan');
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'Ismail Khan', '0535432228', 'timccinf@gmail.com', true from clients
where custom->>'daftra_client_no' = '000008'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'Ismail Khan');
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'Zaheer Zakaria', '0540440587', null, true from clients
where custom->>'daftra_client_no' = '000009'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'Zaheer Zakaria');
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'Hyder Ali', '0545313444', 'hyder@unitedco.uk', true from clients
where custom->>'daftra_client_no' = '000010'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'Hyder Ali');
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'شركة مكشطة الأريج العالمية المحدودة', '0545533553', null, true from clients
where custom->>'daftra_client_no' = '000012'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'شركة مكشطة الأريج العالمية المحدودة');
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'شركة نظام ربط الشبكات العربيه التجارية', '0502513428', null, true from clients
where custom->>'daftra_client_no' = '000013'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'شركة نظام ربط الشبكات العربيه التجارية');
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'Kannanthodi Shihabudheen', null, null, true from clients
where custom->>'daftra_client_no' = '000015'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'Kannanthodi Shihabudheen');
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'SREEJITH CHANDRAN', '0569338993', null, true from clients
where custom->>'daftra_client_no' = '000018'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'SREEJITH CHANDRAN');
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'SHUHAIB MALIACKAL', '0542308896', null, true from clients
where custom->>'daftra_client_no' = '000019'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'SHUHAIB MALIACKAL');
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'Creative Kids Company', '0501164598', null, true from clients
where custom->>'daftra_client_no' = '000020'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'Creative Kids Company');
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'Best Gulf Overseas', '0583078105', null, true from clients
where custom->>'daftra_client_no' = '000021'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'Best Gulf Overseas');
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'Zeeshan', '0545272864', 'zeeshan@rasambition.com', true from clients
where custom->>'daftra_client_no' = '000001'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'Zeeshan');
insert into contacts (client_id, name, phone, email, is_primary)
select id, 'Imtiyaz', '0581375111', 'imtiaz@nexusmiddleeast.com', true from clients
where custom->>'daftra_client_no' = '000004'
  and not exists (select 1 from contacts ct where ct.client_id = clients.id and ct.name = 'Imtiyaz');

-- ٣. الفواتير
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000004', id, 1725.0, '2025-06-25', '2025-06-25', 'issued' from clients
where custom->>'daftra_client_no' = '000006'
  and not exists (select 1 from invoices where number = 'DF-000004');
insert into payments (invoice_id, amount, paid_at, method)
select id, 1725.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000004' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000005', id, 29900.0, '2025-06-29', '2025-06-29', 'issued' from clients
where custom->>'daftra_client_no' = '000008'
  and not exists (select 1 from invoices where number = 'DF-000005');
insert into payments (invoice_id, amount, paid_at, method)
select id, 29900.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000005' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000006', id, 13800.0, '2025-07-17', '2025-07-17', 'issued' from clients
where custom->>'daftra_client_no' = '000005'
  and not exists (select 1 from invoices where number = 'DF-000006');
insert into payments (invoice_id, amount, paid_at, method)
select id, 13800.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000006' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000007', id, 75037.5, '2025-08-26', '2025-08-26', 'issued' from clients
where custom->>'daftra_client_no' = '000009'
  and not exists (select 1 from invoices where number = 'DF-000007');
insert into payments (invoice_id, amount, paid_at, method)
select id, 32625.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000007' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000008', id, 12937.5, '2025-08-26', '2025-08-26', 'issued' from clients
where custom->>'daftra_client_no' = '000007'
  and not exists (select 1 from invoices where number = 'DF-000008');
insert into payments (invoice_id, amount, paid_at, method)
select id, 12937.5, issue_date, 'bank_transfer' from invoices
where number = 'DF-000008' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000009', id, 6003.0, '2025-06-26', '2025-07-01', 'issued' from clients
where custom->>'daftra_client_no' = '000001'
  and not exists (select 1 from invoices where number = 'DF-000009');
insert into payments (invoice_id, amount, paid_at, method)
select id, 6003.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000009' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000010', id, 6003.0, '2025-07-27', '2025-08-01', 'issued' from clients
where custom->>'daftra_client_no' = '000001'
  and not exists (select 1 from invoices where number = 'DF-000010');
insert into payments (invoice_id, amount, paid_at, method)
select id, 6003.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000010' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000011', id, 6003.0, '2025-08-27', '2025-09-01', 'issued' from clients
where custom->>'daftra_client_no' = '000001'
  and not exists (select 1 from invoices where number = 'DF-000011');
insert into payments (invoice_id, amount, paid_at, method)
select id, 6003.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000011' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000012', id, 92000.0, '2025-09-07', '2025-09-07', 'issued' from clients
where custom->>'daftra_client_no' = '000010'
  and not exists (select 1 from invoices where number = 'DF-000012');
insert into payments (invoice_id, amount, paid_at, method)
select id, 16000.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000012' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000013', id, 6003.0, '2025-09-26', '2025-10-01', 'issued' from clients
where custom->>'daftra_client_no' = '000001'
  and not exists (select 1 from invoices where number = 'DF-000013');
insert into payments (invoice_id, amount, paid_at, method)
select id, 6003.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000013' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000014', id, 6003.0, '2025-10-27', '2025-11-01', 'issued' from clients
where custom->>'daftra_client_no' = '000001'
  and not exists (select 1 from invoices where number = 'DF-000014');
insert into payments (invoice_id, amount, paid_at, method)
select id, 6003.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000014' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000015', id, 6003.0, '2025-11-26', '2025-12-01', 'issued' from clients
where custom->>'daftra_client_no' = '000001'
  and not exists (select 1 from invoices where number = 'DF-000015');
insert into payments (invoice_id, amount, paid_at, method)
select id, 6003.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000015' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000016', id, 6003.0, '2025-12-27', '2026-01-01', 'issued' from clients
where custom->>'daftra_client_no' = '000001'
  and not exists (select 1 from invoices where number = 'DF-000016');
insert into payments (invoice_id, amount, paid_at, method)
select id, 3500.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000016' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000017', id, 6003.0, '2026-01-27', '2026-02-01', 'issued' from clients
where custom->>'daftra_client_no' = '000001'
  and not exists (select 1 from invoices where number = 'DF-000017');
insert into payments (invoice_id, amount, paid_at, method)
select id, 3500.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000017' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000018', id, 6003.0, '2026-02-24', '2026-03-01', 'issued' from clients
where custom->>'daftra_client_no' = '000001'
  and not exists (select 1 from invoices where number = 'DF-000018');
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000019', id, 2875.0, '2026-03-25', '2026-03-25', 'issued' from clients
where custom->>'daftra_client_no' = '000013'
  and not exists (select 1 from invoices where number = 'DF-000019');
insert into payments (invoice_id, amount, paid_at, method)
select id, 2875.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000019' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000020', id, 6003.0, '2026-03-27', '2026-04-01', 'issued' from clients
where custom->>'daftra_client_no' = '000001'
  and not exists (select 1 from invoices where number = 'DF-000020');
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000021', id, 35700.0, '2026-04-08', '2026-04-08', 'issued' from clients
where custom->>'daftra_client_no' = '000014'
  and not exists (select 1 from invoices where number = 'DF-000021');
insert into payments (invoice_id, amount, paid_at, method)
select id, 21420.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000021' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000022', id, 11471.25, '2026-04-08', '2026-04-08', 'issued' from clients
where custom->>'daftra_client_no' = '000015'
  and not exists (select 1 from invoices where number = 'DF-000022');
insert into payments (invoice_id, amount, paid_at, method)
select id, 5000.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000022' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000023', id, 75037.5, '2026-04-08', '2026-04-08', 'issued' from clients
where custom->>'daftra_client_no' = '000010'
  and not exists (select 1 from invoices where number = 'DF-000023');
insert into payments (invoice_id, amount, paid_at, method)
select id, 26100.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000023' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000024', id, 22482.5, '2026-04-08', '2026-04-08', 'issued' from clients
where custom->>'daftra_client_no' = '000008'
  and not exists (select 1 from invoices where number = 'DF-000024');
insert into payments (invoice_id, amount, paid_at, method)
select id, 22482.5, issue_date, 'bank_transfer' from invoices
where number = 'DF-000024' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000027', id, 5750.0, '2026-08-03', '2026-08-03', 'issued' from clients
where custom->>'daftra_client_no' = '000016'
  and not exists (select 1 from invoices where number = 'DF-000027');
insert into payments (invoice_id, amount, paid_at, method)
select id, 5750.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000027' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000028', id, 6900.0, '2026-08-17', '2026-08-17', 'issued' from clients
where custom->>'daftra_client_no' = '000017'
  and not exists (select 1 from invoices where number = 'DF-000028');
insert into payments (invoice_id, amount, paid_at, method)
select id, 6000.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000028' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000029', id, 1725.0, '2026-10-20', '2026-11-02', 'issued' from clients
where custom->>'daftra_client_no' = '000019'
  and not exists (select 1 from invoices where number = 'DF-000029');
insert into payments (invoice_id, amount, paid_at, method)
select id, 1725.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000029' and not exists (select 1 from payments p where p.invoice_id = invoices.id);
insert into invoices (number, client_id, total, issue_date, due_date, status)
select 'DF-000030', id, 10350.0, '2026-11-12', '2026-11-12', 'issued' from clients
where custom->>'daftra_client_no' = '000018'
  and not exists (select 1 from invoices where number = 'DF-000030');
insert into payments (invoice_id, amount, paid_at, method)
select id, 5000.0, issue_date, 'bank_transfer' from invoices
where number = 'DF-000030' and not exists (select 1 from payments p where p.invoice_id = invoices.id);

commit;

-- التحقق: عدد ما استُورد
select (select count(*) from clients where custom ? 'daftra_client_no') as clients,
       (select count(*) from invoices where number like 'DF-%') as invoices,
       (select count(*) from payments p join invoices i on i.id = p.invoice_id where i.number like 'DF-%') as payments;
