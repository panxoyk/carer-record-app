import type { Context } from "./handler.ts";
import type { UtcRange } from "./handler.ts";

export type Purpose = "record" | "timeline";
export type Flag = "high" | "low" | "abnormal";
export type Entry = {
  id: string;
  title: string;
  detail: string | null;
  date: string | null;
  isDateOnly: boolean;
  sourceKind: string;
  /** Compact measured value, e.g. `120/80 mmHg` (ADR-024). */
  value: string | null;
  /** Abnormal value from `interpretation` or `referenceRange`. */
  flag: Flag | null;
  /** First coded concept of the resource (LOINC for observations). */
  code: string | null;
  /** First category code (`vital-signs`, `laboratory`, `fluid-intake`…). */
  category: string | null;
  /** Administration instant matched to a scheduled dose. */
  administeredAt: string | null;
  /** Context note client event id a clinical photo belongs to. */
  noteRef: string | null;
};
export type TimelineItem = {
  id: string;
  occurredAt: string | null;
  precision: "date" | "instant" | null;
  resourceType: string;
  title: string;
  detail: string | null;
  summaryDetail?: string | null;
};
export type ClinicalRecord = {
  status: "complete" | "partial";
  truncated: boolean;
  freshness: { retrievedAt: string; sourceUpdatedAt: string | null };
  patient: {
    id: string;
    name: string;
    identifier: string | null;
    birthDate: string | null;
    gender: string | null;
  };
  hospitalization: {
    id: string;
    status: string;
    admittedAt: string;
    dischargedAt: string | null;
    unit: string | null;
    bed: string | null;
    attendingPhysician: string | null;
    reason: string | null;
  };
  sections: { type: string; entries: Entry[] }[];
  timeline: TimelineItem[];
};

const TYPES = [
  "Condition",
  "Observation",
  "MedicationRequest",
  "Procedure",
  "DiagnosticReport",
  "AllergyIntolerance",
  "MedicationAdministration",
  "DocumentReference",
] as const;
/** Category code for clinical photos and system for note links (ADR-024). */
export const PHOTO_CATEGORY = "clinical-photo";
export const NOTE_IDENTIFIER_SYSTEM = "urn:carer-record:context-note";
const ID = /^[A-Za-z0-9.-]{1,64}$/;
const MAX_PAGES = 20,
  MAX_RESOURCES = 500,
  MAX_BYTES = 5_000_000,
  TIMEOUT_MS = 10_000;
// deno-lint-ignore no-explicit-any
type Resource = Record<string, any>;
type Fetcher = typeof fetch;
const ref = (value: unknown, type: string): string | null => {
  if (typeof value !== "string") return null;
  const m = new RegExp(`^${type}/([A-Za-z0-9.-]{1,64})$`).exec(value);
  return m?.[1] ?? null;
};
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") {
    const object = value as Resource;
    return `{${
      Object.keys(object).sort().map((key) =>
        `${JSON.stringify(key)}:${canonical(object[key])}`
      ).join(",")
    }}`;
  }
  return JSON.stringify(value);
}
function mergeUnique(resources: Resource[]): Resource[] {
  const found = new Map<string, Resource>();
  for (const resource of resources) {
    const previous = found.get(resource.id);
    if (
      previous && (previous.meta?.versionId !== resource.meta?.versionId ||
        canonical(previous) !== canonical(resource))
    ) {
      throw new Error("conflicting duplicate FHIR resource");
    }
    if (!previous) found.set(resource.id, resource);
  }
  return [...found.values()];
}
const codings = (cc: Resource): string[] =>
  (cc?.coding ?? []).map((x: Resource) => x.display || x.code).filter((
    x: unknown,
  ): x is string => typeof x === "string" && !!x.trim());
const codeText = (cc: Resource): string =>
  cc?.text?.trim() || codings(cc).join(" / ") || "Sin descripción";
function formatQuantity(q: Resource, includeComparator = false): string | null {
  if (!q || q.value == null) return null;
  return `${includeComparator ? q.comparator ?? "" : ""}${q.value}${
    q.unit ? ` ${q.unit}` : q.code ? ` ${q.code}` : ""
  }`;
}
function dateInfo(value: unknown): { value: string | null; dateOnly: boolean } {
  if (typeof value !== "string") return { value: null, dateOnly: false };
  const calendarIsValid = (date: string) => {
    const [y, m, d] = date.split("-").map(Number);
    if (y < 1 || m < 1 || m > 12) return false;
    if (d === undefined) return true;
    const leap = y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0);
    const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return d >= 1 && d <= days[m - 1];
  };
  if (/^\d{4}(?:-\d{2}(?:-\d{2})?)?$/.test(value)) {
    if (!calendarIsValid(value.length > 4 ? value.slice(0, 10) : value)) {
      throw new Error("invalid clinical date");
    }
    return { value, dateOnly: true };
  }
  const match =
    /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(Z|([+-])(\d{2}):(\d{2}))$/
      .exec(value);
  if (match) {
    const [
      ,
      date,
      hour,
      minute,
      second = "0",
      ,
      ,
      ,
      offsetHour = "0",
      offsetMinute = "0",
    ] = match;
    if (
      !calendarIsValid(date) || Number(hour) > 23 || Number(minute) > 59 ||
      Number(second) > 59 || Number(offsetHour) > 14 ||
      Number(offsetMinute) > 59 ||
      (Number(offsetHour) === 14 && Number(offsetMinute) !== 0) ||
      !Number.isFinite(Date.parse(value))
    ) throw new Error("invalid clinical date");
    return { value, dateOnly: false };
  }
  throw new Error("invalid clinical date");
}
function patientReference(r: Resource): string | null {
  return ref(r.subject?.reference ?? r.patient?.reference, "Patient");
}
function episodeReference(r: Resource): string | null {
  // MedicationAdministration names its encounter `context`; DocumentReference
  // keeps it in `context.encounter[]` (FHIR R4).
  return ref(
    r.encounter?.reference ?? r.context?.reference ??
      r.context?.encounter?.[0]?.reference,
    "Encounter",
  );
}
function ensureResource(r: Resource, type: string, ctx: Context): void {
  if (
    !r || r.resourceType !== type || typeof r.id !== "string" || !ID.test(r.id)
  ) throw new Error("invalid FHIR resource");
  if (patientReference(r) !== ctx.patient_fhir_id) {
    throw new Error("foreign patient resource");
  }
  if (
    type !== "AllergyIntolerance" &&
    episodeReference(r) !== ctx.encounter_fhir_id
  ) throw new Error("foreign encounter resource");
}
function dateFor(r: Resource): string | null {
  const v = r.effectiveDateTime ?? r.effectiveDate ?? r.issued ??
    r.authoredOn ?? r.performedDateTime ?? r.performedPeriod?.start ??
    r.onsetDateTime ?? r.recordedDate ?? r.date;
  return dateInfo(v).value;
}
function utcDate(year: number, month: number, day: number): Date {
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  date.setUTCHours(0, 0, 0, 0);
  return date;
}
function localDateKey(time: number, timezone: string): string {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(time).map((part) => [part.type, part.value]),
  );
  return `${parts.year.padStart(4, "0")}-${parts.month}-${parts.day}`;
}
function firstInstantOnOrAfterLocalDate(key: string, timezone: string): number {
  const [year, month, day] = key.split("-").map(Number);
  const approximate = utcDate(year, month, day).getTime();
  let low = approximate - 48 * 60 * 60 * 1000;
  let high = approximate + 48 * 60 * 60 * 1000;
  if (
    localDateKey(low, timezone) >= key || localDateKey(high, timezone) < key
  ) {
    throw new Error("cannot resolve institutional calendar date");
  }
  while (low + 1 < high) {
    const middle = Math.floor((low + high) / 2);
    if (localDateKey(middle, timezone) >= key) high = middle;
    else low = middle;
  }
  return high;
}
function localMidnightUtc(
  year: number,
  month: number,
  day: number,
  timezone: string,
): number {
  const key = `${String(year).padStart(4, "0")}-${
    String(month).padStart(2, "0")
  }-${String(day).padStart(2, "0")}`;
  return firstInstantOnOrAfterLocalDate(key, timezone);
}
function dateWithinRange(
  value: string,
  range: { fromUtc: string; toUtc: string },
  timezone: string,
): boolean {
  if (/^\d{4}(?:-\d{2}(?:-\d{2})?)?$/.test(value)) {
    const [year, month = "01", day = "01"] = value.split("-");
    const start = localMidnightUtc(
      Number(year),
      Number(month),
      Number(day),
      timezone,
    );
    const nextParts = value.length === 4
      ? utcDate(Number(year) + 1, 1, 1)
      : value.length === 7
      ? utcDate(Number(year), Number(month) + 1, 1)
      : utcDate(Number(year), Number(month), Number(day) + 1);
    const end = localMidnightUtc(
      nextParts.getUTCFullYear(),
      nextParts.getUTCMonth() + 1,
      nextParts.getUTCDate(),
      timezone,
    );
    return start < Date.parse(range.toUtc) && end > Date.parse(range.fromUtc);
  }
  const time = Date.parse(value);
  return Number.isFinite(time) && time >= Date.parse(range.fromUtc) &&
    time < Date.parse(range.toUtc);
}
function detailFor(
  type: string,
  r: Resource,
  observations: Map<string, Resource>,
  includeComparator = false,
): string | null {
  const parts: string[] = [];
  if (type === "Observation") {
    if (r.valueQuantity) {
      parts.push(formatQuantity(r.valueQuantity, includeComparator)!);
    } else if (r.valueString != null) parts.push(String(r.valueString));
    else if (r.valueCodeableConcept) {
      parts.push(codeText(r.valueCodeableConcept));
    }
    for (const c of r.component ?? []) {
      const val = formatQuantity(c.valueQuantity, includeComparator) ??
        c.valueString ??
        codeText(c.valueCodeableConcept);
      if (val) parts.push(`${codeText(c.code)}: ${val}`);
    }
    for (const range of r.referenceRange ?? []) {
      const low = formatQuantity(range.low, includeComparator),
        high = formatQuantity(range.high, includeComparator);
      parts.push(
        `Referencia: ${low ?? ""}${low && high ? "–" : ""}${high ?? ""}${
          range.text ? ` (${range.text})` : ""
        }`.trim(),
      );
    }
  } else if (type === "MedicationRequest") {
    const med = codeText(r.medicationCodeableConcept);
    const doses = (r.dosageInstruction ?? []).map((d: Resource) =>
      [
        d.text,
        d.route ? `vía ${codeText(d.route)}` : null,
        d.doseAndRate?.map((x: Resource) => formatQuantity(x.doseQuantity))
          .filter(Boolean).join(", "),
      ].filter(Boolean).join("; ")
    ).filter(Boolean);
    parts.push(
      `Prescripción: ${med}${doses.length ? ` — ${doses.join("; ")}` : ""}`,
    );
  } else if (type === "DiagnosticReport") {
    if (r.conclusion) parts.push(r.conclusion);
    for (const item of r.result ?? []) {
      const id = ref(item.reference, "Observation");
      if (!id) throw new Error("invalid DiagnosticReport result reference");
      const obs = observations.get(id);
      if (!obs) {
        throw new Error(
          "DiagnosticReport references an unauthorized observation",
        );
      }
      const d = detailFor("Observation", obs, observations);
      parts.push(`${codeText(obs.code)}${d ? `: ${d}` : ""}`);
    }
  } else if (type === "Condition") {
    parts.push(
      r.clinicalStatus?.coding?.map((c: Resource) => c.display || c.code)
        .filter(Boolean).join(" / ") || "",
    );
  } else if (type === "MedicationAdministration") {
    const dose = formatQuantity(r.dosage?.dose);
    parts.push(
      [dose, r.dosage?.route ? `vía ${codeText(r.dosage.route)}` : null]
        .filter(Boolean).join(" · "),
    );
  } else if (type === "DocumentReference") {
    parts.push(r.content?.[0]?.attachment?.title ?? "");
  } else if (type === "Procedure") parts.push(r.status || "");
  else if (type === "AllergyIntolerance") {
    parts.push(
      r.clinicalStatus?.coding?.map((c: Resource) => c.display || c.code)
        .filter(Boolean).join(" / ") || "",
    );
  }
  return parts.filter(Boolean).join(" · ") || null;
}
function summaryDetailFor(
  type: string,
  r: Resource,
  observations: Map<string, Resource>,
): string | null {
  const parts: string[] = [];
  if (type === "Observation") {
    if (r.status) parts.push(`Estado: ${r.status}`);
    const value = detailFor(type, r, observations, true);
    if (value) parts.push(value);
  } else if (type === "Condition") {
    if (r.clinicalStatus) {
      parts.push(`Estado clínico: ${codeText(r.clinicalStatus)}`);
    }
    if (r.verificationStatus) {
      parts.push(`Verificación: ${codeText(r.verificationStatus)}`);
    }
  } else if (type === "MedicationRequest") {
    if (r.status) parts.push(`Estado: ${r.status}`);
    if (r.intent) parts.push(`Intención: ${r.intent}`);
    const medication = codeText(r.medicationCodeableConcept);
    if (medication !== "Sin descripción") {
      parts.push(`Medicamento: ${medication}`);
    }
    for (const d of r.dosageInstruction ?? []) {
      const dosage: string[] = [];
      if (d.text) dosage.push(d.text);
      if (d.route) dosage.push(`Vía: ${codeText(d.route)}`);
      for (const x of d.doseAndRate ?? []) {
        const dose = formatQuantity(x.doseQuantity, true);
        if (dose) dosage.push(`Dosis: ${dose}`);
        if (x.doseRange) {
          const low = formatQuantity(x.doseRange.low, true);
          const high = formatQuantity(x.doseRange.high, true);
          if (low || high) {
            dosage.push(
              `Rango de dosis: ${low ?? ""}${low && high ? "–" : ""}${
                high ?? ""
              }`,
            );
          }
        }
        const rateQuantity = formatQuantity(x.rateQuantity, true);
        if (rateQuantity) dosage.push(`Tasa: ${rateQuantity}`);
        if (x.rateRange) {
          const low = formatQuantity(x.rateRange.low, true);
          const high = formatQuantity(x.rateRange.high, true);
          if (low || high) {
            dosage.push(
              `Rango de tasa: ${low ?? ""}${low && high ? "–" : ""}${
                high ?? ""
              }`,
            );
          }
        }
        if (x.rateRatio) {
          const numerator = formatQuantity(x.rateRatio.numerator, true);
          const denominator = formatQuantity(x.rateRatio.denominator, true);
          if (numerator || denominator) {
            dosage.push(
              `Tasa — numerador: ${numerator ?? "no indicado"}; denominador: ${
                denominator ?? "no indicado"
              }`,
            );
          }
        }
      }
      if (d.timing?.repeat) {
        const repeat = d.timing.repeat;
        for (
          const [label, value] of [
            ["Frecuencia", repeat.frequency],
            ["Periodo", repeat.period],
            ["Unidad de periodo", repeat.periodUnit],
            ["Frecuencia máxima", repeat.frequencyMax],
            ["Periodo máximo", repeat.periodMax],
          ] as [string, unknown][]
        ) {
          if (value != null) dosage.push(`${label}: ${value}`);
        }
      }
      if (d.timing?.repeat?.duration != null) {
        dosage.push(
          `Duración de administración: ${d.timing.repeat.duration}${
            d.timing.repeat.durationUnit
              ? ` ${d.timing.repeat.durationUnit}`
              : ""
          }`,
        );
      }
      if (d.asNeededBoolean != null) {
        dosage.push(`Según necesidad: ${d.asNeededBoolean}`);
      }
      if (d.asNeededCodeableConcept) {
        dosage.push(`Según necesidad: ${codeText(d.asNeededCodeableConcept)}`);
      }
      if (dosage.length) parts.push(dosage.join("; "));
    }
  } else if (type === "Procedure") {
    if (r.status) parts.push(`Estado: ${r.status}`);
    if (r.outcome) parts.push(`Resultado: ${codeText(r.outcome)}`);
  } else if (type === "DiagnosticReport") {
    if (r.status) parts.push(`Estado: ${r.status}`);
    if (r.conclusion) parts.push(`Conclusión: ${r.conclusion}`);
    for (const item of r.result ?? []) {
      const id = ref(item.reference, "Observation");
      if (!id) throw new Error("invalid DiagnosticReport result reference");
      const obs = observations.get(id);
      if (!obs) {
        throw new Error(
          "DiagnosticReport references an unauthorized observation",
        );
      }
      const date = dateInfo(dateFor(obs));
      const details = detailFor("Observation", obs, observations, true);
      parts.push(
        `Resultado ${id} · ${date.value ?? "Fecha no disponible"}${
          date.dateOnly ? " (fecha)" : date.value ? " (instante)" : ""
        }: ${codeText(obs.code)}${
          obs.status ? ` · Estado: ${obs.status}` : ""
        }${details ? ` · ${details}` : ""}`,
      );
    }
  }
  return parts.join(" · ") || null;
}
function sectionName(t: string): string {
  return ({
    Condition: "conditions",
    Observation: "observations",
    MedicationRequest: "medications",
    Procedure: "procedures",
    DiagnosticReport: "reports",
    AllergyIntolerance: "allergies",
    MedicationAdministration: "administrations",
    DocumentReference: "photos",
  } as Record<string, string>)[t];
}
function titleFor(t: string, r: Resource): string {
  if (t === "DocumentReference") {
    return r.description?.trim() || r.content?.[0]?.attachment?.title?.trim() ||
      "Foto clínica";
  }
  return codeText(
    t === "MedicationRequest" || t === "MedicationAdministration"
      ? r.medicationCodeableConcept
      : t === "AllergyIntolerance"
      ? r.code
      : r.code ?? r.type,
  );
}
const firstCode = (cc: Resource): string | null =>
  cc?.coding?.find((c: Resource) => typeof c.code === "string")?.code ?? null;
function codeFor(t: string, r: Resource): string | null {
  return firstCode(
    t === "MedicationRequest" || t === "MedicationAdministration"
      ? r.medicationCodeableConcept
      : r.code,
  );
}
function categoryFor(r: Resource): string | null {
  const categories = Array.isArray(r.category) ? r.category : [r.category];
  for (const category of categories) {
    const code = firstCode(category);
    if (code) return code;
  }
  return null;
}
const compact = (q: Resource): string | null =>
  q?.value == null ? null : String(q.value);
/** Measured value, joining systolic/diastolic components as `120/80 mmHg`. */
function valueFor(t: string, r: Resource): string | null {
  if (t !== "Observation") return null;
  if (r.valueQuantity) return formatQuantity(r.valueQuantity);
  if (r.valueString != null) return String(r.valueString);
  const parts = (r.component ?? []).map((c: Resource) =>
    compact(c.valueQuantity)
  ).filter(Boolean);
  if (parts.length) {
    const unit = r.component?.[0]?.valueQuantity?.unit ?? "";
    return `${parts.join("/")}${unit ? ` ${unit}` : ""}`;
  }
  return null;
}
const INTERPRETATION: Record<string, Flag> = {
  H: "high",
  HH: "high",
  HU: "high",
  L: "low",
  LL: "low",
  LU: "low",
  A: "abnormal",
  AA: "abnormal",
};
function quantityOutside(q: Resource, range: Resource): Flag | null {
  if (q?.value == null) return null;
  const sameUnit = (bound: Resource) =>
    bound?.value != null && (bound.unit ?? bound.code) === (q.unit ?? q.code);
  if (sameUnit(range.high) && q.value > range.high.value) return "high";
  if (sameUnit(range.low) && q.value < range.low.value) return "low";
  return null;
}
/** Uses the source interpretation; otherwise compares with referenceRange. */
function flagFor(t: string, r: Resource): Flag | null {
  if (t !== "Observation") return null;
  for (const interpretation of r.interpretation ?? []) {
    for (const coding of interpretation.coding ?? []) {
      const flag = INTERPRETATION[coding.code];
      if (flag) return flag;
    }
  }
  for (const range of r.referenceRange ?? []) {
    const own = quantityOutside(r.valueQuantity, range);
    if (own) return own;
  }
  for (const component of r.component ?? []) {
    for (const range of component.referenceRange ?? []) {
      const flag = quantityOutside(component.valueQuantity, range);
      if (flag) return flag;
    }
  }
  return null;
}
/**
 * What a photo belongs to: a context note (its client event id) or a FHIR
 * event of the same timeline (its entry id, e.g. a wound-care Procedure).
 */
function noteRefFor(t: string, r: Resource): string | null {
  if (t !== "DocumentReference") return null;
  for (const related of r.context?.related ?? []) {
    if (related.identifier?.system === NOTE_IDENTIFIER_SYSTEM) {
      const value = related.identifier.value;
      return typeof value === "string" && /^[0-9a-f-]{36}$/i.test(value)
        ? value.toLowerCase()
        : null;
    }
    const match = /^(Procedure|Observation)\/([A-Za-z0-9.-]{1,64})$/.exec(
      String(related.reference ?? ""),
    );
    if (match) return entryId(match[1], match[2]);
  }
  return null;
}
function entryFor(
  type: string,
  r: Resource,
  observations: Map<string, Resource>,
): Entry {
  const d = dateInfo(dateFor(r));
  return {
    id: entryId(type, r.id),
    title: titleFor(type, r),
    detail: detailFor(type, r, observations),
    date: d.value,
    isDateOnly: d.dateOnly,
    sourceKind: type,
    value: valueFor(type, r),
    flag: flagFor(type, r),
    code: codeFor(type, r),
    category: categoryFor(r),
    administeredAt: type === "MedicationAdministration" ? d.value : null,
    noteRef: noteRefFor(type, r),
  };
}
/**
 * Scheduled doses from `MedicationRequest.dosageInstruction.timing.event`,
 * each matched to the nearest administration of the same order (±3 h). The
 * remaining administrations are listed on their own.
 */
function administrationEntries(
  requests: Resource[],
  administrations: Resource[],
  observations: Map<string, Resource>,
): Entry[] {
  const unused = new Set(administrations.map((a) => a.id));
  const entries: Entry[] = [];
  for (const request of requests) {
    const events = (request.dosageInstruction ?? []).flatMap((d: Resource) =>
      d.timing?.event ?? []
    ).filter((value: unknown) => typeof value === "string");
    for (const scheduled of events) {
      const at = dateInfo(scheduled);
      if (!at.value || at.dateOnly) continue;
      const time = Date.parse(at.value);
      let match: Resource | null = null;
      for (const administration of administrations) {
        if (!unused.has(administration.id)) continue;
        if (
          ref(administration.request?.reference, "MedicationRequest") !==
            request.id
        ) continue;
        const given = dateFor(administration);
        if (!given || Math.abs(Date.parse(given) - time) > 3 * 3_600_000) {
          continue;
        }
        if (
          !match ||
          Math.abs(Date.parse(given) - time) <
            Math.abs(Date.parse(dateFor(match)!) - time)
        ) match = administration;
      }
      if (match) unused.delete(match.id);
      entries.push({
        ...entryFor("MedicationRequest", request, observations),
        id: `${entryId("MedicationRequest", request.id)}@${at.value}`,
        sourceKind: "MedicationAdministration",
        date: at.value,
        isDateOnly: false,
        administeredAt: match ? dateFor(match) : null,
      });
    }
  }
  for (const administration of administrations) {
    if (unused.has(administration.id)) {
      entries.push(
        entryFor("MedicationAdministration", administration, observations),
      );
    }
  }
  return entries.sort((a, b) => (a.date ?? "").localeCompare(b.date ?? ""));
}
function entryId(t: string, id: string): string {
  return `demo-hapi/${t}/${id}`;
}

export async function loadClinicalRecord(
  ctx: Context,
  purpose: Purpose,
  fetcher: Fetcher,
  baseURL: string,
  range?: UtcRange,
  timezone?: string,
): Promise<ClinicalRecord> {
  if (range && !timezone) throw new Error("institution timezone required");
  if (!ID.test(ctx.patient_fhir_id) || !ID.test(ctx.encounter_fhir_id)) {
    throw new Error("invalid authorized context");
  }
  const base = new URL(baseURL);
  if (
    !["http:", "https:"].includes(base.protocol) || base.username ||
    base.password || base.search || base.hash
  ) throw new Error("invalid source base URL");
  const rootPath = base.pathname.replace(/\/$/, "");
  const root = new URL(`${rootPath}/`, base.origin);
  let bytes = 0, truncated = false;
  const fetchJson = async (url: URL): Promise<Resource> => {
    const relativePath = url.pathname.startsWith(rootPath + "/")
      ? url.pathname.slice(rootPath.length + 1)
      : "";
    if (
      url.origin !== base.origin ||
      (url.pathname !== rootPath &&
        !/^[A-Za-z]+(?:\/[A-Za-z0-9.-]{1,64})?$/.test(relativePath))
    ) throw new Error("upstream URL outside source");
    const response = await fetcher(url, {
      headers: { accept: "application/fhir+json" },
      redirect: "error",
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!response.ok) throw new Error("FHIR upstream error");
    const declared = Number(response.headers.get("content-length") ?? 0);
    if (declared && bytes + declared > MAX_BYTES) {
      truncated = true;
      throw new Error("FHIR byte limit exceeded");
    }
    if (!response.body) throw new Error("FHIR response body missing");
    const reader = response.body.getReader();
    const decoder = new TextDecoder("utf-8", { fatal: true });
    let text = "";
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > MAX_BYTES) {
        await reader.cancel();
        truncated = true;
        throw new Error("FHIR byte limit exceeded");
      }
      text += decoder.decode(value, { stream: true });
    }
    try {
      return JSON.parse(text + decoder.decode()) as Resource;
    } catch {
      throw new Error("invalid FHIR JSON");
    }
  };
  const resource = async (type: string, id: string) => {
    const result = await fetchJson(
      new URL(`${type}/${encodeURIComponent(id)}`, root),
    );
    if (result.resourceType !== type || result.id !== id) {
      throw new Error("FHIR identity mismatch");
    }
    return result;
  };
  const search = async (
    type: typeof TYPES[number],
    patientOnly = false,
    dateParam?: string,
    missingDate = false,
    missingDateParam = "date",
  ): Promise<Resource[]> => {
    const params = new URLSearchParams({
      patient: `Patient/${ctx.patient_fhir_id}`,
      _count: "100",
    });
    if (!patientOnly) {
      params.set(
        type === "MedicationAdministration" ? "context" : "encounter",
        `Encounter/${ctx.encounter_fhir_id}`,
      );
    }
    if (range && dateParam) {
      const lower = new Date(Math.max(
        utcDate(1, 1, 1).getTime(),
        Date.parse(range.fromUtc) - 86_400_000,
      ))
        .toISOString().slice(0, 10);
      const upper = new Date(Date.parse(range.toUtc) + 86_400_000)
        .toISOString().slice(0, 10);
      params.append(dateParam, `ge${lower}`);
      params.append(dateParam, `lt${upper}`);
    }
    if (range && missingDate) {
      params.append(`${missingDateParam}:missing`, "true");
    }
    let next: URL | null = new URL(`${type}?${params}`, root), pages = 0;
    const seen = new Set<string>(), found = new Map<string, Resource>();
    while (next) {
      if (++pages > MAX_PAGES) {
        truncated = true;
        break;
      }
      if (seen.has(next.href)) throw new Error("FHIR pagination cycle");
      seen.add(next.href);
      const bundle = await fetchJson(next);
      if (
        bundle.resourceType !== "Bundle" || bundle.type !== "searchset" ||
        !Array.isArray(bundle.entry ?? [])
      ) throw new Error("invalid FHIR search bundle");
      let limitReached = false;
      for (const e of bundle.entry ?? []) {
        if (!e.resource) continue;
        ensureResource(e.resource, type, ctx);
        const previous = found.get(e.resource.id);
        if (previous) {
          if (
            previous.meta?.versionId !== e.resource.meta?.versionId ||
            canonical(previous) !== canonical(e.resource)
          ) throw new Error("conflicting duplicate FHIR resource");
          continue;
        }
        if (found.size >= (range ? MAX_PAGES * 100 : MAX_RESOURCES)) {
          truncated = true;
          limitReached = true;
          break;
        }
        found.set(e.resource.id, e.resource);
      }
      const link = bundle.link?.find((x: Resource) => x.relation === "next")
        ?.url;
      if (limitReached || found.size >= MAX_RESOURCES && link != null) {
        if (link != null) truncated = true;
        break;
      }
      if (link == null) next = null;
      else {
        if (typeof link !== "string") throw new Error("invalid next link");
        const candidate: URL = new URL(link, next.href);
        if (
          candidate.origin !== base.origin || candidate.username ||
          candidate.password || candidate.hash ||
          candidate.pathname !== rootPath
        ) throw new Error("untrusted FHIR next link");
        const qs = candidate.searchParams;
        const allowed = new Set([
          "_getpages",
          "_getpagesoffset",
          "_count",
          "_pretty",
          "_bundletype",
          "_format",
        ]);
        if (
          [...qs.keys()].some((key) => !allowed.has(key)) ||
          [...qs.keys()].some((key) => qs.getAll(key).length !== 1) ||
          qs.getAll("_getpages").length !== 1 ||
          !/^[A-Za-z0-9._-]{1,128}$/.test(qs.get("_getpages") ?? "")
        ) throw new Error("untrusted FHIR cursor");
        if (
          qs.has("_getpagesoffset") &&
          !/^(0|[1-9]\d{0,5})$/.test(qs.get("_getpagesoffset")!)
        ) throw new Error("untrusted FHIR cursor offset");
        if (
          qs.has("_count") && !/^(?:[1-9]\d{0,2}|1000)$/.test(qs.get("_count")!)
        ) throw new Error("untrusted FHIR cursor count");
        if (
          qs.has("_pretty") && !["true", "false"].includes(qs.get("_pretty")!)
        ) throw new Error("untrusted FHIR cursor option");
        if (qs.has("_bundletype") && qs.get("_bundletype") !== "searchset") {
          throw new Error("untrusted FHIR cursor type");
        }
        if (
          qs.has("_format") &&
          !["application/fhir+json", "json"].includes(qs.get("_format")!)
        ) throw new Error("untrusted FHIR cursor format");
        next = candidate;
      }
    }
    return [...found.values()];
  };
  const retrievedAt = new Date().toISOString();
  const [patient, encounter] = await Promise.all([
    resource("Patient", ctx.patient_fhir_id),
    resource("Encounter", ctx.encounter_fhir_id),
  ]);
  const subject = ref(encounter.subject?.reference, "Patient");
  if (
    subject !== ctx.patient_fhir_id || encounter.class?.code !== "IMP" ||
    !["in-progress", "finished"].includes(encounter.status)
  ) throw new Error("authorized Encounter invalid");
  const start = dateInfo(encounter.period?.start);
  if (!start.value || start.dateOnly) {
    throw new Error("Encounter start instant required");
  }
  const end = dateInfo(encounter.period?.end);
  if (
    encounter.status === "in-progress" && end.value ||
    encounter.status === "finished" && (!end.value || end.dateOnly)
  ) throw new Error("Encounter period/status mismatch");
  if (end.value && Date.parse(end.value) < Date.parse(start.value)) {
    throw new Error("invalid Encounter period");
  }
  const [
    conditions,
    observations,
    medications,
    procedures,
    reports,
    allergies,
    administrations,
    documents,
  ] = await Promise.all([
    range
      ? Promise.all([
        search("Condition", false, "onset-date"),
        search("Condition", false, "recorded-date"),
        search("Condition", false, undefined, true, "onset-date"),
      ]).then((rows) => mergeUnique(rows.flat()))
      : search("Condition", false),
    range
      ? Promise.all([
        search("Observation", false, "date"),
        search("Observation", false, undefined, true),
      ]).then((rows) => mergeUnique(rows.flat()))
      : search("Observation", false),
    range
      ? Promise.all([
        search("MedicationRequest", false, "authoredon"),
        search("MedicationRequest", false, undefined, true, "authoredon"),
      ]).then((rows) => mergeUnique(rows.flat()))
      : search("MedicationRequest", false),
    search("Procedure", false, range ? "date" : undefined),
    range
      ? Promise.all([
        search("DiagnosticReport", false, "date"),
        search("DiagnosticReport", false, undefined, true),
      ]).then((rows) => mergeUnique(rows.flat()))
      : search("DiagnosticReport", false),
    search("AllergyIntolerance", true),
    search("MedicationAdministration", false),
    search("DocumentReference", false).then((rows) =>
      rows.filter((r) => categoryFor(r) === PHOTO_CATEGORY)
    ),
  ]);
  const byType = new Map<string, Resource[]>(
    TYPES.map((
      t,
      i,
    ) => [
      t,
      [
        conditions,
        observations,
        medications,
        procedures,
        reports,
        allergies,
        administrations,
        documents,
      ][i],
    ]),
  );
  if (range && timezone) {
    for (const type of TYPES) {
      const rows = byType.get(type) ?? [];
      byType.set(
        type,
        rows.filter((r) => {
          const value = dateFor(r);
          return value !== null && dateWithinRange(value, range, timezone);
        }),
      );
    }
  }
  let remaining = MAX_RESOURCES;
  for (const type of TYPES) {
    const rows = byType.get(type) ?? [];
    if (rows.length > remaining) {
      byType.set(type, rows.slice(0, remaining));
      truncated = true;
    } else remaining -= rows.length;
  }
  const observationsInRange = byType.get("Observation") ?? [];
  const observationMap = new Map(observationsInRange.map((o) => [o.id, o]));
  if (range) {
    const referencedIds = [
      ...new Set(
        (byType.get("DiagnosticReport") ?? []).flatMap((report) =>
          (report.result ?? []).map((item: Resource) =>
            ref(item.reference, "Observation")
          )
            .filter((id: string | null): id is string => id !== null)
        ),
      ),
    ].filter((id) => !observationMap.has(id));
    if (referencedIds.length + observations.length > MAX_RESOURCES) {
      truncated = true;
      throw new Error("FHIR resource limit exceeded");
    }
    const linked = await Promise.all(referencedIds.map(async (id) => {
      const observation = await resource("Observation", id);
      ensureResource(observation, "Observation", ctx);
      return observation;
    }));
    for (const observation of linked) {
      observationMap.set(observation.id, observation);
    }
  }
  const locRefs: string[] = [];
  for (const l of encounter.location ?? []) {
    const id = ref(l.location?.reference, "Location");
    if (!id) throw new Error("invalid Encounter Location reference");
    if (!locRefs.includes(id)) locRefs.push(id);
  }
  const locations = await Promise.all(
    locRefs.map((id) => resource("Location", id)),
  );
  const locById = new Map(locations.map((l) => [l.id, l]));
  let unit: string | null = null, bed: string | null = null;
  for (const l of locations) {
    const parentId = l.partOf ? ref(l.partOf.reference, "Location") : null;
    if (l.partOf && !parentId) {
      throw new Error("invalid Location parent reference");
    }
    const parent = parentId
      ? locById.get(parentId) ?? await resource("Location", parentId)
      : null;
    if (parentId && parent?.resourceType !== "Location") {
      throw new Error("invalid Location parent");
    }
    if (l.physicalType?.coding?.some((c: Resource) => c.code === "wa")) {
      unit = l.name ?? unit;
    } else {
      bed = l.name ?? bed;
      if (
        parent?.physicalType?.coding?.some((c: Resource) => c.code === "wa")
      ) unit = parent.name ?? unit;
    }
  }
  const sections = TYPES.map((type) => ({
    type: sectionName(type),
    entries: type === "MedicationAdministration"
      ? administrationEntries(
        byType.get("MedicationRequest") ?? [],
        byType.get("MedicationAdministration") ?? [],
        observationMap,
      )
      : (byType.get(type) ?? []).map((r) => entryFor(type, r, observationMap))
        .sort((a, b) => (b.date ?? "").localeCompare(a.date ?? "")),
  }));
  const timeline: TimelineItem[] = [];
  if (purpose === "timeline") {
    // Photos are shown inside the note they belong to, not as own events.
    for (
      const type of TYPES.filter((t) =>
        t !== "AllergyIntolerance" && t !== "DocumentReference"
      )
    ) {
      for (const r of byType.get(type) ?? []) {
        const d = dateInfo(dateFor(r));
        timeline.push({
          id: entryId(type, r.id),
          occurredAt: d.value,
          precision: d.value ? d.dateOnly ? "date" : "instant" : null,
          resourceType: type,
          title: titleFor(type, r),
          detail: detailFor(type, r, observationMap),
          summaryDetail: summaryDetailFor(type, r, observationMap),
        });
      }
    }
  }
  timeline.sort((a, b) =>
    (b.occurredAt ?? "").localeCompare(a.occurredAt ?? "")
  );
  const official = patient.name?.find((n: Resource) => n.use === "official") ??
    patient.name?.[0] ?? {};
  const name = [
    ...(official.given ?? []),
    ...(official.family ? [official.family] : []),
  ].join(" ").trim();
  const sourceTimes = [
    patient,
    encounter,
    ...TYPES.flatMap((t) => byType.get(t) ?? []),
    ...locations,
  ].map((r) => r.meta?.lastUpdated).filter((v): v is string =>
    typeof v === "string"
  );
  for (const value of sourceTimes) {
    const timestamp = dateInfo(value);
    if (timestamp.dateOnly) {
      throw new Error("FHIR meta.lastUpdated must be an instant");
    }
  }
  const sourceUpdatedAt =
    sourceTimes.sort((a, b) => Date.parse(a) - Date.parse(b)).at(-1) ?? null;
  return {
    status: truncated ? "partial" : "complete",
    truncated,
    freshness: {
      retrievedAt,
      sourceUpdatedAt,
    },
    patient: {
      id: ctx.patient_id,
      name,
      identifier: patient.identifier?.[0]?.value ?? null,
      birthDate: patient.birthDate ?? null,
      gender: patient.gender ?? null,
    },
    hospitalization: {
      id: ctx.hospitalization_id,
      status: encounter.status === "in-progress" ? "admitted" : "discharged",
      admittedAt: start.value,
      dischargedAt: end.value,
      unit,
      bed,
      attendingPhysician: attendingPhysician(encounter),
      reason: admissionReason(encounter, byType.get("Condition") ?? []),
    },
    sections,
    timeline,
  };
}

/** Attending physician display from `Encounter.participant` (ATND first). */
function attendingPhysician(encounter: Resource): string | null {
  const participants: Resource[] = encounter.participant ?? [];
  const attending =
    participants.find((p) =>
      p.type?.some((t: Resource) =>
        t.coding?.some((c: Resource) => c.code === "ATND")
      )
    ) ?? participants[0];
  const display = attending?.individual?.display;
  return typeof display === "string" && display.trim() ? display.trim() : null;
}

/** Admission reason from `Encounter.reasonCode`, else the principal diagnosis. */
function admissionReason(
  encounter: Resource,
  conditions: Resource[],
): string | null {
  const reason = encounter.reasonCode?.[0];
  if (reason) return codeText(reason);
  const principal = encounter.diagnosis?.find((d: Resource) => d.rank === 1) ??
    encounter.diagnosis?.[0];
  const id = ref(principal?.condition?.reference, "Condition");
  const condition = id ? conditions.find((c) => c.id === id) : null;
  return condition ? codeText(condition.code) : null;
}
