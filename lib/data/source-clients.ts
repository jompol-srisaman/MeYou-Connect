import { createSign } from "node:crypto";

export const DATA_HUB_SPREADSHEET_ID = "1o52Vpri7toZDviODQ12tpOoLgCs7Z5cYMmUZMc0Jeoc";
export const SUPABASE_PROJECT_REF = "pgjmxdeafzogzsyawejs";

type GoogleServiceAccount = { client_email: string; private_key: string };

export class SourceReadError extends Error {
  constructor(
    public readonly reasonCode: string,
    message: string,
    public readonly sourceRef: string,
    public readonly status?: number,
  ) {
    super(message);
  }
}

const base64Url = (value: string | Buffer) =>
  Buffer.from(value).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

function parseServiceAccount(): GoogleServiceAccount | null {
  const raw = process.env.GOOGLE_SERVICE_ACCOUNT_JSON;
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as { client_email?: string; private_key?: string };
      if (parsed.client_email && parsed.private_key) return { client_email: parsed.client_email, private_key: parsed.private_key };
    } catch {
      throw new SourceReadError(
        "GOOGLE_DATA_HUB_AUTH_INVALID",
        "GOOGLE_SERVICE_ACCOUNT_JSON is not valid service-account JSON.",
        "MEYOU_CONNECT_MVP_DATA_HUB_V1",
      );
    }
  }

  const client_email = process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL;
  const private_key = process.env.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY?.replace(/\\n/g, "\n");
  if (client_email && private_key) return { client_email, private_key };
  return null;
}

async function googleAccessToken() {
  const explicitToken = process.env.GOOGLE_SHEETS_ACCESS_TOKEN;
  if (explicitToken) return explicitToken;

  const credentials = parseServiceAccount();
  if (!credentials) {
    throw new SourceReadError(
      "GOOGLE_DATA_HUB_AUTH_NOT_CONFIGURED",
      "Private Data Hub requires a server-side read identity. No Google read credential is configured in this runtime.",
      "MEYOU_CONNECT_MVP_DATA_HUB_V1",
    );
  }

  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64Url(JSON.stringify({
    iss: credentials.client_email,
    scope: "https://www.googleapis.com/auth/spreadsheets.readonly",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${payload}`;
  const signer = createSign("RSA-SHA256");
  signer.update(unsigned);
  signer.end();
  const assertion = `${unsigned}.${base64Url(signer.sign(credentials.private_key))}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
    cache: "no-store",
  });

  if (!response.ok) {
    throw new SourceReadError(
      "GOOGLE_DATA_HUB_AUTH_FAILED",
      `Google OAuth rejected the server-side read identity (${response.status}).`,
      "MEYOU_CONNECT_MVP_DATA_HUB_V1",
      response.status,
    );
  }

  const body = await response.json() as { access_token?: string };
  if (!body.access_token) {
    throw new SourceReadError(
      "GOOGLE_DATA_HUB_AUTH_FAILED",
      "Google OAuth response did not include an access token.",
      "MEYOU_CONNECT_MVP_DATA_HUB_V1",
    );
  }
  return body.access_token;
}

export async function readDataHubRange(sheetName: string, range: string) {
  const token = await googleAccessToken();
  const a1 = `${sheetName}!${range}`;
  const endpoint = `https://sheets.googleapis.com/v4/spreadsheets/${DATA_HUB_SPREADSHEET_ID}/values/${encodeURIComponent(a1)}?majorDimension=ROWS&valueRenderOption=FORMATTED_VALUE`;
  const observedAt = new Date().toISOString();
  const response = await fetch(endpoint, {
    headers: { authorization: `Bearer ${token}` },
    cache: "no-store",
  });

  if (!response.ok) {
    throw new SourceReadError(
      "GOOGLE_DATA_HUB_READ_FAILED",
      `Google Sheets read failed (${response.status}).`,
      `MEYOU_CONNECT_MVP_DATA_HUB_V1/${sheetName}`,
      response.status,
    );
  }

  const body = await response.json() as { values?: unknown[][] };
  return { rows: body.values ?? [], observedAt };
}

function supabaseServiceKey() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.MYC_SUPABASE_SERVICE_ROLE_KEY;
  if (!key) {
    throw new SourceReadError(
      "SUPABASE_SERVER_AUTH_NOT_CONFIGURED",
      "Supabase technical reads require a server-only service credential in this runtime.",
      `supabase:${SUPABASE_PROJECT_REF}`,
    );
  }
  return key;
}

export async function readSupabaseOps<T>(resource: string, query: string): Promise<{ data: T; observedAt: string }> {
  const key = supabaseServiceKey();
  const url = process.env.SUPABASE_URL ?? `https://${SUPABASE_PROJECT_REF}.supabase.co`;
  const observedAt = new Date().toISOString();
  const response = await fetch(`${url}/rest/v1/${resource}?${query}`, {
    headers: {
      apikey: key,
      authorization: `Bearer ${key}`,
      "accept-profile": "ops",
      accept: "application/json",
    },
    cache: "no-store",
  });

  if (!response.ok) {
    const detail = (await response.text()).slice(0, 240);
    throw new SourceReadError(
      "SUPABASE_TECHNICAL_READ_FAILED",
      `Supabase ops read failed for ${resource} (${response.status})${detail ? `: ${detail}` : ""}`,
      `ops.${resource}`,
      response.status,
    );
  }

  return { data: await response.json() as T, observedAt };
}

export function serverAuthReadiness() {
  const googleConfigured = Boolean(
    process.env.GOOGLE_SHEETS_ACCESS_TOKEN ||
    process.env.GOOGLE_SERVICE_ACCOUNT_JSON ||
    (process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL && process.env.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY),
  );
  const supabaseConfigured = Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.MYC_SUPABASE_SERVICE_ROLE_KEY);
  return { googleConfigured, supabaseConfigured };
}
