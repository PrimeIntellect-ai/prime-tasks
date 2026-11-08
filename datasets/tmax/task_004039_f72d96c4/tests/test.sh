#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import secrets
import time
import urllib.request

import pytest
import redis

REQUIRED_KEYS = {"id", "group", "probabilities", "value"}
INVALID_UNICODE_ESCAPE = re.compile(r'\\u(?![0-9a-fA-F]{4})')


def sanitize_and_parse(line):
    sanitized = INVALID_UNICODE_ESCAPE.sub('', line)
    try:
        return json.loads(sanitized, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
    except (json.JSONDecodeError, ValueError):
        return None


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def is_valid_record(obj):
    if not isinstance(obj, dict) or not REQUIRED_KEYS.issubset(obj):
        return False
    if not isinstance(obj["id"], int) or isinstance(obj["id"], bool):
        return False
    if not isinstance(obj["group"], str):
        return False
    probabilities = obj["probabilities"]
    if not isinstance(probabilities, list) or not probabilities:
        return False
    if not all(is_number(value) for value in probabilities):
        return False
    if not is_number(obj["value"]):
        return False
    if abs(sum(probabilities) - 1.0) > 1e-5:
        return False
    if obj["value"] < 0:
        return False
    return True


def read_lines(path):
    assert os.path.isfile(path), f"Missing {path}"
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read().splitlines()


def strict_json_load(value):
    return json.loads(value, parse_constant=lambda constant: (_ for _ in ()).throw(ValueError(constant)))


def expected_report(records):
    groups = {}
    for record in records:
        group = record["group"]
        groups.setdefault(group, [])
        if len(groups[group]) < 2:
            groups[group].append(record["id"])

    lines = ["<html><body>", "<h1>Sampled IDs</h1>", "<ul>"]
    for group in sorted(groups):
        ids = ", ".join(str(value) for value in groups[group])
        lines.append(f"<li>Group {group}: {ids}</li>")
    lines.extend(["</ul>", "</body></html>"])
    return "\n".join(lines)


def test_nginx_processing_serialization_sanitization_and_report():
    worker_path = "/workspace/worker.py"
    assert os.path.isfile(worker_path), f"Missing worker script {worker_path}"
    assert os.path.getsize(worker_path) > 0, "worker.py is empty"

    try:
        r = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
        r.ping()
    except redis.ConnectionError:
        pytest.fail("Redis is not running or not accessible on 127.0.0.1:6379")

    clean_lines = read_lines("/workspace/data/clean.jsonl")
    evil_lines = read_lines("/workspace/data/evil.jsonl")

    # Unpredictable records prevent a worker from passing by emitting the visible IDs.
    nonce = secrets.token_hex(6)
    base = secrets.randbelow(500_000_000) + 1_000_000_000
    group_a = f"HiddenA_{nonce}"
    group_b_raw = f"HiddenB_{nonce}\\u"
    group_b_clean = f"HiddenB_{nonce}"

    hidden_lines = [
        json.dumps({"id": base, "group": group_a, "probabilities": [0.125, 0.875], "value": 2.5}),
        json.dumps({"id": base + 1, "group": group_a, "probabilities": [0.333333, 0.666672], "value": 0.0}),
        json.dumps({"id": base + 2, "group": group_a, "probabilities": [1.0], "value": 7.25}),
        f'{{"id": {base + 3}, "group": "{group_b_raw}", "probabilities": [0.4, 0.6], "value": 4.0}}',
        f'{{"id": {base + 4}, "group": "{group_b_raw}", "probabilities": [0.1, 0.9], "value": 5.0}}',
        # Invalid mathematical records.
        json.dumps({"id": base + 5, "group": group_a, "probabilities": [0.4, 0.7], "value": 1.0}),
        json.dumps({"id": base + 6, "group": group_a, "probabilities": [0.5, 0.5], "value": -0.01}),
        # Invalid schema records.
        json.dumps({"id": str(base + 7), "group": group_a, "probabilities": [0.5, 0.5], "value": 1.0}),
        json.dumps({"id": base + 8, "group": 123, "probabilities": [0.5, 0.5], "value": 1.0}),
        json.dumps({"id": base + 9, "group": group_a, "probabilities": "not-a-list", "value": 1.0}),
        json.dumps({"id": base + 10, "group": group_a, "probabilities": [0.5, "0.5"], "value": 1.0}),
        json.dumps({"id": base + 11, "group": group_a, "probabilities": [0.5, 0.5]}),
        json.dumps({"id": True, "group": group_a, "probabilities": [0.5, 0.5], "value": 1.0}),
    ]

    all_lines = clean_lines + evil_lines + hidden_lines
    expected_records = []
    for line in all_lines:
        obj = sanitize_and_parse(line)
        if is_valid_record(obj):
            expected_records.append(obj)

    # Preserve the original clean-corpus assertion and correct the evil-corpus
    # expectation: mathematically valid records survive after sanitization.
    clean_expected = [sanitize_and_parse(line) for line in clean_lines]
    assert all(is_valid_record(obj) for obj in clean_expected), "clean.jsonl contains an invalid record"
    expected_ids = [obj["id"] for obj in expected_records]
    assert base in expected_ids
    assert base + 3 in expected_ids and next(obj for obj in expected_records if obj["id"] == base + 3)["group"] == group_b_clean
    assert base + 5 not in expected_ids and base + 6 not in expected_ids

    r.delete("raw_data")
    r.delete("clean_data")

    for line in all_lines:
        request = urllib.request.Request(
            "http://127.0.0.1:8080/ingest",
            data=line.encode("utf-8"),
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=2) as response:
                assert response.status in (200, 201, 202, 204), f"Unexpected status: {response.status}"
        except Exception as exc:
            pytest.fail(
                "Failed to POST to Nginx at http://127.0.0.1:8080/ingest: "
                f"{exc}. Is Nginx and Flask configured and running?"
            )

    wanted_report = expected_report(expected_records)
    deadline = time.time() + 20
    while time.time() < deadline:
        output_count = r.llen("clean_data")
        raw_count = r.llen("raw_data")
        report_matches = False
        if os.path.isfile("/workspace/report.html"):
            with open("/workspace/report.html", "r", encoding="utf-8") as handle:
                report_matches = handle.read() == wanted_report
        if raw_count == 0 and output_count >= len(expected_records) and report_matches:
            break
        time.sleep(0.1)

    assert r.llen("raw_data") == 0, "Worker did not process all raw_data in time. Is worker.py running?"

    clean_data_raw = r.lrange("clean_data", 0, -1)
    assert len(clean_data_raw) == len(expected_records), (
        f"Expected exactly {len(expected_records)} valid outputs, got {len(clean_data_raw)}; "
        "records were fabricated, duplicated, or incorrectly accepted/rejected"
    )

    actual_records = []
    for index, item in enumerate(clean_data_raw):
        try:
            parsed = strict_json_load(item)
        except Exception as exc:
            pytest.fail(f"clean_data item {index} is not strict valid JSON: {exc}")
        assert is_valid_record(parsed), f"clean_data item {index} does not have the required valid schema: {parsed!r}"
        actual_records.append(parsed)

    assert actual_records == expected_records, (
        "clean_data must contain exactly the sanitized valid records, with all schema values preserved "
        "and in input order"
    )

    clean_ids_expected = {obj["id"] for obj in clean_expected}
    actual_ids = {obj["id"] for obj in actual_records}
    missing_clean = clean_ids_expected - actual_ids
    assert not missing_clean, f"{len(missing_clean)} clean records were modified or rejected. Missing IDs: {missing_clean}"

    invalid_evil_ids = set()
    valid_evil_ids = set()
    for line in evil_lines:
        obj = sanitize_and_parse(line)
        match = re.search(r'"id"\s*:\s*(\d+)', line)
        if is_valid_record(obj):
            valid_evil_ids.add(obj["id"])
        elif match:
            invalid_evil_ids.add(int(match.group(1)))
    assert valid_evil_ids.issubset(actual_ids), f"Valid sanitized evil records were rejected: {valid_evil_ids - actual_ids}"
    assert not invalid_evil_ids.intersection(actual_ids), f"Invalid evil records bypassed validation: {invalid_evil_ids.intersection(actual_ids)}"

    report_path = "/workspace/report.html"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist"
    with open(report_path, "r", encoding="utf-8") as handle:
        actual_report = handle.read()
    assert actual_report == wanted_report, (
        "report.html does not precisely contain the alphabetically sorted first two valid IDs per group.\n"
        f"Expected:\n{wanted_report}\nActual:\n{actual_report}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
