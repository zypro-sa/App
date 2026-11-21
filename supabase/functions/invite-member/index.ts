// دعوة عضو جديد للفريق — للمالك فقط.
// تُنشر على Supabase باسم: invite-member
//
// الطلب (POST, JSON):
//   { email, name, role: "employee" | "manager", job_title?, redirect_to?, resend? }
//
// تستخدم مفتاح الخدمة المتاح تلقائيًا داخل Supabase Edge Functions،
// ولا يظهر هذا المفتاح أبدًا في التطبيق.

import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    // ١. التحقق من هوية من يرسل الدعوة
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: auth, error: authError } = await admin.auth.getUser(token);
    if (authError || !auth.user) return json({ error: "يجب تسجيل الدخول" }, 401);

    const { data: me, error: meError } = await admin
      .from("profiles")
      .select("role, is_active")
      .eq("id", auth.user.id)
      .single();
    if (meError) return json({ error: `تعذّر قراءة الملف الشخصي: ${meError.message}` }, 500);
    if (!me || !me.is_active) return json({ error: "الحساب غير مفعّل" }, 403);
    if (me.role !== "owner") {
      const { data: allowed } = await admin.rpc("perm_of", { p_user: auth.user.id, p: "team.add" });
      if (allowed !== true) return json({ error: "ليست لديك صلاحية إضافة الأعضاء" }, 403);
    }

    // ٢. التحقق من البيانات
    const body = await req.json();
    const email = String(body.email ?? "").trim().toLowerCase();
    const name = String(body.name ?? "").trim();
    const role = String(body.role ?? "employee");
    const jobTitle = body.job_title ? String(body.job_title).trim() : null;
    const redirectTo = body.redirect_to ? String(body.redirect_to) : undefined;

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "البريد غير صحيح" }, 400);
    if (!name) return json({ error: "الاسم مطلوب" }, 400);
    if (!["employee", "manager"].includes(role)) return json({ error: "الدور غير صحيح" }, 400);

    // ٣. إرسال الدعوة (أو إعادة إرسالها)
    const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
      data: { name, needs_password: true },
      redirectTo,
    });

    let userId = invited?.user?.id;

    if (inviteError) {
      const already = /already|registered|exists/i.test(inviteError.message);
      if (!already) return json({ error: inviteError.message }, 400);

      // مسجّل مسبقًا: إن لم يدخل بعد، نرسل له رابط تعيين كلمة المرور
      const { data: existing } = await admin.from("profiles").select("id").eq("email", email).maybeSingle();
      if (!existing) return json({ error: "البريد مسجّل مسبقًا" }, 409);
      userId = existing.id;
      const { data: u } = await admin.auth.admin.getUserById(existing.id);
      if (u?.user?.last_sign_in_at && !body.resend) {
        return json({ error: "هذا العضو مسجّل ويستخدم التطبيق بالفعل" }, 409);
      }
      await admin.auth.admin.updateUserById(existing.id, {
        user_metadata: { ...(u?.user?.user_metadata ?? {}), name, needs_password: true },
      });
      const { error: resetError } = await admin.auth.resetPasswordForEmail(email, { redirectTo });
      if (resetError) return json({ error: resetError.message }, 400);
    }

    // ٤. ضبط الاسم والدور والمسمى
    if (userId) {
      const { error: profileError } = await admin
        .from("profiles")
        .update({ name, role, job_title: jobTitle, is_active: true })
        .eq("id", userId);
      if (profileError) return json({ error: profileError.message }, 400);
    }

    return json({ ok: true, user_id: userId });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
