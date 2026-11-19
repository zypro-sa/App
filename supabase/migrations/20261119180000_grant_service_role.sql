-- منح دور الخدمة (service_role) صلاحية الجداول.
-- تستخدمه دالة invite-member على الخادم فقط؛ لا يصل للتطبيق أبدًا.
-- مشاريع Supabase الحديثة لا تمنح هذه الصلاحية تلقائيًا للجداول المنشأة بـ SQL.

grant usage on schema public to service_role;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;
