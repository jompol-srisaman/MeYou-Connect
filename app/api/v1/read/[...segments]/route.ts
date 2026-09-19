import { NextResponse } from "next/server";
import { dispatchOfficialRead } from "@/lib/data/official-read";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ segments: string[] }> },
) {
  const { segments } = await params;
  const result = await dispatchOfficialRead(segments);
  const status = result.reason_code === "READ_ROUTE_NOT_FOUND" ? 404 : 200;
  return NextResponse.json(result, {
    status,
    headers: {
      "cache-control": "no-store, max-age=0",
      pragma: "no-cache",
      "x-myc-contract-version": "v1",
      "x-myc-readiness": result.readiness,
    },
  });
}
