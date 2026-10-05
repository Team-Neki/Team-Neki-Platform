"""Lambda handler for ga4-daily-report aggregation ingestion.

See ../../docs/lld/aggregation.md for the contract.
"""

from __future__ import annotations

import json
import logging
import os
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import boto3
from jsonschema import Draft7Validator

LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
logger = logging.getLogger()
logger.setLevel(LOG_LEVEL)

S3_BUCKET = os.environ["S3_BUCKET"]
S3_PREFIX = os.environ.get("S3_PREFIX", "aggregation")
REPORT_DATE_MAX_AGE_DAYS = int(os.environ.get("REPORT_DATE_MAX_AGE_DAYS", "7"))

KST = timezone(timedelta(hours=9))

_SCHEMA_PATH = Path(__file__).parent / "schemas" / "ga4-daily-report.v1.json"
with _SCHEMA_PATH.open(encoding="utf-8") as _f:
    SCHEMA = json.load(_f)
_VALIDATOR = Draft7Validator(SCHEMA)

s3 = boto3.client("s3")


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    start = time.monotonic()
    request_id = getattr(context, "aws_request_id", "unknown")
    log_base: dict[str, Any] = {"request_id": request_id}
    _log("INFO", {**log_base, "stage": "request_received"})

    content_type = _get_header(event, "content-type")
    if "application/json" not in content_type.lower():
        return _error(
            400,
            "INVALID_JSON",
            "Content-Type must be application/json",
            {"received": content_type},
            log_base,
            start,
        )

    try:
        payload = json.loads(event.get("body") or "")
    except json.JSONDecodeError as exc:
        return _error(
            400,
            "INVALID_JSON",
            "Invalid JSON body",
            {"reason": str(exc)},
            log_base,
            start,
        )

    schema_errors = sorted(
        _VALIDATOR.iter_errors(payload),
        key=lambda e: list(e.absolute_path),
    )
    if schema_errors:
        first = schema_errors[0]
        field = ".".join(str(p) for p in first.absolute_path) or "(root)"
        return _error(
            400,
            "VALIDATION_ERROR",
            "Schema validation failed",
            {"field": field, "reason": first.message},
            log_base,
            start,
        )

    schema_version = payload["schema_version"]
    if not schema_version.startswith("1."):
        return _error(
            400,
            "UNSUPPORTED_SCHEMA_VERSION",
            "Unsupported schema_version major",
            {"schema_version": schema_version, "supported_major": "1"},
            log_base,
            start,
        )

    report_date_str = payload["report_date"]
    try:
        report_date = date.fromisoformat(report_date_str)
    except ValueError:
        return _error(
            400,
            "VALIDATION_ERROR",
            "Invalid report_date format",
            {"field": "report_date", "reason": "must be YYYY-MM-DD"},
            log_base,
            start,
        )

    today_kst = datetime.now(KST).date()
    min_date = today_kst - timedelta(days=REPORT_DATE_MAX_AGE_DAYS)
    if report_date < min_date or report_date > today_kst:
        return _error(
            400,
            "DATE_OUT_OF_RANGE",
            "report_date is outside allowed range",
            {
                "report_date": report_date_str,
                "min": min_date.isoformat(),
                "max": today_kst.isoformat(),
            },
            log_base,
            start,
        )

    _log(
        "INFO",
        {
            **log_base,
            "stage": "validation_passed",
            "report_date": report_date_str,
            "schema_version": schema_version,
        },
    )

    object_key = _build_s3_key(report_date)
    try:
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=object_key,
            Body=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            ContentType="application/json; charset=utf-8",
            Metadata={
                "schema-version": schema_version,
                "report-type": payload["report_type"],
                "generated-at": payload["generated_at"],
            },
        )
    except Exception:
        logger.exception("S3 PutObject failed")
        return _error(
            500,
            "STORAGE_ERROR",
            "Failed to store payload",
            None,
            log_base,
            start,
            level="ERROR",
            stage="s3_put_failed",
        )

    duration_ms = int((time.monotonic() - start) * 1000)
    _log(
        "INFO",
        {
            **log_base,
            "stage": "s3_put_success",
            "object_key": object_key,
            "report_date": report_date_str,
            "duration_ms": duration_ms,
        },
    )

    return _response(
        200,
        {
            "status": "stored",
            "object_key": object_key,
            "report_date": report_date_str,
        },
    )


def _build_s3_key(report_date: date) -> str:
    return (
        f"{S3_PREFIX}/year={report_date.year:04d}"
        f"/month={report_date.month:02d}"
        f"/day={report_date.day:02d}"
        f"/ga4-daily-report.json"
    )


def _get_header(event: dict[str, Any], name: str) -> str:
    headers = event.get("headers") or {}
    lowered = {k.lower(): v for k, v in headers.items()}
    return lowered.get(name.lower(), "") or ""


def _error(
    status_code: int,
    code: str,
    message: str,
    details: dict[str, Any] | None,
    log_base: dict[str, Any],
    start: float,
    *,
    level: str = "WARNING",
    stage: str = "validation_failed",
) -> dict[str, Any]:
    duration_ms = int((time.monotonic() - start) * 1000)
    _log(level, {**log_base, "stage": stage, "code": code, "duration_ms": duration_ms})
    body: dict[str, Any] = {"error": {"code": code, "message": message}}
    if details is not None:
        body["error"]["details"] = details
    return _response(status_code, body)


def _response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json; charset=utf-8"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def _log(level: str, fields: dict[str, Any]) -> None:
    record = {"level": level, **fields}
    msg = json.dumps(record, ensure_ascii=False)
    if level == "ERROR":
        logger.error(msg)
    elif level == "WARNING":
        logger.warning(msg)
    else:
        logger.info(msg)
