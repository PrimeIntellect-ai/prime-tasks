#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess
import tempfile

import pytest

EXECUTABLE = "/home/user/router_utility/build/request_validator"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"

ROUTES = {
    "/api/v1/users": (20, {"id": "42", "format": "json"}),
    "/api/v1/billing": (5, {"invoice_id": "INV123"}),
    "/api/v2/data": (50, {"query": "alpha", "limit": "10"}),
}


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "request_validator is not a compiled ELF executable"


def run_executable(target_dir):
    result = subprocess.run(
        [EXECUTABLE, target_dir],
        capture_output=True,
        text=True,
        timeout=15
    )
    assert result.returncode == 0, (
        f"Executable failed with return code {result.returncode}\n"
        f"Stderr: {result.stderr}"
    )
    return result.stdout


def test_clean_corpus():
    stdout = run_executable(CLEAN_CORPUS)
    lines = stdout.strip().split('\n')

    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if f.endswith('.json')]

    # We expect ACCEPT for all clean files.
    rejected = []
    for line in lines:
        if not line.strip():
            continue
        if "REJECT" in line.upper():
            rejected.append(line)

    if rejected:
        pytest.fail(f"{len(rejected)} of {len(clean_files)} clean requests were incorrectly REJECTED.\nSample: {rejected[:5]}")

    # Also verify that ACCEPT is present
    accepts = [line for line in lines if "ACCEPT" in line.upper()]
    assert len(accepts) > 0, "No ACCEPT found in clean corpus output."


def test_evil_corpus():
    stdout = run_executable(EVIL_CORPUS)
    lines = stdout.strip().split('\n')

    evil_files = [f for f in os.listdir(EVIL_CORPUS) if f.endswith('.json')]

    # We expect REJECT for all evil files.
    accepted = []
    for line in lines:
        if not line.strip():
            continue
        if "ACCEPT" in line.upper():
            accepted.append(line)

    if accepted:
        pytest.fail(f"{len(accepted)} of {len(evil_files)} evil requests bypassed validation and were ACCEPTED.\nSample: {accepted[:5]}")

    # Also verify that REJECT is present
    rejects = [line for line in lines if "REJECT" in line.upper()]
    assert len(rejects) > 0, "No REJECT found in evil corpus output."


def status_rows(stdout):
    """Return one exact ACCEPT/REJECT status for each CSV request row."""
    statuses = []
    for row in csv.reader(stdout.splitlines()):
        found = [cell.strip().upper() for cell in row
                 if cell.strip().upper() in ("ACCEPT", "REJECT")]
        if found:
            assert len(found) == 1, f"Ambiguous CSV status row: {row!r}"
            statuses.append(found[0])
    return statuses


def write_request(directory, name, route, params, timestamp):
    with open(os.path.join(directory, name), "w", encoding="utf-8") as f:
        json.dump({"route": route, "params": params, "timestamp": timestamp}, f)


def run_cases(cases):
    # The random directory name deliberately contains neither 'clean' nor 'evil'.
    with tempfile.TemporaryDirectory(prefix="router_eval_") as directory:
        for index, case in enumerate(cases):
            write_request(directory, f"case_{index:04d}.json", **case)
        stdout = run_executable(directory)
        statuses = status_rows(stdout)
        assert len(statuses) == len(cases), (
            f"Expected exactly one CSV result per JSON request; got {len(statuses)} "
            f"statuses for {len(cases)} files. Output:\n{stdout}"
        )
        return statuses


@pytest.mark.parametrize("route,params", [
    (route, params) for route, (_, params) in ROUTES.items()
])
def test_generated_valid_requests(route, params):
    statuses = run_cases([{
        "route": route,
        "params": params,
        "timestamp": 1723456789,
    }])
    assert statuses == ["ACCEPT"]


@pytest.mark.parametrize("case", [
    {
        "route": "/api/v1/users",
        "params": {"id": "../secret", "format": "json"},
        "timestamp": 1723456789,
    },
    {
        "route": "/api/v1/billing",
        "params": {"invoice_id": "../../etc/passwd"},
        "timestamp": 1723456789,
    },
    {
        "route": "/api/v2/data",
        "params": {"query": "<script>", "limit": "10"},
        "timestamp": 1723456789,
    },
    {
        "route": "/api/v1/users",
        "params": {"id": "42", "format": "json", "admin": "true"},
        "timestamp": 1723456789,
    },
    {
        "route": "/api/v1/unknown",
        "params": {"id": "42"},
        "timestamp": 1723456789,
    },
    {
        "route": "/api/v1/../billing",
        "params": {"invoice_id": "INV123"},
        "timestamp": 1723456789,
    },
])
def test_generated_invalid_requests(case):
    assert run_cases([case]) == ["REJECT"]


@pytest.mark.parametrize("route", list(ROUTES))
def test_route_specific_rate_limits_and_minute_reset(route):
    limit, params = ROUTES[route]
    base = 1800000000

    # Use the same corpus size for every route, so behavior cannot be selected
    # merely from the number of files. Fifty-two requests occur at one instant;
    # one more occurs in a later minute and must be accepted after the reset.
    cases = [
        {"route": route, "params": params, "timestamp": base}
        for _ in range(52)
    ]
    cases.append({"route": route, "params": params, "timestamp": base + 120})

    statuses = run_cases(cases)
    assert statuses.count("ACCEPT") == limit + 1, (
        f"Wrong rate-limit behavior for {route}: {statuses.count('ACCEPT')} accepts"
    )
    assert statuses.count("REJECT") == 52 - limit, (
        f"Wrong rate-limit behavior for {route}: {statuses.count('REJECT')} rejects"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
