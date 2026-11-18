#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess

import pytest

SCRIPT_PATH = "/home/user/solver.sh"
CSV_PATH = "/home/user/libs.csv"


def run_solver(http_request: str) -> str:
    result = subprocess.run(
        [SCRIPT_PATH],
        input=http_request,
        text=True,
        capture_output=True,
        check=False,
    )
    return result.stdout


def parse_http_response(stdout: str):
    stdout = stdout.replace("\r\n", "\n")
    parts = stdout.split("\n\n", 1)

    headers_part = parts[0]
    body = parts[1] if len(parts) > 1 else ""

    header_lines = headers_part.split("\n")
    status_line = header_lines[0] if header_lines else ""
    headers = [line.lower() for line in header_lines[1:]]

    return status_line, headers, body.strip()


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_valid_200_ok():
    req = "GET /api/v1/fit?libs=math,crypto,net&max=200 HTTP/1.1\r\nHost: localhost\r\n\r\n"
    stdout = run_solver(req)
    status_line, headers, body = parse_http_response(stdout)

    assert "200 OK" in status_line, f"Expected 200 OK, got: {status_line}"
    assert any("content-type: application/json" in h for h in headers), "Missing or incorrect Content-Type header."

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        pytest.fail(f"Could not parse JSON body: {body}")

    assert data.get("status") == "ok", "Expected status 'ok'"
    assert data.get("total") == 100, f"Expected total 100, got {data.get('total')}"


def test_valid_400_bad_request():
    req = "GET /api/v1/fit?libs=db,ui,core&max=150 HTTP/1.1\r\nHost: localhost\r\n\r\n"
    stdout = run_solver(req)
    status_line, headers, body = parse_http_response(stdout)

    assert "400 Bad Request" in status_line, f"Expected 400 Bad Request, got: {status_line}"
    assert any("content-type: application/json" in h for h in headers), "Missing or incorrect Content-Type header."

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        pytest.fail(f"Could not parse JSON body: {body}")

    assert data.get("error") == "exceeds capacity", "Expected error 'exceeds capacity'"
    assert data.get("total") == 250, f"Expected total 250, got {data.get('total')}"
    assert data.get("max") == 150, f"Expected max 150, got {data.get('max')}"


def test_404_not_found():
    req = "GET /api/v1/other?libs=math&max=200 HTTP/1.1\r\nHost: localhost\r\n\r\n"
    stdout = run_solver(req)
    status_line, headers, body = parse_http_response(stdout)

    assert "404 Not Found" in status_line, f"Expected 404 Not Found, got: {status_line}"
    assert body == "", "Expected empty body for 404 Not Found"


def test_missing_libraries_ignored():
    req = "GET /api/v1/fit?libs=core,nonexistent,net&max=100 HTTP/1.1\r\nHost: localhost\r\n\r\n"
    stdout = run_solver(req)
    status_line, headers, body = parse_http_response(stdout)

    assert "200 OK" in status_line, f"Expected 200 OK, got: {status_line}"

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        pytest.fail(f"Could not parse JSON body: {body}")

    assert data.get("status") == "ok", "Expected status 'ok'"
    assert data.get("total") == 75, f"Expected total 75, got {data.get('total')}"


def assert_exact_response(libs, maximum, total):
    request = (
        f"GET /api/v1/fit?libs={','.join(libs)}&max={maximum} HTTP/1.1\r\n"
        "Host: localhost\r\n\r\n"
    )
    status_line, headers, body = parse_http_response(run_solver(request))
    assert any(h == "content-type: application/json" for h in headers), (
        "Missing or incorrect Content-Type header."
    )

    if total > maximum:
        assert status_line == "HTTP/1.1 400 Bad Request"
        assert body == f'{{"error": "exceeds capacity", "total": {total}, "max": {maximum}}}'
    else:
        assert status_line == "HTTP/1.1 200 OK"
        assert body == f'{{"status": "ok", "total": {total}}}'


def test_dynamic_csv_lookup_summation_and_constraints():
    original_csv = open(CSV_PATH, "rb").read()
    token = secrets.token_hex(8)
    entries = [
        (f"dyn{token}{i}", 11 + secrets.randbelow(180))
        for i in range(7)
    ]
    unknown = f"missing{secrets.token_hex(12)}"

    try:
        with open(CSV_PATH, "w", encoding="utf-8", newline="") as csv_file:
            for name, size in entries:
                csv_file.write(f"{name},{size}\n")

        all_names = [name for name, _ in entries]
        all_total = sum(size for _, size in entries)
        assert_exact_response(all_names, all_total, all_total)

        selected = [entries[1], entries[3], entries[6]]
        selected_names = [name for name, _ in selected]
        selected_total = sum(size for _, size in selected)
        assert_exact_response(selected_names, selected_total - 1, selected_total)

        mixed = [unknown, entries[0][0], entries[5][0]]
        mixed_total = entries[0][1] + entries[5][1]
        assert_exact_response(mixed, mixed_total + 17, mixed_total)

        assert_exact_response([unknown], 0, 0)
    finally:
        with open(CSV_PATH, "wb") as csv_file:
            csv_file.write(original_csv)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
