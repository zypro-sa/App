-- منح المستخدمين المسجّلين صلاحية الوصول للجداول عبر واجهة Supabase.
-- مشاريع Supabase الحديثة لا تمنح هذه الصلاحية تلقائيًا للجداول المنشأة بـ SQL.
-- الحماية الفعلية تبقى في سياسات RLS: كل مستخدم يرى ما تسمح له به فقط.

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- الجداول التي تُضاف مستقبلًا
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant usage, select on sequences to authenticated;
