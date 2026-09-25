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

Deno.serve(async (req) => {
  const h = { ...cors(req), "Content-Type": "application/json" };
  if (req.method === "OPTIONS") return new Response(null, { headers: h });
  if (req.method !== "POST") return new Response(JSON.stringify({ ok: false, error: "POST only" }), { status: 405, headers: h });
  try {
    const body = await req.json().catch(() => ({}));
    const level = Number(body.level);
    if (!FORMS[level]) throw new Problem("level must be 1-4");

    if (body.action === "inspect") {
      const fields = await formFields(FORMS[level]);
      return new Response(JSON.stringify({ ok: true, form: FORMS[level], fields }, null, 2), { headers: h });
    }

    const me = checkMe(body.me);
    const answers = checkAnswers(body.answers);
    const { _summary, ...payload } = await build(level, me, answers);

    if (body.action === "preview") {
      return new Response(JSON.stringify({ ok: true, form: FORMS[level], summary: _summary, payload }, null, 2), { headers: h });
    }
    if (body.action !== "submit") throw new Problem("unknown action");

    const res = await pco(`/forms/${FORMS[level]}/form_submissions`, { method: "POST", body: JSON.stringify(payload) });
    return new Response(JSON.stringify({
      ok: true, submission: res?.data?.id ?? null,
      person: res?.data?.relationships?.person?.data?.id ?? null,
    }), { headers: h });
  } catch (e) {
    const known = e instanceof Problem;
    console.error(e);
    return new Response(JSON.stringify({ ok: false, error: known ? e.message : "Unexpected error" }),
      { status: known ? 400 : 500, headers: h });
  }
});
