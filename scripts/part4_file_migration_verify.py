#!/usr/bin/env python3
"""MeYou Connect Part 4 file-migration verification utility.

TEST/LOCAL only. This utility does not call Google Drive, Supabase Storage, R2,
or any network API. It verifies a local/exported manifest after a controlled
copy step and produces deterministic SHA-256 evidence.

Manifest JSON format:
[
  {
    "file_id": "MYC-FILE-000003",
    "evidence_id": "MYC-EV-000001",
    "legacy_drive_id": "optional-drive-id",
    "source_path": "/local/export/source.bin",
    "target_path": "/local/export/target.bin",
    "expected_sha256": "optional-64-char-hex"
  }
]

Exit codes:
0 = every item verified
1 = one or more verification failures
2 = invalid input/manifest
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

CHUNK_SIZE = 1024 * 1024


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(CHUNK_SIZE)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def valid_hex_digest(value: str) -> bool:
    if len(value) != 64:
        return False
    try:
        int(value, 16)
    except ValueError:
        return False
    return True


def verify_item(item: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "file_id": item.get("file_id"),
        "evidence_id": item.get("evidence_id"),
        "legacy_drive_id": item.get("legacy_drive_id"),
        "status": "FAIL",
        "issues": [],
    }

    source_raw = item.get("source_path")
    target_raw = item.get("target_path")
    if not isinstance(source_raw, str) or not source_raw:
        result["issues"].append("SOURCE_PATH_REQUIRED")
        return result
    if not isinstance(target_raw, str) or not target_raw:
        result["issues"].append("TARGET_PATH_REQUIRED")
        return result

    source = Path(source_raw)
    target = Path(target_raw)
    if not source.is_file():
        result["issues"].append("SOURCE_FILE_MISSING")
        return result
    if not target.is_file():
        result["issues"].append("TARGET_FILE_MISSING")
        return result

    source_hash = sha256_file(source)
    target_hash = sha256_file(target)
    result["source_sha256"] = source_hash
    result["target_sha256"] = target_hash
    result["source_size"] = source.stat().st_size
    result["target_size"] = target.stat().st_size

    if source_hash != target_hash:
        result["issues"].append("SOURCE_TARGET_SHA256_MISMATCH")
    if source.stat().st_size != target.stat().st_size:
        result["issues"].append("SOURCE_TARGET_SIZE_MISMATCH")

    expected = item.get("expected_sha256")
    if expected not in (None, ""):
        if not isinstance(expected, str) or not valid_hex_digest(expected.lower()):
            result["issues"].append("INVALID_EXPECTED_SHA256")
        elif source_hash != expected.lower():
            result["issues"].append("EXPECTED_SHA256_MISMATCH")

    if not result["issues"]:
        result["status"] = "PASS"
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify local file-migration copies with SHA-256.")
    parser.add_argument("manifest", type=Path, help="JSON manifest path")
    parser.add_argument("--report", type=Path, help="Optional JSON report output path")
    args = parser.parse_args()

    try:
        payload = json.loads(args.manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"Invalid manifest: {exc}", file=sys.stderr)
        return 2

    if not isinstance(payload, list):
        print("Manifest root must be a JSON array.", file=sys.stderr)
        return 2

    results = []
    for index, item in enumerate(payload, start=1):
        if not isinstance(item, dict):
            results.append({"row": index, "status": "FAIL", "issues": ["MANIFEST_ITEM_NOT_OBJECT"]})
            continue
        results.append(verify_item(item))

    passed = sum(1 for item in results if item.get("status") == "PASS")
    failed = len(results) - passed
    report = {
        "tool": "part4_file_migration_verify",
        "total": len(results),
        "passed": passed,
        "failed": failed,
        "status": "PASS" if failed == 0 else "FAIL",
        "results": results,
    }

    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    print(rendered)
    if args.report:
        args.report.write_text(rendered + "\n", encoding="utf-8")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
