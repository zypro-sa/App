// مزامنة البيانات من دفترة إلى التطبيق (قراءة فقط من دفترة).
// تُنشر على Supabase باسم: daftra-sync
//
// الأسرار المطلوبة (Edge Functions ← Secrets):
//   DAFTRA_API_KEY     مفتاح API من دفترة (الإعدادات ← API)
//   DAFTRA_SUBDOMAIN   اسم حسابك في رابط دفترة، مثل: zypro  (أو zypro.daftra.com)
//
// الطلب (POST, JSON):
//   { dry_run?: boolean, auto?: boolean }
//   - dry_run: يقرأ من دفترة ويعرض ما سيتغير دون أي تعديل
//   - auto: مزامنة تلقائية عند فتح التطبيق (مرة كل ١٥ دقيقة كحد أقصى)
//
// ما يُزامن: العملاء، الفواتير، الدفعات، المرتجعات (من إجمالي المرتجع على الفاتورة)، عروض الأسعار.
// ما يبقى من التطبيق: ربط الفاتورة بطلب، الملاحظات، المتابعات، وكل أقسام العمل الأخرى.

import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

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

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

const num = (v: unknown) => {
  const n = typeof v === "number" ? v : parseFloat(String(v ?? "0"));
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : 0;
};
const day = (v: unknown) => {
  const s = String(v ?? "").slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : null;
};
const addDays = (d: string, n: number) => {
  const t = new Date(d + "T00:00:00Z");
  t.setUTCDate(t.getUTCDate() + n);
  return t.toISOString().slice(0, 10);
};
const isDraft = (r: Row) =>
  r.draft === true || r.draft === 1 || r.draft === "1" || String(r.payment_status ?? "") === "-1";
const method = (m: unknown) => {
  const s = String(m ?? "").toLowerCase();
  if (s.includes("cash") || s.includes("نقد")) return "cash";
  if (s.includes("cheque") || s.includes("check") || s.includes("شيك")) return "cheque";
  if (s.includes("bank") || s.includes("transfer") || s.includes("تحويل")) return "bank_transfer";
  return "other";
};

function daftraBase() {
  const raw = (Deno.env.get("DAFTRA_SUBDOMAIN") ?? "").trim()
    .replace(/^https?:\/\//, "").replace(/\/.*$/, "");
  if (!raw) throw new Error("أضف السر DAFTRA_SUBDOMAIN في Supabase");
  const host = raw.includes(".") ? raw : `${raw}.daftra.com`;
  return `https://${host}/api2`;
}

async function fetchAll(path: string, wrapper: string, extra: Record<string, string> = {}) {
  const key = Deno.env.get("DAFTRA_API_KEY");
  if (!key) throw new Error("أضف السر DAFTRA_API_KEY في Supabase");
  const base = daftraBase();
  const out: Row[] = [];
  for (let page = 1; page <= 200; page++) {
    const url = new URL(`${base}/${path}.json`);
    url.searchParams.set("page", String(page));
    url.searchParams.set("limit", "100");
    for (const [k, v] of Object.entries(extra)) url.searchParams.set(k, v);
    const res = await fetch(url, { headers: { apikey: key, Accept: "application/json" } });
    if (!res.ok) {
      const text = (await res.text()).slice(0, 300);
      if (res.status === 401 || res.status === 403) {
        throw new Error(`دفترة رفضت المفتاح (${res.status}). تأكد من DAFTRA_API_KEY وصلاحياته. ${text}`);
      }
      throw new Error(`دفترة ${path}: HTTP ${res.status} ${text}`);
    }
    const body = await res.json();
    const data: Row[] = Array.isArray(body?.data) ? body.data : [];
    for (const item of data) {
      const v = item && typeof item === "object" ? (item[wrapper] ?? Object.values(item)[0]) : null;
      if (v && typeof v === "object") out.push(v as Row);
    }
    const pageCount = Number(body?.pagination?.page_count ?? 1);
    if (data.length === 0 || page >= pageCount) break;
  }
  return out;
}

async function all(db: SupabaseClient, table: string, cols: string) {
  const out: Row[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await db.from(table).select(cols).range(from, from + 999);
    if (error) throw new Error(`${table}: ${error.message}`);
    out.push(...(data ?? []));
    if (!data || data.length < 1000) break;
  }
  return out;
}

async function sync(db: SupabaseClient, dry: boolean) {
  const r = {
    dry_run: dry,
    fetched: { clients: 0, invoices: 0, payments: 0, estimates: 0, refunds: 0 },
    clients: { created: 0, linked: 0 },
    invoices: { created: 0, updated: 0, removed: 0, skipped_drafts: 0, skipped_fully_returned: 0, skipped_no_client: 0 },
    payments: { added: 0, updated: 0, removed: 0, mismatched: [] as string[] },
    returns: { set: 0, removed: 0 },
    quotes: { created: 0, updated: 0, removed: 0 },
    fields: {} as Record<string, string[]>,
    warnings: [] as string[],
    details: [] as string[],
  };
  let fake = 0;
  const newId = () => `dry-${++fake}`;
  const write = async (p: PromiseLike<{ error: { message: string } | null }>, what: string) => {
    if (dry) return;
    const { error } = await p;
    if (error) throw new Error(`${what}: ${error.message}`);
  };

  // ١. القراءة من دفترة
  let refundsOk = true;
  const softFetch = (path: string, wrapper: string, label: string) =>
    fetchAll(path, wrapper).catch((e) => {
      refundsOk = false;
      r.warnings.push(`${label}: ${e.message}`);
      return [] as Row[];
    });
  const [dClients, dInvoices, dPayments, dEstimates, dRefundReceipts, dCreditNotes] = await Promise.all([
    fetchAll("clients", "Client"),
    fetchAll("invoices", "Invoice"),
    fetchAll("invoice_payments", "InvoicePayment"),
    fetchAll("estimates", "Estimate").catch((e) => {
      r.warnings.push(`عروض الأسعار: ${e.message}`);
      return [] as Row[];
    }),
    softFetch("refund_receipts", "RefundReceipt", "إشعارات المرتجع"),
    softFetch("credit_notes", "CreditNote", "الإشعارات الدائنة"),
  ]);
  const dRefunds = [...dRefundReceipts, ...dCreditNotes].filter((x) => !isDraft(x));
  r.fetched = {
    clients: dClients.length, invoices: dInvoices.length, payments: dPayments.length,
    estimates: dEstimates.length, refunds: dRefunds.length,
  };

  // المرتجعات في دفترة مستندات مستقلة مرتبطة بالفاتورة الأصلية
  const invoiceIds = new Set(dInvoices.map((i) => String(i.id)));
  const invoiceIdByNo = new Map(dInvoices.map((i) => [String(i.no ?? ""), String(i.id)]));
  const invoiceNoById = new Map(dInvoices.map((i) => [String(i.id), String(i.no ?? i.id)]));
  const refundByInvoice = new Map<string, number>();
  let unlinked = 0;
  for (const x of dRefunds) {
    const candidates = [x.subscription_id, x.source_id, x.invoice_id, x.parent_invoice_id, x.related_invoice_id]
      .map((v) => String(v ?? "")).filter((v) => v && v !== "0");
    let parent = candidates.find((v) => invoiceIds.has(v));
    let via = parent ? Object.keys(x).find((k) => String(x[k]) === parent && /id/i.test(k)) ?? "id" : "";
    if (!parent) {
      via = "text";
      // أحيانًا يُذكر رقم الفاتورة الأصلية في الملاحظات أو الحقول النصية
      const text = `${x.notes ?? ""} ${x.po_number ?? ""} ${x.name ?? ""}`;
      for (const [no, id] of invoiceIdByNo) if (no && text.includes(no)) { parent = id; break; }
    }
    if (!parent) {
      unlinked++;
      r.details.push(`مرتجع ${x.no ?? x.id} (${num(x.summary_total)}): بلا فاتورة`);
      continue;
    }
    r.details.push(`مرتجع ${x.no ?? x.id} (${num(x.summary_total)}) ← فاتورة ${invoiceNoById.get(parent)} [${via}]`);
    refundByInvoice.set(parent, num((refundByInvoice.get(parent) ?? 0) + num(x.summary_total)));
  }
  if (unlinked > 0) {
    refundsOk = false;
    const k = Object.keys(dRefunds[0] ?? {}).filter((f) => /id|no|source|subscription|invoice/i.test(f)).join(", ");
    r.warnings.push(`${unlinked} مرتجع لم يُعرف لأي فاتورة (الحقول: ${k}) — لن تُحذف المرتجعات الموجودة`);
  }
  const keys = (rows: Row[]) => (rows[0] ? Object.keys(rows[0]).filter((k) => typeof rows[0][k] !== "object" || rows[0][k] === null) : []);
  r.fields = {
    client: keys(dClients), invoice: keys(dInvoices), payment: keys(dPayments),
    estimate: keys(dEstimates), refund: keys(dRefunds),
  };

  // ٢. العملاء
  const lClients = await all(db, "clients", "id, name, custom, daftra_id");
  const clientByDaftra = new Map<string, string>();
  for (const c of lClients) if (c.daftra_id) clientByDaftra.set(String(c.daftra_id), c.id);
  for (const dc of dClients) {
    const did = String(dc.id);
    if (clientByDaftra.has(did)) continue;
    const no = String(dc.client_number ?? "").trim();
    const name = String(dc.business_name ?? "").trim() ||
      `${dc.first_name ?? ""} ${dc.last_name ?? ""}`.trim() || `Client ${no || did}`;
    const match = lClients.find((c) =>
      !c.daftra_id && ((no && c.custom?.daftra_client_no === no) ||
        String(c.name).trim().toLowerCase() === name.toLowerCase()));
    if (match) {
      match.daftra_id = dc.id;
      clientByDaftra.set(did, match.id);
      r.clients.linked++;
      await write(db.from("clients").update({
        daftra_id: dc.id,
        custom: { ...(match.custom ?? {}), daftra_client_no: no || undefined },
      }).eq("id", match.id), "ربط عميل");
    } else {
      r.clients.created++;
      if (dry) {
        clientByDaftra.set(did, newId());
      } else {
        const { data, error } = await db.from("clients").insert({
          name,
          type: "company",
          status: "active",
          city: dc.city || null,
          address: dc.address1 || null,
          vat_number: dc.bn1 || null,
          daftra_id: dc.id,
          custom: no ? { daftra_client_no: no } : {},
        }).select("id").single();
        if (error) throw new Error(`إضافة عميل ${name}: ${error.message}`);
        clientByDaftra.set(did, data.id);
      }
    }
  }

  // ٣. الفواتير والمرتجعات
  const lInvoices = await all(db, "invoices", "id, number, daftra_id, status, deleted_at, notes");
  const lReturns = await all(db, "invoice_returns", "id, invoice_id, amount, daftra_id, deleted_at");
  const invByDaftra = new Map<string, string>(); // دفترة ← محلي
  const invInfo = new Map<string, { number: string; paid: number }>();
  const seenInv = new Set<string>();
  const convertedEstimates = new Set<string>();

  for (const di of dInvoices) {
    if (isDraft(di)) { r.invoices.skipped_drafts++; continue; }
    const did = String(di.id);
    const st = String(di.source_type ?? "").toLowerCase();
    if (di.source_id && (st.includes("estimate") || st === "3")) convertedEstimates.add(String(di.source_id));

    const number = `DF-${String(di.no ?? did).trim()}`;
    const total = num(di.summary_total);
    const refund = Math.max(num(di.summary_refund), refundByInvoice.get(did) ?? 0);
    const paid = num(di.summary_paid);
    const fullyReturned = total > 0 && refund >= total - 0.01;
    const clientId = clientByDaftra.get(String(di.client_id ?? di.Client?.id ?? ""));
    const local = lInvoices.find((i) => String(i.daftra_id ?? "") === did) ??
      lInvoices.find((i) => i.number === number && !i.daftra_id);
    const issue = day(di.date) ?? new Date().toISOString().slice(0, 10);
    const due = day(di.due_date) ?? (Number(di.due_after) > 0 ? addDays(issue, Number(di.due_after)) : issue);

    if (!local && fullyReturned) { r.invoices.skipped_fully_returned++; continue; }
    if (!clientId) { r.invoices.skipped_no_client++; r.warnings.push(`الفاتورة ${number} بلا عميل معروف`); continue; }

    let localId: string;
    const fields = {
      number,
      client_id: clientId,
      total: Math.max(total, 0),
      currency: String(di.currency_code || "SAR").slice(0, 3),
      issue_date: issue,
      due_date: due,
      daftra_id: di.id,
    };
    if (local) {
      localId = local.id;
      r.invoices.updated++;
      const status = fullyReturned ? "void" : (local.status === "void" ? "issued" : undefined);
      await write(db.from("invoices").update({ ...fields, ...(status ? { status } : {}) }).eq("id", local.id), `تحديث ${number}`);
    } else {
      r.invoices.created++;
      if (dry) {
        localId = newId();
      } else {
        const { data, error } = await db.from("invoices")
          .insert({ ...fields, status: "issued", notes: di.notes ? String(di.notes).slice(0, 2000) : null })
          .select("id").single();
        if (error) throw new Error(`إضافة ${number}: ${error.message}`);
        localId = data.id;
      }
    }
    invByDaftra.set(did, localId);
    invInfo.set(did, { number, paid });
    seenInv.add(did);

    // المرتجع: سجل واحد بإجمالي المرتجع في دفترة
    const active = lReturns.filter((x) => x.invoice_id === localId && !x.deleted_at);
    const activeSum = num(active.reduce((s, x) => s + num(x.amount), 0));
    // لا نحذف مرتجعًا موجودًا إلا إذا عرفنا كل مرتجعات دفترة بثقة
    const shouldSync = Math.abs(activeSum - refund) > 0.01 && !fullyReturned && (refundsOk || refund > activeSum);
    if (shouldSync) {
      r.details.push(`فاتورة ${number}: المرتجع في التطبيق ${activeSum} ← في دفترة ${refund}`);
      for (const x of active) {
        r.returns.removed++;
        await write(db.from("invoice_returns").update({ deleted_at: new Date().toISOString() }).eq("id", x.id), "حذف مرتجع");
      }
      if (refund > 0) {
        r.returns.set++;
        await write(db.from("invoice_returns").insert({
          invoice_id: localId, amount: refund, returned_at: issue,
          reason: "مرتجع مسجّل في دفترة", daftra_id: di.id,
        }), `مرتجع ${number}`);
      }
    }
  }

  // الفواتير المحذوفة من دفترة تنتقل للسلة
  if (dInvoices.length > 0) {
    for (const i of lInvoices) {
      if (i.daftra_id && !i.deleted_at && !seenInv.has(String(i.daftra_id))) {
        r.invoices.removed++;
        await write(db.from("invoices").update({ deleted_at: new Date().toISOString() }).eq("id", i.id), `حذف ${i.number}`);
      }
    }
  }

  // ٤. الدفعات
  const lPayments = await all(db, "payments", "id, invoice_id, amount, daftra_id, deleted_at");
  const payByInvoice = new Map<string, Row[]>();
  for (const p of dPayments) {
    const k = String(p.invoice_id ?? "");
    if (!k) continue;
    payByInvoice.set(k, [...(payByInvoice.get(k) ?? []), p]);
  }
  for (const [did, localId] of invByDaftra) {
    const info = invInfo.get(did)!;
    const pays = (payByInvoice.get(did) ?? []).filter((p) => num(p.amount) > 0);
    const sum = (xs: Row[]) => num(xs.reduce((s, p) => s + num(p.amount), 0));
    const done = pays.filter((p) => String(p.status ?? "") === "1");
    let chosen = pays;
    if (Math.abs(sum(pays) - info.paid) > 0.01) {
      if (Math.abs(sum(done) - info.paid) <= 0.01) chosen = done;
      else {
        r.payments.mismatched.push(`${info.number}: دفترة ${info.paid} / الدفعات ${sum(pays)}`);
        if (pays.length === 0) continue; // لا نحذف دفعات محلية دون بديل
      }
    }
    const keep = new Set<string>();
    for (const p of chosen) {
      keep.add(String(p.id));
      const existing = lPayments.find((x) => String(x.daftra_id ?? "") === String(p.id));
      const row = {
        invoice_id: localId,
        amount: num(p.amount),
        paid_at: day(p.date) ?? new Date().toISOString().slice(0, 10),
        method: method(p.payment_method),
        daftra_id: p.id,
        deleted_at: null,
      };
      if (existing) {
        if (num(existing.amount) !== row.amount || existing.invoice_id !== localId || existing.deleted_at) {
          r.payments.updated++;
          await write(db.from("payments").update(row).eq("id", existing.id), `دفعة ${info.number}`);
        }
      } else {
        r.payments.added++;
        await write(db.from("payments").insert(row), `دفعة ${info.number}`);
      }
    }
    for (const x of lPayments) {
      if (x.invoice_id === localId && !x.deleted_at && !keep.has(String(x.daftra_id ?? ""))) {
        r.payments.removed++;
        await write(db.from("payments").update({ deleted_at: new Date().toISOString() }).eq("id", x.id), `حذف دفعة ${info.number}`);
      }
    }
  }

  // ٥. عروض الأسعار
  if (dEstimates.length > 0) {
    const lQuotes = await all(db, "quotes", "id, number, daftra_id, deleted_at");
    const seenQ = new Set<string>();
    const monthAgo = addDays(new Date().toISOString().slice(0, 10), -30);
    for (const de of dEstimates) {
      if (isDraft(de)) continue;
      const did = String(de.id);
      const clientId = clientByDaftra.get(String(de.client_id ?? de.Client?.id ?? ""));
      if (!clientId) continue;
      seenQ.add(did);
      const number = `DFQ-${String(de.no ?? did).trim()}`;
      const date = day(de.date) ?? new Date().toISOString().slice(0, 10);
      const status = convertedEstimates.has(did) ? "accepted" : (date < monthAgo ? "expired" : "sent");
      const fields = {
        number, client_id: clientId, amount: Math.max(num(de.summary_total), 0), vat_amount: 0,
        currency: String(de.currency_code || "SAR").slice(0, 3), status, sent_at: date, daftra_id: de.id,
      };
      const local = lQuotes.find((q) => String(q.daftra_id ?? "") === did) ?? lQuotes.find((q) => q.number === number);
      if (local) {
        r.quotes.updated++;
        await write(db.from("quotes").update(fields).eq("id", local.id), `عرض ${number}`);
      } else {
        r.quotes.created++;
        await write(db.from("quotes").insert({ ...fields, notes: de.notes ? String(de.notes).slice(0, 2000) : null }), `عرض ${number}`);
      }
    }
    for (const q of lQuotes) {
      if (q.daftra_id && !q.deleted_at && !seenQ.has(String(q.daftra_id))) {
        r.quotes.removed++;
        await write(db.from("quotes").update({ deleted_at: new Date().toISOString() }).eq("id", q.id), `حذف ${q.number}`);
      }
    }
  }

  return r;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  try {
    // من يطلب المزامنة؟
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: auth, error: authError } = await db.auth.getUser(token);
    if (authError || !auth.user) return json({ error: "يجب تسجيل الدخول" }, 401);
    const { data: me } = await db.from("profiles").select("role, is_active, permissions").eq("id", auth.user.id).single();
    if (!me?.is_active) return json({ error: "الحساب غير مفعّل" }, 403);

    const body = await req.json().catch(() => ({}));
    const dry = body?.dry_run === true;
    const auto = body?.auto === true;
    // نفس قاعدة has_perm('finance.manage'): المالك دائمًا، وغيره حسب التخصيص (الافتراضي لا)
    const canManage = me.role === "owner" || me.permissions?.["finance.manage"] === true;

    const { data: state } = await db.from("daftra_sync").select("*").eq("id", 1).single();
    const now = Date.now();
    if (auto) {
      if (!state?.enabled) return json({ skipped: "not_enabled" });
      if (state.last_run_at && now - Date.parse(state.last_run_at) < 15 * 60 * 1000) return json({ skipped: "recent" });
    } else if (!canManage) {
      return json({ error: "المزامنة اليدوية للمالك أو من لديه صلاحية المالية" }, 403);
    }
    if (state?.running_since && now - Date.parse(state.running_since) < 5 * 60 * 1000) {
      return json({ skipped: "running" });
    }

    if (!dry) {
      await db.from("daftra_sync").update({ running_since: new Date().toISOString(), last_run_at: new Date().toISOString() }).eq("id", 1);
    }
    try {
      const result = await sync(db, dry);
      if (!dry) {
        await db.from("daftra_sync").update({
          enabled: true, running_since: null, last_ok_at: new Date().toISOString(),
          last_result: result, last_error: null,
        }).eq("id", 1);
      }
      return json(result);
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      if (!dry) await db.from("daftra_sync").update({ running_since: null, last_error: message }).eq("id", 1);
      return json({ error: message }, 500);
    }
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
