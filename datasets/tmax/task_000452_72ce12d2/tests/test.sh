#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

RELEASE_DIR = "/home/user/release"
SERVICES_DIR = os.path.join(RELEASE_DIR, "services")
BUILD_SCRIPT = os.path.join(RELEASE_DIR, "build_release.sh")
LOCKFILE = os.path.join(RELEASE_DIR, "lockfile.txt")
WAF_ROUTER = os.path.join(RELEASE_DIR, "waf_router.sh")


def test_build_script_exists_and_executable():
    assert os.path.isfile(BUILD_SCRIPT), f"Build script not found at {BUILD_SCRIPT}"
    st = os.stat(BUILD_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Build script {BUILD_SCRIPT} is not executable"
    with open(BUILD_SCRIPT, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace")
    assert first_line.startswith("#!") and "bash" in first_line, "Build script must be a Bash executable"


def test_build_script_executes_and_generates_outputs():
    for artifact in (LOCKFILE, WAF_ROUTER):
        try:
            os.unlink(artifact)
        except FileNotFoundError:
            pass
    result = subprocess.run(
        [BUILD_SCRIPT], cwd=RELEASE_DIR, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"Build script failed with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_lockfile_content():
    assert os.path.isfile(LOCKFILE), f"Lockfile not found at {LOCKFILE}. Did the build script run?"
    with open(LOCKFILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = [
        "auth=1.0.0",
        "db=1.0.0",
        "logger=1.0.0"
    ]
    assert lines == expected, f"Lockfile content incorrect. Expected {expected}, got {lines}"


def test_waf_router_exists_and_executable():
    assert os.path.isfile(WAF_ROUTER), f"WAF router script not found at {WAF_ROUTER}"
    st = os.stat(WAF_ROUTER)
    assert bool(st.st_mode & stat.S_IXUSR), f"WAF router script {WAF_ROUTER} is not executable"


def run_waf_router(method, path, query_string=""):
    result = subprocess.run(
        [WAF_ROUTER, method, path, query_string],
        capture_output=True,
        text=True
    )
    return result.stdout.strip()


@pytest.mark.parametrize("method, path, query_string, expected", [
    ("POST", "/login", "username=admin&password=123", "ROUTED_TO: auth"),
    ("POST", "/login", "username=admin&password=123&token=abc", "ROUTED_TO: auth"),
    ("POST", "/login", "username=admin&password=123&mfa=1", "403 FORBIDDEN"),
    ("GET", "/data", "limit=10", "ROUTED_TO: db"),
    ("POST", "/data", "query=select&limit=5", "ROUTED_TO: db"),
    ("GET", "/data", "limit=10&offset=5", "403 FORBIDDEN"),
    ("GET", "/logs", "", "ROUTED_TO: logger"),
    ("GET", "/logs", "date=2023-10-01", "ROUTED_TO: logger"),
    ("PUT", "/logs", "", "403 FORBIDDEN"),
    ("GET", "/unknown", "", "403 FORBIDDEN"),
    ("POST", "/login", "unknown_param=1", "403 FORBIDDEN"),
])
def test_waf_router_behavior(method, path, query_string, expected):
    output = run_waf_router(method, path, query_string)
    assert output == expected, f"WAF router failed for {method} {path} '{query_string}'. Expected '{expected}', got '{output}'"


def test_build_resolves_runtime_service_data_and_regenerates_router():
    token = secrets.token_hex(8)
    api = f"api_{token}"
    data = f"data_{token}"
    utility = f"utility_{token}"
    api_path = f"/v/{token}/session"
    data_path = f"/v/{token}/records"
    utility_path = f"/v/{token}/events"
    user_key = f"user_{token}"
    signature_key = f"sig_{token}"
    mfa_key = f"mfa_{token}"
    query_key = f"query_{token}"
    limit_key = f"limit_{token}"
    offset_key = f"offset_{token}"
    date_key = f"date_{token}"

    fixtures = [
        {
            "name": api,
            "version": "1.2.3",
            "requires": {data: ">= 1.9.0"},
            "routes": [{
                "path": api_path,
                "methods": ["POST"],
                "allowed_params": [user_key, signature_key]
            }]
        },
        {
            "name": api,
            "version": "2.7.1",
            "requires": {data: ">= 2.0.0"},
            "routes": [{
                "path": api_path,
                "methods": ["POST"],
                "allowed_params": [user_key, signature_key, mfa_key]
            }]
        },
        {
            "name": data,
            "version": "1.10.0",
            "requires": {utility: ">= 3.9.9"},
            "routes": [{
                "path": data_path,
                "methods": ["GET", "POST"],
                "allowed_params": [query_key, limit_key]
            }]
        },
        {
            "name": data,
            "version": "2.1.0",
            "requires": {api: ">= 2.0.0"},
            "routes": [{
                "path": data_path,
                "methods": ["GET", "POST"],
                "allowed_params": [query_key, limit_key, offset_key]
            }]
        },
        {
            "name": utility,
            "version": "3.10.2",
            "requires": {},
            "routes": [{
                "path": utility_path,
                "methods": ["GET"],
                "allowed_params": [date_key]
            }]
        }
    ]

    services = Path(SERVICES_DIR)
    for old_file in services.glob("*.json"):
        old_file.unlink()
    for index, fixture in enumerate(fixtures):
        with open(services / f"runtime_{token}_{index}.json", "w") as f:
            json.dump(fixture, f)

    for artifact in (LOCKFILE, WAF_ROUTER):
        try:
            os.unlink(artifact)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [BUILD_SCRIPT], cwd=RELEASE_DIR, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"Build script failed on runtime fixtures. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    assert os.path.isfile(LOCKFILE), "Build did not regenerate lockfile.txt"
    with open(LOCKFILE, "r") as f:
        actual_lock = [line.strip() for line in f if line.strip()]
    expected_lock = sorted([
        f"{api}=1.2.3",
        f"{data}=1.10.0",
        f"{utility}=3.10.2",
    ])
    assert actual_lock == expected_lock, (
        f"Runtime dependency resolution incorrect. Expected {expected_lock}, got {actual_lock}"
    )

    assert os.path.isfile(WAF_ROUTER), "Build did not regenerate waf_router.sh"
    assert os.stat(WAF_ROUTER).st_mode & stat.S_IXUSR, "Regenerated router is not executable"

    cases = [
        ("POST", api_path, f"{user_key}=alice&{signature_key}=abc", f"ROUTED_TO: {api}"),
        ("POST", api_path, "", f"ROUTED_TO: {api}"),
        ("POST", api_path, f"{mfa_key}=1", "403 FORBIDDEN"),
        ("GET", api_path, "", "403 FORBIDDEN"),
        ("GET", data_path, f"{limit_key}=10", f"ROUTED_TO: {data}"),
        ("POST", data_path, f"{query_key}=x&{limit_key}=5", f"ROUTED_TO: {data}"),
        ("GET", data_path, f"{offset_key}=5", "403 FORBIDDEN"),
        ("GET", utility_path, "", f"ROUTED_TO: {utility}"),
        ("GET", utility_path, f"{date_key}=today", f"ROUTED_TO: {utility}"),
        ("POST", utility_path, "", "403 FORBIDDEN"),
        ("GET", f"/v/{token}/missing", "", "403 FORBIDDEN"),
    ]
    for method, path, query, expected in cases:
        routed = subprocess.run(
            [WAF_ROUTER, method, path, query],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert routed.returncode == 0, f"Router exited with {routed.returncode} for {method} {path}"
        assert routed.stdout.strip() == expected, (
            f"Runtime router failed for {method} {path} {query!r}: "
            f"expected {expected!r}, got {routed.stdout.strip()!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
