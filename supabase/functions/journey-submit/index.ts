// The Journey → Planning Center.
//
// The app POSTs one level's answers here when a participant finishes it.
// This function turns them into a submission of that level's existing
// Planning Center form (People → Forms), exactly as if the person had
// filled the form in on Church Center.
//
// Secrets (Supabase → Edge Functions → Secrets). Never put them in the app or repo:
//   PCO_APP_ID, PCO_SECRET   Planning Center Personal Access Token
//
// Actions (POST JSON):
//   { action: "submit",  level, lang, me, answers }  → creates the form submission
//   { action: "preview", level, lang, me, answers }  → builds it but does NOT send (for testing)
//   { action: "inspect", level }                     → lists the form's fields, types and options

const PCO = "https://api.planningcenteronline.com/people/v2";

// Planning Center form for each level.
const FORMS: Record<number, string> = { 1: "480411", 2: "494110", 3: "494099", 4: "494115" };

// Where the app is allowed to call from.
const ORIGINS = [
  "https://kendallturcios-sketch.github.io",
  "http://localhost:5173",
];

// ---------- mapping: app answers → form fields --------------------
// Fields are found by type or by words in their label, so small wording
// edits in Planning Center don't break anything. Option labels are
// matched the same way (case, spaces and punctuation ignored).

const GIFT_LABEL: Record<string, string> = {
  administration: "administration", exhortation: "exhortation", evangelism: "evangelism",
  giving: "giving", mercy_showing: "mercy", prophecy: "prophecy", serving: "serving",
  shepherding: "shepherding", teaching: "teaching",
};
// Same order as MIN in the app (identical in English and Spanish).
const MINISTRY_LABEL = [
  "next steps", "hospitality", "worship", "student ministry", "children",
  "life groups", "production", "creative", "behind the scenes",
];
const UNSURE_LABEL = "not sure";
const BAPTISM_LABEL: Record<string, string> = { yes: "yes", talk: "i have questions", not: "not yet" };
const LIFEGROUP_HELP_LABEL = "help finding";

type Me = { first: string; last: string; email: string; phone: string };
type Answers = {
  fb?: string[];                    // feedback answers, in form order
  about?: Record<string, string>;   // Level 1: bday, gender, marital, street, apt, city, state, zip, country, found
  baptism?: "yes" | "talk" | "not" | null;
  lgHelp?: boolean;
  gifts?: string[];                 // app gift keys
  ministries?: number[];            // indexes into MINISTRY_LABEL
  unsure?: boolean;
  roles?: string[];
  signed?: boolean;
};

type Field = { id: string; label: string; type: string; options: { id: string; label: string }[] };

// One entry per answer we want to send: which field, and what to put in it.
type Want =
  | { find: (f: Field) => boolean; what: string; text: string }
  | { find: (f: Field) => boolean; what: string; options: string[] }
  | { find: (f: Field) => boolean; what: string; bool: true }
  | { find: (f: Field) => boolean; what: string; address: Record<string, string> }
  | { find: (f: Field) => boolean; what: string; date: string };

const norm = (s: string) => (s || "").toLowerCase().replace(/[^a-z0-9]/g, "");
const has = (label: string, ...words: string[]) => words.every((w) => norm(label).includes(norm(w)));
const byType = (...types: string[]) => (f: Field) => types.includes(f.type);
const byLabel = (...words: string[]) => (f: Field) => has(f.label, ...words);

function wants(level: number, me: Me, a: Answers): Want[] {
  const w: Want[] = [];
  const fb = a.fb || [];
  w.push({ find: byType("phone_number"), what: "phone", text: me.phone });
  if (fb[0]) w.push({ find: byLabel("most interesting"), what: "feedback 1", text: fb[0] });
  if (fb[1]) w.push({ find: byLabel("looking forward"), what: "feedback 2", text: fb[1] });

  if (level === 1) {
    const ab = a.about || {};
    w.push({ find: byType("birthday"), what: "birthday", date: ab.bday });
    w.push({ find: byType("gender"), what: "gender", options: [ab.gender] });
    w.push({ find: byType("marital_status"), what: "marital status", options: [ab.marital] });
    w.push({
      find: byType("address"), what: "address",
      address: { street: ab.street, apt: ab.apt, city: ab.city, state: ab.state, zip: ab.zip, country: ab.country },
    });
    w.push({ find: byLabel("how did you", "arise"), what: "how they found ARISE", options: [ab.found] });
    if (a.baptism) w.push({ find: byLabel("next step"), what: "baptism", options: [BAPTISM_LABEL[a.baptism]] });
  }
  if (level === 2 && a.lgHelp) {
    w.push({ find: byLabel("next step"), what: "life group help", options: [LIFEGROUP_HELP_LABEL] });
  }
  if (level === 3) {
    w.push({ find: byLabel("spiritual gifts"), what: "gifts", options: (a.gifts || []).map((g) => GIFT_LABEL[g]) });
  }
  if (level === 4) {
    const picks = (a.ministries || []).map((i) => MINISTRY_LABEL[i]).filter(Boolean);
    if (a.unsure) picks.push(UNSURE_LABEL);
    if (picks.length) w.push({ find: byLabel("ministry"), what: "ministries", options: picks });
    if (a.roles?.length) w.push({ find: byLabel("role"), what: "roles", text: a.roles.join(", ") });
    if (a.signed) w.push({ find: byLabel("covenant"), what: "covenant signed", bool: true });
  }
  return w;
}

// ---------- how each kind of answer is written ----------------------
// Planning Center's docs don't spell out every value shape yet, so they
// all live here. Adjust after the first test submission if needed.
function encode(field: Field, want: Want): unknown[] {
  if ("text" in want) {
    if (!want.text) return [];
    // Phone fields want a number and a location, like a profile phone number.
    return field.type === "phone_number" ? [{ number: want.text, location: "Mobile" }] : [want.text];
  }
  if ("date" in want) return want.date ? [want.date] : [];            // YYYY-MM-DD
  if ("address" in want) {
    const d = want.address;
    if (!d.street) return [];
    // Planning Center takes a 2-letter country_code (country_name is read-only).
    const cc = countryCode(d.country);
    // Form addresses read the street from `street` (street_line_1 alone is ignored).
    return [{
      street: d.apt ? `${d.street}\n${d.apt}` : d.street, street_line_1: d.street, street_line_2: d.apt || "", city: d.city,
      state: d.state, zip: d.zip, ...(cc ? { country_code: cc } : {}), location: "Home",
    }];
  }
  if ("bool" in want) {
    // A single checkbox may be modelled with one option, or as a plain boolean.
    return field.options.length ? [field.options[0].id] : [true];
  }
  // Checkbox / dropdown answers: Planning Center wants option IDs, one value per selection.
  // (Gender and marital status get their options from the church's lists in formFields.)
  if (!field.options.length) return want.options.filter(Boolean);
  return want.options.filter(Boolean).map((label) => {
    const o = field.options.find((o) => norm(o.label).startsWith(norm(label)))
      ?? field.options.find((o) => norm(o.label).includes(norm(label)));
    if (!o) throw new Problem(`"${field.label}" has no option matching "${label}"`);
    return o.id;
  });
}

// The app's country box is free text (English or Spanish). Unknown names send no code.
const COUNTRY: Record<string, string> = {
  unitedstates: "US", unitedstatesofamerica: "US", usa: "US", us: "US", estadosunidos: "US", eeuu: "US", eua: "US",
  cuba: "CU", venezuela: "VE", colombia: "CO", mexico: "MX", "méxico": "MX", honduras: "HN", nicaragua: "NI",
  guatemala: "GT", elsalvador: "SV", costarica: "CR", panama: "PA", "panamá": "PA", dominicanrepublic: "DO",
  republicadominicana: "DO", "repúblicadominicana": "DO", puertorico: "PR", haiti: "HT", "haití": "HT",
  jamaica: "JM", peru: "PE", "perú": "PE", ecuador: "EC", argentina: "AR", chile: "CL", bolivia: "BO",
  paraguay: "PY", uruguay: "UY", brazil: "BR", brasil: "BR", canada: "CA", "canadá": "CA", spain: "ES", "españa": "ES",
};
function countryCode(name?: string): string {
  const t = (name || "United States").trim();
  if (/^[A-Za-z]{2}$/.test(t)) return t.toUpperCase();
  return COUNTRY[t.toLowerCase().replace(/[^a-záéíóúñ]/g, "")] || "";
}

// ---------- Planning Center access ------------------------------------
class Problem extends Error {}

function auth() {
  const id = Deno.env.get("PCO_APP_ID"), secret = Deno.env.get("PCO_SECRET");
  if (!id || !secret) throw new Problem("Planning Center key is not set up yet (PCO_APP_ID / PCO_SECRET).");
  return "Basic " + btoa(`${id}:${secret}`);
}

async function pco(path: string, init: RequestInit = {}) {
  const r = await fetch(PCO + path, {
    ...init,
    // Form submissions by API exist only from this People API version on.
    headers: { Authorization: auth(), "Content-Type": "application/json", "X-PCO-API-Version": "2026-06-04", ...(init.headers || {}) },
  });
  const body = await r.text();
  if (!r.ok) throw new Problem(`Planning Center ${r.status}: ${body.slice(0, 3000)}`);
  return body ? JSON.parse(body) : {};
}

const fieldCache = new Map<string, { at: number; fields: Field[] }>();
async function formFields(formId: string): Promise<Field[]> {
  const hit = fieldCache.get(formId);
  if (hit && Date.now() - hit.at < 10 * 60_000) return hit.fields;
  const j = await pco(`/forms/${formId}/fields?per_page=100&order=sequence`);
  const fields: Field[] = await Promise.all(j.data.map(async (d: any) => {
    const f: Field = { id: d.id, label: d.attributes.label || "", type: d.attributes.field_type, options: [] };
    if (!["string", "text", "heading", "note", "number", "file"].includes(f.type)) {
      const o = await pco(`/forms/${formId}/fields/${d.id}/options?per_page=100`);
      f.options = o.data.map((x: any) => ({ id: x.id, label: x.attributes.label || "" }));
    }
    // Gender and marital status use the church's own lists, answered by ID.
    const list = { gender: "/genders", marital_status: "/marital_statuses" }[f.type];
    if (list && !f.options.length) {
      const o = await pco(`${list}?per_page=100`);
      f.options = o.data.map((x: any) => ({ id: x.id, label: x.attributes.value || "" }));
    }
    return f;
  }));
  fieldCache.set(formId, { at: Date.now(), fields });
  return fields;
}

async function build(level: number, me: Me, a: Answers) {
  const fields = await formFields(FORMS[level]);
  const values: { form_field_id: string; value: unknown; _what: string }[] = [];
  for (const want of wants(level, me, a)) {
    const f = fields.find(want.find);
    if (!f) throw new Problem(`Level ${level} form has no field for ${want.what}`);
    for (const v of encode(f, want)) values.push({ form_field_id: f.id, value: v, _what: want.what });
  }
  return {
    data: {
      type: "FormSubmission",
      attributes: {
        person_attributes: {
          first_name: me.first, last_name: me.last,
          emails_attributes: [{ location: "Home", address: me.email }],
        },
      },
    },
    included: values.map(({ form_field_id, value }) => ({
      type: "FormSubmissionValue", attributes: { form_field_id, value },
    })),
    _summary: values.map((v) => `${v._what} → field ${v.form_field_id}: ${JSON.stringify(v.value)}`),
  };
}

// ---------- request checks ---------------------------------------------
function checkMe(me: any): Me {
  const s = (x: unknown, max = 200) => (typeof x === "string" ? x.trim().slice(0, max) : "");
  const m = { first: s(me?.first, 80), last: s(me?.last, 80), email: s(me?.email, 200), phone: s(me?.phone, 40) };
  if (!m.first || !m.last) throw new Problem("Missing name");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(m.email)) throw new Problem("Invalid email");
  if (m.phone.replace(/\D/g, "").length < 10) throw new Problem("Invalid phone");
  return m;
}
function checkAnswers(a: any): Answers {
  const txt = (x: unknown) => (typeof x === "string" ? x.slice(0, 4000) : "");
  a = a && typeof a === "object" ? a : {};
  return {
    fb: Array.isArray(a.fb) ? a.fb.slice(0, 2).map(txt) : [],
    about: a.about && typeof a.about === "object"
      ? Object.fromEntries(Object.entries(a.about).map(([k, v]) => [k, txt(v).slice(0, 200)])) : {},
    baptism: ["yes", "talk", "not"].includes(a.baptism) ? a.baptism : null,
    lgHelp: a.lgHelp === true,
    gifts: Array.isArray(a.gifts) ? a.gifts.filter((g: string) => g in GIFT_LABEL).slice(0, 3) : [],
    ministries: Array.isArray(a.ministries)
      ? a.ministries.filter((i: number) => Number.isInteger(i) && i >= 0 && i < MINISTRY_LABEL.length) : [],
    unsure: a.unsure === true,
    roles: Array.isArray(a.roles) ? a.roles.map(txt).map((r: string) => r.slice(0, 80)).slice(0, 20) : [],
    signed: a.signed === true,
  };
}

// ---------- HTTP -----------------------------------------------------------
function cors(req: Request) {
  const o = req.headers.get("origin") || "";
  return {
    "Access-Control-Allow-Origin": ORIGINS.includes(o) ? o : ORIGINS[0],
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, authorization, apikey, x-client-info",
    "Vary": "Origin",
  };
}

// ---------- admin checks (need the ADMIN_KEY secret in an x-admin-key header) ----------
// Leaders live in the JOURNEY_LEADERS secret, not the repo:
//   {"next steps":["First Last"], "hospitality":["First Last","First Last"], ...}
// Keys are MINISTRY_LABEL entries plus "life groups" (also the Life Groups leader).
function leaders(): Record<string, string[]> {
  try { return JSON.parse(Deno.env.get("JOURNEY_LEADERS") || "{}"); } catch { return {}; }
}

async function findPerson(name: string) {
  const j = await pco(`/people?where[search_name]=${encodeURIComponent(name)}&include=emails,phone_numbers&per_page=10`);
  const inc = j.included || [];
  return (j.data || []).map((p: any) => {
    const mine = (type: string) => inc.filter((x: any) => x.type === type &&
      (p.relationships?.[type === "Email" ? "emails" : "phone_numbers"]?.data || []).some((r: any) => r.id === x.id));
    const phones = mine("PhoneNumber");
    return {
      id: p.id,
      has_email: mine("Email").length > 0,
      has_mobile: phones.some((x: any) => /mobile/i.test(x.attributes.location || "")),
      has_phone: phones.length > 0,
    };
  });
}

// ---------- leader alerts: a follow-up card + a text per request ----------
// ALERTS secret: "off" (default) | "test" | "live".
//   test: cards go to the workflow step's default assignee (the owner) and every
//         text goes to that person's mobile, marked [TEST → leader name].
//   live: cards are assigned to the ministry's leaders and texts go to them.
const FOLLOWUP_WORKFLOW = "785600";   // PCO People → Workflows → "The Journey - Follow Up"
const DONE_PAGE = "https://kendallturcios-sketch.github.io/the-journey/done.html";
const MINISTRY_NAME: Record<string, string> = {
  "next steps": "Next Steps", hospitality: "Hospitality", worship: "Worship",
  "student ministry": "Student Ministry", children: "Children's Ministry / Seekers", "life groups": "Life Groups",
  production: "Production", creative: "Creative and Social", "behind the scenes": "Behind the Scenes",
};
const alertsMode = () => (Deno.env.get("ALERTS") || "off").trim().toLowerCase();

type Contact = { id: string; name: string; phone: string };
async function contactById(id: string): Promise<Contact> {
  const j = await pco(`/people/${id}?include=phone_numbers`);
  const phones = (j.included || []).filter((x: any) => x.type === "PhoneNumber");
  const m = phones.find((x: any) => /mobile/i.test(x.attributes.location || "")) || phones[0];
  return {
    id, name: `${j.data.attributes.first_name} ${j.data.attributes.last_name}`,
    phone: m ? (m.attributes.e164 || m.attributes.number || "") : "",
  };
}
async function contactByName(name: string): Promise<Contact | null> {
  const j = await pco(`/people?where[search_name]=${encodeURIComponent(name)}&per_page=2`);
  return (j.data || []).length === 1 ? contactById(j.data[0].id) : null;
}
async function defaultAssignee(): Promise<string> {
  const j = await pco(`/workflows/${FOLLOWUP_WORKFLOW}/steps?order=sequence`);
  return String(j.data?.[0]?.attributes?.default_assignee_id || "");
}

// What each finished level asks the leaders to follow up on.
function followups(level: number, a: Answers): { ministry: string; what: string }[] {
  if (level === 2 && a.lgHelp) return [{ ministry: "life groups", what: "asked for help finding a Life Group" }];
  if (level !== 4) return [];
  const roles = a.roles?.length ? ` (roles: ${a.roles.join(", ")})` : "";
  const out = (a.ministries || []).map((i) => MINISTRY_LABEL[i]).filter(Boolean)
    .map((m) => ({ ministry: m, what: `wants to serve in ${MINISTRY_NAME[m] || m}${roles}` }));
  if (a.unsure && !out.some((f) => f.ministry === "next steps")) {
    out.push({ ministry: "next steps", what: "wants to serve but isn't sure where yet" });
  }
  return out;
}

async function sign(text: string) {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(Deno.env.get("ADMIN_KEY") || ""),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const s = new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(text)));
  return [...s.slice(0, 12)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

let twilioFrom = "";
async function sendText(to: string, body: string): Promise<string> {
  const sid = Deno.env.get("TWILIO_ACCOUNT_SID"), tok = Deno.env.get("TWILIO_AUTH_TOKEN");
  if (!sid || !tok || !to) return "skipped (no Twilio or no number)";
  const auth = "Basic " + btoa(`${sid}:${tok}`);
  if (!twilioFrom) {
    const n = await (await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/IncomingPhoneNumbers.json`,
      { headers: { Authorization: auth } })).json();
    twilioFrom = (n.incoming_phone_numbers || []).find((x: any) => x.capabilities?.sms)?.phone_number || "";
  }
  if (!twilioFrom) return "skipped (no Twilio number yet)";
  const r = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
    method: "POST", headers: { Authorization: auth, "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ To: to, From: twilioFrom, Body: body }),
  });
  const j = await r.json().catch(() => ({}));
  return r.ok ? `sent ${j.sid}` : `failed: ${j.message || r.status}`;
}

async function alertLeaders(level: number, me: Me, a: Answers, personId: string | null) {
  const mode = alertsMode();
  const todo = followups(level, a);
  if (mode === "off" || !personId || !todo.length) return [];
  const owner = mode === "live" ? null : await contactById(await defaultAssignee());
  const log: string[] = [];
  for (const f of todo) {
    const leads = (await Promise.all((leaders()[f.ministry] || []).map(contactByName))).filter(Boolean) as Contact[];
    // One card per leader (Hospitality has two). No leader found → one card for the default assignee.
    const targets: (Contact | null)[] = leads.length ? leads : [null];
    const cards: string[] = [];
    for (const l of targets) {
      const attrs = mode === "live" && l ? { assignee_id: l.id } : {};
      const c = await pco(`/workflows/${FOLLOWUP_WORKFLOW}/cards`, {
        method: "POST",
        body: JSON.stringify({ data: { type: "WorkflowCard", attributes: { person_id: personId, ...attrs } } }),
      });
      cards.push(c.data.id);
    }
    const ids = cards.join(",");
    const link = `${DONE_PAGE}?p=${personId}&c=${ids}&s=${await sign(`${personId}:${ids}`)}`;
    const msg = `The Journey: ${me.first} ${me.last} ${f.what}. Please reach out within 3 days: ${me.phone} · ${me.email}. ` +
      `When you have, tap: ${link}`;
    for (const l of leads) {
      const res = owner
        ? await sendText(owner.phone, `[TEST → ${l.name}] ${msg}`)
        : await sendText(l.phone, msg);
      log.push(`${f.ministry} → ${l.name}: card ${ids}, text ${res}`);
    }
    if (!leads.length) log.push(`${f.ministry}: no leader found, card ${ids} for the default assignee`);
  }
  return log;
}

// A leader tapped "I reached out": complete that request's card(s).
async function markDone(p: string, c: string, s: string) {
  if (!/^\d+$/.test(p) || !/^\d+(,\d+)*$/.test(c) || s !== await sign(`${p}:${c}`)) throw new Problem("This link isn't valid.");
  let already = true;
  for (const id of c.split(",")) {
    const card = await pco(`/people/${p}/workflow_cards/${id}`);
    if (card.data.attributes.completed_at || card.data.attributes.removed_at) continue;
    already = false;
    await pco(`/people/${p}/workflow_cards/${id}/promote`, { method: "POST" });
  }
  const person = await pco(`/people/${p}`);
  return { ok: true, already, first_name: person.data.attributes.first_name };
}

async function admin(req: Request, body: any) {
  const key = Deno.env.get("ADMIN_KEY");
  if (!key || req.headers.get("x-admin-key") !== key) throw new Problem("not allowed");

  if (body.action === "admin_leaders") {
    const out: Record<string, unknown>[] = [];
    for (const [ministry, names] of Object.entries(leaders())) {
      for (const name of names) {
        const matches = await findPerson(name);
        out.push({ ministry, name, matches: matches.length, people: matches });
      }
    }
    return { ok: true, leaders: out };
  }

  if (body.action === "admin_twilio") {
    const sid = Deno.env.get("TWILIO_ACCOUNT_SID"), tok = Deno.env.get("TWILIO_AUTH_TOKEN");
    if (!sid || !tok) throw new Problem("Twilio secrets are not set");
    const a = "Basic " + btoa(`${sid}:${tok}`);
    const acct = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}.json`, { headers: { Authorization: a } });
    if (!acct.ok) throw new Problem(`Twilio ${acct.status}: credentials not accepted`);
    const aj = await acct.json();
    const nums = await (await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/IncomingPhoneNumbers.json`,
      { headers: { Authorization: a } })).json();
    const verified = await (await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/OutgoingCallerIds.json`,
      { headers: { Authorization: a } })).json();
    return {
      ok: true, status: aj.status, type: aj.type,
      phone_numbers: (nums.incoming_phone_numbers || []).map((n: any) => ({ number: n.phone_number, sms: n.capabilities?.sms })),
      verified_numbers: (verified.outgoing_caller_ids || []).length,
    };
  }
  if (body.action === "admin_alert_test") {
    // Run the leader alerts for an existing person without submitting a form.
    const level = Number(body.level);
    return { ok: true, mode: alertsMode(), log: await alertLeaders(level, checkMe(body.me), checkAnswers(body.answers), String(body.person)) };
  }
  if (body.action === "admin_link") {
    // Build a done link for existing cards (for testing the page).
    const ids = String(body.cards);
    return { ok: true, link: `${DONE_PAGE}?p=${body.person}&c=${ids}&s=${await sign(`${body.person}:${ids}`)}` };
  }

  if (body.action === "admin_workflows") {
    const j = await pco(`/workflows?per_page=100&include=steps`);
    const inc = j.included || [];
    return {
      ok: true,
      workflows: (j.data || []).filter((w: any) => /journey/i.test(w.attributes.name || "")).map((w: any) => ({
        id: w.id, name: w.attributes.name, attributes: w.attributes,
        steps: (w.relationships?.steps?.data || []).map((r: any) => {
          const s = inc.find((x: any) => x.type === "WorkflowStep" && x.id === r.id);
          return { id: r.id, ...(s?.attributes || {}) };
        }),
      })),
    };
  }
  throw new Problem("unknown admin action");
}

Deno.serve(async (req) => {
  const h = { ...cors(req), "Content-Type": "application/json" };
  if (req.method === "OPTIONS") return new Response(null, { headers: h });
  if (req.method !== "POST") return new Response(JSON.stringify({ ok: false, error: "POST only" }), { status: 405, headers: h });
  try {
    const body = await req.json().catch(() => ({}));
    if (String(body.action || "").startsWith("admin_")) {
      return new Response(JSON.stringify(await admin(req, body), null, 2), { headers: h });
    }
    if (body.action === "done") {
      return new Response(JSON.stringify(await markDone(String(body.p || ""), String(body.c || ""), String(body.s || ""))), { headers: h });
    }
    const level = Number(body.level);
    if (!FORMS[level]) throw new Problem("level must be 1-4");

    if (body.action === "inspect") {
      const fields = await formFields(FORMS[level]);
      return new Response(JSON.stringify({ ok: true, form: FORMS[level], fields }, null, 2), { headers: h });
    }

    // Diagnostics: the form's name/status and, for one submission, which fields it filled.
    // Never returns answers or names — this endpoint is public.
    if (body.action === "check") {
      const f = (await pco(`/forms/${FORMS[level]}`)).data.attributes;
      const out: Record<string, unknown> = {
        ok: true, form: FORMS[level], name: f.name, active: f.active, archived_at: f.archived_at,
        submission_count: f.submission_count,
      };
      if (/^\d+$/.test(String(body.submission || ""))) {
        const s = await pco(`/forms/${FORMS[level]}/form_submissions/${body.submission}?include=form_submission_values`);
        out.submission = {
          id: s.data.id, created_at: s.data.attributes.created_at,
          fields_filled: (s.included || []).map((v: any) => v.relationships?.form_field?.data?.id),
        };
      }
      return new Response(JSON.stringify(out, null, 2), { headers: h });
    }

    const me = checkMe(body.me);
    const answers = checkAnswers(body.answers);
    const { _summary, ...payload } = await build(level, me, answers);

    if (body.action === "preview") {
      return new Response(JSON.stringify({ ok: true, form: FORMS[level], summary: _summary, payload }, null, 2), { headers: h });
    }
    if (body.action !== "submit") throw new Problem("unknown action");

    const res = await pco(`/forms/${FORMS[level]}/form_submissions`, { method: "POST", body: JSON.stringify(payload) });
    const person = res?.data?.relationships?.person?.data?.id ?? null;
    // The submission is in; a failed alert must not make the app retry it.
    try { console.log(await alertLeaders(level, me, answers, person)); } catch (e) { console.error("alerts:", e); }
    return new Response(JSON.stringify({ ok: true, submission: res?.data?.id ?? null, person }), { headers: h });
  } catch (e) {
    const known = e instanceof Problem;
    console.error(e);
    return new Response(JSON.stringify({ ok: false, error: known ? e.message : "Unexpected error" }),
      { status: known ? 400 : 500, headers: h });
  }
});
