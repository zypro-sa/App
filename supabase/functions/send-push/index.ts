// إرسال الإشعار لأجهزة العضو (Web Push) — تُنشر باسم: send-push
//
// يستدعيها Database Webhook عند إضافة صف في جدول notifications:
//   { "type": "INSERT", "table": "notifications", "record": { ... } }
//
// المتغيرات السرية المطلوبة (Edge Functions › Secrets):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (مثال: mailto:info@zypro.sa)
// ومتاح تلقائيًا: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "jsr:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const APP_BASE = Deno.env.get("APP_BASE_URL") ?? "https://zypro-sa.github.io/App/";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const n = payload?.record;
    if (!n?.user_id) return json({ skipped: "no record" });

    webpush.setVapidDetails(
      Deno.env.get("VAPID_SUBJECT") ?? "mailto:info@zypro.sa",
      Deno.env.get("VAPID_PUBLIC_KEY")!,
      Deno.env.get("VAPID_PRIVATE_KEY")!,
    );

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    const { data: subs, error } = await admin
      .from("push_subscriptions")
      .select("id, endpoint, p256dh, auth")
      .eq("user_id", n.user_id);
    if (error) return json({ error: error.message }, 500);
    if (!subs?.length) return json({ sent: 0, reason: "no devices" });

    // الرابط داخل التطبيق (التوجيه بعلامة #)
    const url = APP_BASE + "#" + (n.url ?? "/home");
    const message = JSON.stringify({
      title: n.title ?? "Zypro",
      body: n.body ?? "",
      url,
      tag: `${n.type}-${n.related_id ?? n.id}`,
    });

    let sent = 0;
    for (const s of subs) {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          message,
          { TTL: 60 * 60 * 24, urgency: n.type === "meeting_soon" ? "high" : "normal" },
        );
        sent++;
        await admin.from("push_subscriptions").update({ last_used_at: new Date().toISOString() }).eq("id", s.id);
      } catch (e) {
        const code = (e as { statusCode?: number }).statusCode;
        // الجهاز ألغى الاشتراك أو انتهى: نحذفه
        if (code === 404 || code === 410) {
          await admin.from("push_subscriptions").delete().eq("id", s.id);
        } else {
          console.error("push failed", code, (e as Error).message);
        }
      }
    }
    return json({ sent, devices: subs.length });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
