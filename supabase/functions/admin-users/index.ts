// إدارة الأعضاء (المالك، ومن يملك صلاحية الفريق): تعديل البيانات، تغيير كلمة المرور، الإيقاف، الحذف النهائي.
// تُنشر على Supabase باسم: admin-users
//
// الطلب (POST, JSON) — التعديل يحتاج team.edit، والإيقاف والحذف team.delete:
//   { action: "update", user_id, name?, job_title?, phone?, email? }
//   { action: "set_password", user_id, password }
//   { action: "set_active", user_id, active: boolean }
//   { action: "delete", user_id, transfer_to }

import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const clean = (v: unknown) => {
  if (v === undefined) return undefined;
  const s = String(v ?? "").trim();
  return s.length ? s : null;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: auth, error: authError } = await admin.auth.getUser(token);
    if (authError || !auth.user) return json({ error: "يجب تسجيل الدخول" }, 401);
    const { data: me } = await admin.from("profiles").select("role, is_active").eq("id", auth.user.id).single();
    if (!me?.is_active) return json({ error: "الحساب غير مفعّل" }, 403);
    const isOwner = me.role === "owner";
    const can = async (p: string) => {
      if (isOwner) return true;
      const { data } = await admin.rpc("perm_of", { p_user: auth.user!.id, p });
      return data === true;
    };

    const body = await req.json().catch(() => ({}));
    const action = String(body?.action ?? "");
    const userId = String(body?.user_id ?? "");
    if (!userId) return json({ error: "user_id مطلوب" }, 400);

    const { data: target } = await admin.from("profiles").select("id, role, email").eq("id", userId).single();
    if (!target) return json({ error: "العضو غير موجود" }, 404);
    const isSelf = userId === auth.user.id;
    // غير المالك لا يدير نفسه ولا المالك
    if (!isOwner && (isSelf || target.role === "owner")) return json({ error: "لا يمكنك تعديل هذا الحساب" }, 403);
    const needed = action === "set_active" || action === "delete" ? "team.delete" : "team.edit";
    if (!(await can(needed))) return json({ error: "ليست لديك صلاحية لهذا الإجراء" }, 403);

    switch (action) {
      case "update": {
        const profile: Record<string, unknown> = {};
        const name = clean(body.name);
        if (name !== undefined) {
          if (!name) return json({ error: "الاسم مطلوب" }, 400);
          profile.name = name;
        }
        if (body.job_title !== undefined) profile.job_title = clean(body.job_title);
        if (body.phone !== undefined) profile.phone = clean(body.phone);

        const email = clean(body.email);
        if (email !== undefined && email && email.toLowerCase() !== String(target.email).toLowerCase()) {
          if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "البريد غير صحيح" }, 400);
          const { error } = await admin.auth.admin.updateUserById(userId, { email, email_confirm: true });
          if (error) return json({ error: `تعذّر تغيير البريد: ${error.message}` }, 400);
          profile.email = email;
        }
        if (Object.keys(profile).length) {
          const { error } = await admin.from("profiles").update(profile).eq("id", userId);
          if (error) return json({ error: error.message }, 400);
        }
        return json({ ok: true });
      }

      case "set_password": {
        const password = String(body?.password ?? "");
        if (password.length < 8) return json({ error: "كلمة المرور ٨ أحرف على الأقل" }, 400);
        const { error } = await admin.auth.admin.updateUserById(userId, { password });
        if (error) return json({ error: error.message }, 400);
        return json({ ok: true });
      }

      case "set_active": {
        if (isSelf || target.role === "owner") return json({ error: "لا يمكن إيقاف حساب المالك" }, 400);
        const active = body?.active === true;
        const { error: e1 } = await admin.from("profiles").update({ is_active: active }).eq("id", userId);
        if (e1) return json({ error: e1.message }, 400);
        // الحساب الموقوف لا يستطيع تسجيل الدخول
        const { error: e2 } = await admin.auth.admin.updateUserById(userId, { ban_duration: active ? "none" : "876000h" });
        if (e2) return json({ error: e2.message }, 400);
        return json({ ok: true });
      }

      case "delete": {
        if (isSelf || target.role === "owner") return json({ error: "لا يمكن حذف حساب المالك" }, 400);
        const transferTo = String(body?.transfer_to ?? "");
        if (!transferTo || transferTo === userId) return json({ error: "اختر عضوًا تنتقل إليه أعماله" }, 400);
        const { error: e1 } = await admin.rpc("transfer_member_work", { p_from: userId, p_to: transferTo });
        if (e1) return json({ error: `تعذّر نقل الأعمال: ${e1.message}` }, 400);
        const { error: e2 } = await admin.auth.admin.deleteUser(userId);
        if (e2) return json({ error: `تعذّر حذف الحساب: ${e2.message}` }, 400);
        return json({ ok: true });
      }

      default:
        return json({ error: "إجراء غير معروف" }, 400);
    }
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
