import { headers } from "next/headers";
import { notFound } from "next/navigation";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type Envelope = {
  contract_version?: string;
  interface_key?: string;
  canonical_id?: string;
  source_authority?: string;
  source_ref?: string;
  freshness?: { state?: string; observed_at?: string | null; age_seconds?: number | null; max_age_seconds?: number };
  readiness?: string;
  reason_code?: string;
  data?: unknown;
  warnings?: Array<{ code?: string; count?: number }>;
  candidate_inventory_completeness?: {
    readiness?: string;
    reason_code?: string;
    unverified_count?: number;
    verified_count?: number;
    newest_unverified_at?: string | null;
    observed_at?: string | null;
  };
};

type Probe = {
  path: string;
  http: number;
  contract_version: string | null;
  interface_key: string | null;
  source_authority: string | null;
  source_ref: string | null;
  freshness: Envelope["freshness"] | null;
  readiness: string | null;
  reason_code: string | null;
  payload_count: number | null;
  meaningful_payload: boolean;
  cache_control: string | null;
  pragma: string | null;
  vercel_cache: string | null;
  pii_secret_leak_detected: boolean;
  leak_paths: string[];
  body: Envelope | null;
};

const MAIN_PATHS = [
  "/api/v1/read/inbox/line",
  "/api/v1/read/system/health",
  "/api/v1/read/jobs",
  "/api/v1/read/clients",
  "/api/v1/read/partners",
  "/api/v1/read/candidates",
  "/api/v1/read/dq",
  "/api/v1/read/founder/today",
] as const;

const FORBIDDEN_KEY = /(^|_)(phone|line|sender_ref|raw_summary|private_key|access_token|authorization|apikey|api_key|service_role|secret|password|national_id|id_card|passport)($|_)/i;
const FORBIDDEN_VALUE = /(PRIVATE KEY|Bearer |sb_secret_|service_role|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})/i;

function scanForLeak(value: unknown, path: string[] = [], found: string[] = []): string[] {
  if (value === null || value === undefined) return found;
  if (typeof value === "string") {
    if (FORBIDDEN_VALUE.test(value)) found.push(path.join(".") || "<root>");
    return found;
  }
  if (Array.isArray(value)) {
    value.forEach((item, index) => scanForLeak(item, [...path, String(index)], found));
    return found;
  }
  if (typeof value === "object") {
    for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
      const next = [...path, key];
      if (FORBIDDEN_KEY.test(key) && nested !== null && nested !== "" && nested !== undefined) found.push(next.join("."));
      scanForLeak(nested, next, found);
    }
  }
  return found;
}

function payloadCount(data: unknown): number | null {
  if (Array.isArray(data)) return data.length;
  if (!data || typeof data !== "object") return data == null ? 0 : 1;
  const object = data as Record<string, unknown>;
  if (Array.isArray(object.business) || Array.isArray(object.technical)) {
    return (Array.isArray(object.business) ? object.business.length : 0) + (Array.isArray(object.technical) ? object.technical.length : 0);
  }
  if (Array.isArray(object.today) || Array.isArray(object.need_my_action)) {
    return (Array.isArray(object.today) ? object.today.length : 0) + (Array.isArray(object.need_my_action) ? object.need_my_action.length : 0);
  }
  if (Array.isArray(object.workers)) return object.workers.length;
  return Object.keys(object).length;
}

async function probe(origin: string, cookie: string, path: string): Promise<Probe> {
  const response = await fetch(origin + path, {
    headers: { accept: "application/json", ...(cookie ? { cookie } : {}) },
    cache: "no-store",
    redirect: "manual",
  });
  let body: Envelope | null = null;
  try {
    body = await response.json() as Envelope;
  } catch {
    body = null;
  }
  const leakPaths = body ? [...new Set(scanForLeak(body))].slice(0, 40) : [];
  const count = body ? payloadCount(body.data) : null;
  return {
    path,
    http: response.status,
    contract_version: body?.contract_version ?? null,
    interface_key: body?.interface_key ?? null,
    source_authority: body?.source_authority ?? null,
    source_ref: body?.source_ref ?? null,
    freshness: body?.freshness ?? null,
    readiness: body?.readiness ?? null,
    reason_code: body?.reason_code ?? null,
    payload_count: count,
    meaningful_payload: body?.data !== null && body?.data !== undefined && (count === null || count > 0),
    cache_control: response.headers.get("cache-control"),
    pragma: response.headers.get("pragma"),
    vercel_cache: response.headers.get("x-vercel-cache"),
    pii_secret_leak_detected: leakPaths.length > 0,
    leak_paths: leakPaths,
    body,
  };
}

function sanitized(probeResult: Probe) {
  const { body: _body, ...safe } = probeResult;
  return safe;
}

function firstId(probeResult: Probe) {
  const data = probeResult.body?.data;
  if (!Array.isArray(data)) return null;
  const first = data.find((row) => row && typeof row === "object" && typeof (row as { canonical_id?: unknown }).canonical_id === "string");
  return first ? String((first as { canonical_id: string }).canonical_id) : null;
}

function interfaceExpected(path: string) {
  if (path === "/api/v1/read/inbox/line") return "inbox.line";
  if (path === "/api/v1/read/system/health") return "system.health";
  if (path === "/api/v1/read/dq") return "dq.list";
  if (path === "/api/v1/read/founder/today") return "founder.today";
  for (const pair of [["jobs", "job"], ["clients", "client"], ["partners", "partner"], ["candidates", "candidate"]] as const) {
    const plural = pair[0];
    const singular = pair[1];
    if (path === "/api/v1/read/" + plural) return singular + ".list";
    if (path.startsWith("/api/v1/read/" + plural + "/")) return singular + ".detail";
  }
  return null;
}

function contractPass(p: Probe) {
  return p.http === 200
    && p.contract_version === "v1"
    && p.interface_key === interfaceExpected(p.path)
    && Boolean(p.source_authority)
    && Boolean(p.source_ref)
    && Boolean(p.freshness?.state)
    && Boolean(p.readiness)
    && /no-store/i.test(p.cache_control ?? "")
    && !p.pii_secret_leak_detected;
}

export default async function ReadGateAcceptancePage() {
  if (process.env.VERCEL_ENV !== "preview") notFound();

  const incoming = await headers();
  const host = incoming.get("host") ?? process.env.VERCEL_URL;
  if (!host) throw new Error("Preview host is unavailable.");
  const origin = (host.includes("localhost") ? "http" : "https") + "://" + host;
  const cookie = incoming.get("cookie") ?? "";

  const main = await Promise.all(MAIN_PATHS.map((path) => probe(origin, cookie, path)));
  const byPath = new Map(main.map((item) => [item.path, item]));

  const detailSpecs: Array<[string, string | null]> = [
    ["jobs", firstId(byPath.get("/api/v1/read/jobs")!)],
    ["clients", firstId(byPath.get("/api/v1/read/clients")!)],
    ["partners", firstId(byPath.get("/api/v1/read/partners")!)],
    ["candidates", firstId(byPath.get("/api/v1/read/candidates")!)],
  ];
  const details = await Promise.all(detailSpecs.map(async ([domain, id]) =>
    id ? probe(origin, cookie, "/api/v1/read/" + domain + "/" + encodeURIComponent(id)) : null
  ));

  const fallbackDetails = await Promise.all(
    ["jobs", "clients", "partners", "candidates"].map((domain) =>
      probe(origin, cookie, "/api/v1/read/" + domain + "/__MYC_ACCEPTANCE_MISSING__")
    )
  );
  const unknownRoute = await probe(origin, cookie, "/api/v1/read/__myc_acceptance_unknown__");

  const candidate = byPath.get("/api/v1/read/candidates")!;
  const candidateRows = Array.isArray(candidate.body?.data) ? candidate.body!.data as Array<Record<string, unknown>> : [];
  const recordReadinessCounts = candidateRows.reduce<Record<string, number>>((acc, row) => {
    const readiness = String(row.readiness ?? "UNKNOWN");
    acc[readiness] = (acc[readiness] ?? 0) + 1;
    return acc;
  }, {});
  const lifecycleReviewRows = candidateRows.filter((row) =>
    row.reason_code === "LIFECYCLE_EVIDENCE_REVIEW_REQUIRED"
    || (row.data && typeof row.data === "object" && (row.data as Record<string, unknown>).lifecycle_evidence_state === "REVIEW")
  );
  const lifecycleUnlockTrue = candidateRows.filter((row) =>
    row.data && typeof row.data === "object" && (row.data as Record<string, unknown>).lifecycle_action_unlock_allowed === true
  );

  const lifecycleCandidateId = lifecycleReviewRows.find((row) => typeof row.canonical_id === "string")?.canonical_id;
  const lifecycleDetail = typeof lifecycleCandidateId === "string"
    ? await probe(origin, cookie, "/api/v1/read/candidates/" + encodeURIComponent(lifecycleCandidateId))
    : null;

  const mainPass = main.every(contractPass);
  const detailPass = details.every((p) => p !== null && contractPass(p));
  const lifecycleDetailPass = lifecycleDetail === null || (
    contractPass(lifecycleDetail)
    && lifecycleDetail.body?.data !== null
    && lifecycleDetail.body?.data !== undefined
    && (lifecycleDetail.body.data as { reason_code?: string }).reason_code === "LIFECYCLE_EVIDENCE_REVIEW_REQUIRED"
  );
  const fallbackPass = fallbackDetails.every((p) =>
    p.http === 200
    && p.contract_version === "v1"
    && p.readiness === "NOT_READY"
    && p.reason_code === "RECORD_NOT_FOUND"
    && p.body?.data === null
    && /no-store/i.test(p.cache_control ?? "")
    && !p.pii_secret_leak_detected
  );
  const unknownPass = unknownRoute.http === 404
    && unknownRoute.contract_version === "v1"
    && unknownRoute.reason_code === "READ_ROUTE_NOT_FOUND"
    && /no-store/i.test(unknownRoute.cache_control ?? "")
    && !unknownRoute.pii_secret_leak_detected;

  const allProbes = [
    ...main,
    ...details.filter((p): p is Probe => p !== null),
    ...(lifecycleDetail ? [lifecycleDetail] : []),
    ...fallbackDetails,
    unknownRoute,
  ];
  const report = {
    generated_at: new Date().toISOString(),
    deployment: {
      vercel_url: process.env.VERCEL_URL ?? null,
      git_commit_sha: process.env.VERCEL_GIT_COMMIT_SHA ?? null,
      git_commit_ref: process.env.VERCEL_GIT_COMMIT_REF ?? null,
      environment: process.env.VERCEL_ENV ?? null,
    },
    live_http_only: true,
    main_matrix: main.map(sanitized),
    detail_matrix: details.filter((p): p is Probe => p !== null).map(sanitized),
    lifecycle_detail: lifecycleDetail ? sanitized(lifecycleDetail) : null,
    fallback_matrix: fallbackDetails.map(sanitized),
    unknown_route_fallback: sanitized(unknownRoute),
    candidate_checks: {
      endpoint_readiness: candidate.readiness,
      endpoint_reason_code: candidate.reason_code,
      candidate_inventory_completeness: candidate.body?.candidate_inventory_completeness ?? null,
      per_record_readiness_counts: recordReadinessCounts,
      lifecycle_review_count: lifecycleReviewRows.length,
      lifecycle_action_unlock_true_count: lifecycleUnlockTrue.length,
    },
    acceptance: {
      main_contracts_pass: mainPass,
      detail_contracts_pass: detailPass,
      lifecycle_guard_pass: lifecycleDetailPass && lifecycleUnlockTrue.length === 0,
      fallback_behavior_pass: fallbackPass && unknownPass,
      pii_secret_leak_pass: allProbes.every((p) => !p.pii_secret_leak_detected),
      all_live_http_checks_pass: mainPass && detailPass && lifecycleDetailPass && fallbackPass && unknownPass && lifecycleUnlockTrue.length === 0,
    },
  };

  return (
    <main style={{ fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", padding: 24, whiteSpace: "pre-wrap" }}>
      <h1>MYC Engineering Live Read Gate Acceptance</h1>
      <p>Preview-only · read-only · live HTTP probes · sanitized output</p>
      <script id="myc-read-gate-report" type="application/json" dangerouslySetInnerHTML={{ __html: JSON.stringify(report).replace(/</g, "\\u003c") }} />
      <pre>{JSON.stringify(report, null, 2)}</pre>
    </main>
  );
}
