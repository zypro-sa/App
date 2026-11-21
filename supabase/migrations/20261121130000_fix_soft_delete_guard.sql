-- إصلاح: حذف المهام كان يفشل برسالة «record "old" has no field "owner_id"»
-- لأن الشرط كان يقرأ حقلًا غير موجود في جدول المهام. نقرأ الحقول الآن بأمان.
create or replace function guard_soft_delete() returns trigger
language plpgsql as $$
declare
  module text := coalesce(tg_argv[0], tg_table_name);
  row_old jsonb := to_jsonb(old);
begin
  if new.deleted_at is distinct from old.deleted_at
     and auth.uid() is not null
     and not has_perm(module || '.delete')
     and not (tg_table_name = 'tasks' and row_old ->> 'created_by' = auth.uid()::text)
     and not (tg_table_name = 'followups' and row_old ->> 'owner_id' = auth.uid()::text) then
    raise exception 'ليست لديك صلاحية الحذف';
  end if;
  return new;
end $$;
