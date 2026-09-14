export type DataHubDomain = "candidate" | "job" | "client" | "partner" | "dq" | "founderToday";

export type HeaderAliasSpec = Record<string, readonly string[]>;

export const DATA_HUB_HEADER_ALIASES: Record<DataHubDomain, HeaderAliasSpec> = {
  candidate: {
    canonical_id: ["Candidate ID", "candidate_id"],
    display_name: ["ชื่อ-นามสกุล", "ชื่อ นามสกุล", "Name", "Full Name"],
    nickname: ["ชื่อเล่น", "Nickname"],
    phone: ["โทรศัพท์", "เบอร์โทร", "Phone"],
    line: ["LINE", "Line ID"],
    province: ["จังหวัดต้นทาง", "จังหวัด", "Province"],
    current_location: ["ที่อยู่ปัจจุบัน/พื้นที่", "Current Location"],
    age: ["อายุ", "Age"],
    education: ["การศึกษา", "Education"],
    experience: ["ประสบการณ์หลัก", "Experience"],
    preferred_job: ["งานที่สนใจ", "Preferred Job"],
    expected_income: ["รายได้ที่คาดหวัง", "Expected Income"],
    shift_preference: ["กะที่รับได้", "Shift Preference"],
    relocation_ready: ["พร้อมย้าย?", "Ready to Relocate?"],
    ready_date: ["วันที่พร้อมเริ่ม", "Ready Date"],
    has_vehicle: ["มีรถ?", "Has Vehicle?"],
    dorm_needed: ["ต้องการหอ?", "Needs Dorm?"],
    dorm_budget: ["งบหอ/เดือน", "Dorm Budget"],
    documents_ready: ["เอกสารพร้อม?", "Documents Ready?"],
    medical_ready: ["ตรวจสุขภาพพร้อม?", "Medical Ready?"],
    source_type: ["Source", "แหล่งที่มา"],
    partner_id: ["Partner ID", "Sourcing Partner ID"],
    status: ["Status", "สถานะ"],
    last_contact: ["ติดต่อครั้งล่าสุด", "Last Contact"],
    next_action: ["Next Action", "งานถัดไป"],
    consent_status: ["Consent สมัครงาน", "Consent Status"],
    notes: ["หมายเหตุ", "Notes"],
    created_at: ["Created At", "สร้างเมื่อ"],
    updated_at: ["Updated At", "Last Updated"],
  },
  job: {
    canonical_id: ["Job ID", "job_id"],
    client_id: ["Client ID", "client_id"],
    company: ["บริษัท/สถานที่ทำงาน", "Company"],
    province: ["จังหวัด", "Province"],
    location: ["พื้นที่/อำเภอ", "Location"],
    position: ["ตำแหน่ง", "Position"],
    headcount: ["จำนวนรับ", "Headcount"],
    wage: ["ค่าแรง/เงินเดือน", "Wage", "Salary"],
    ot: ["OT"],
    shift: ["กะ", "Shift"],
    benefits: ["สวัสดิการ", "Benefits"],
    required_qualification: ["คุณสมบัติ", "Required Qualification"],
    documents: ["เอกสารที่ต้องใช้", "Documents"],
    medical_requirement: ["ตรวจสุขภาพ", "Medical Requirement"],
    dorm_available: ["มีหอ?", "Dorm Available?"],
    transport_available: ["มีรถรับส่ง?", "Transport Available?"],
    application_date: ["วันที่สมัคร/นัด", "Application Date"],
    start_date: ["วันที่เริ่มงาน", "Start Date"],
    milestone: ["Milestone Deal", "Milestone"],
    payment_term: ["Payment Term"],
    contact_person: ["ผู้ติดต่อ", "Contact Person"],
    status: ["Status", "สถานะ"],
    updated_at: ["Last Updated", "Updated At"],
  },
  client: {
    canonical_id: ["Client ID", "client_id"],
    client_type: ["ประเภท Client", "Client Type"],
    company_name: ["ชื่อบริษัท/Partner", "Company Name", "Client Name"],
    contact_person: ["ผู้ติดต่อ", "Contact Person"],
    phone: ["โทรศัพท์", "Phone"],
    line_email: ["LINE/Email", "LINE", "Email"],
    province: ["จังหวัด", "Province"],
    area: ["พื้นที่", "Area"],
    crm_status: ["CRM Status", "Status"],
    next_action: ["Next Action"],
    payment_term: ["Payment Term"],
    billing_cycle: ["Billing Cycle"],
    updated_at: ["Last Updated", "Updated At"],
    verification_status: ["Verification Status"],
  },
  partner: {
    canonical_id: ["Partner ID", "partner_id"],
    partner_name: ["ชื่อ Partner", "Partner Name"],
    phone: ["โทรศัพท์", "Phone"],
    line: ["LINE", "Line ID"],
    province: ["จังหวัด", "Province"],
    partner_type: ["ประเภท Partner", "Partner Type"],
    parent_partner_id: ["ผู้แนะนำ Partner ID", "Parent Partner ID"],
    started_at: ["วันที่เริ่ม", "Started At"],
    status: ["Status", "สถานะ"],
    updated_at: ["Updated At", "Last Updated"],
  },
  dq: {
    canonical_id: ["DQ Issue ID", "dq_issue_id"],
    detected_at: ["Detected At"],
    entity_type: ["Entity Type"],
    entity_id: ["Entity ID"],
    issue_type: ["Issue Type"],
    severity: ["Severity"],
    required_action: ["Required Action"],
    status: ["Status"],
    resolution: ["Resolution"],
    updated_at: ["Updated At"],
  },
  founderToday: {
    metric: ["KPI สำคัญ", "KPI", "Metric"],
    value: ["ค่า", "Value"],
    meaning: ["ความหมาย", "Meaning"],
  },
};

export const REQUIRED_HEADERS: Record<DataHubDomain, readonly string[]> = {
  candidate: ["canonical_id", "display_name", "status", "next_action"],
  job: ["canonical_id", "company", "position", "status"],
  client: ["canonical_id", "company_name", "crm_status"],
  partner: ["canonical_id", "partner_name", "status"],
  dq: ["canonical_id", "issue_type", "severity", "status"],
  founderToday: ["metric", "value", "meaning"],
};

const normalizeHeader = (value: string) => value.trim().replace(/\s+/g, " ").toLocaleLowerCase("th-TH");

export class MissingRequiredHeaderError extends Error {
  constructor(public readonly domain: DataHubDomain, public readonly fields: string[]) {
    super(`Missing required ${domain} header(s): ${fields.join(", ")}`);
  }
}

export function resolveHeaderMap(domain: DataHubDomain, headers: string[]) {
  const normalized = new Map(headers.map((header, index) => [normalizeHeader(header), index]));
  const aliases = DATA_HUB_HEADER_ALIASES[domain];
  const resolved: Record<string, number> = {};

  for (const [field, candidates] of Object.entries(aliases)) {
    const index = candidates
      .map((candidate) => normalized.get(normalizeHeader(candidate)))
      .find((candidate): candidate is number => candidate !== undefined);
    if (index !== undefined) resolved[field] = index;
  }

  const missing = REQUIRED_HEADERS[domain].filter((field) => resolved[field] === undefined);
  if (missing.length) throw new MissingRequiredHeaderError(domain, missing);
  return resolved;
}

export function mapDataHubRows(domain: DataHubDomain, rows: unknown[][]) {
  if (!rows.length) throw new MissingRequiredHeaderError(domain, REQUIRED_HEADERS[domain] as string[]);
  const headers = rows[0].map((value) => String(value ?? ""));
  const index = resolveHeaderMap(domain, headers);

  return rows.slice(1).filter((row) => row.some((value) => value !== "" && value != null)).map((row) => {
    const record: Record<string, unknown> = {};
    for (const [field, position] of Object.entries(index)) record[field] = row[position] ?? null;
    return record;
  });
}
