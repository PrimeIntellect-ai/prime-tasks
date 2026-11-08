#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

SCRIPT = "/home/user/router.sh"
OUTPUT = Path("/home/user/routed.json")


def run_router(log_path, routes_path):
    OUTPUT.unlink(missing_ok=True)
    try:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", SCRIPT, str(log_path), str(routes_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("router.sh did not terminate within 10 seconds")

    assert result.returncode == 0, (
        f"router.sh exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert OUTPUT.is_file(), f"The output file {OUTPUT} was not created."

    try:
        with OUTPUT.open() as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The file {OUTPUT} does not contain valid JSON: {exc}")


def expected_output(log_lines, routes):
    parsed_routes = []
    for route in routes:
        match = re.fullmatch(r"([0-9]+)\.([0-9]+)\.([0-9]+)", route["version"])
        assert match is not None
        parsed_routes.append((route, tuple(map(int, match.groups()))))

    accepted_by_ip = {}
    result = []
    path_pattern = re.compile(r"^/api/([^/]+)/v([0-9]+)\.([0-9]+)\.([0-9]+)$")

    for line in log_lines:
        fields = line.split()
        if len(fields) != 4:
            continue
        timestamp_text, ip, method, path = fields
        if method != "GET":
            continue
        match = path_pattern.fullmatch(path)
        if match is None:
            continue

        timestamp = int(timestamp_text)
        service = match.group(1)
        requested = tuple(map(int, match.groups()[1:]))

        recent = [t for t in accepted_by_ip.get(ip, []) if timestamp - 4 <= t <= timestamp]
        if len(recent) >= 2:
            accepted_by_ip[ip] = recent
            continue
        recent.append(timestamp)
        accepted_by_ip[ip] = recent

        candidates = [
            (version, route)
            for route, version in parsed_routes
            if route["service"] == service
            and version[0] == requested[0]
            and version[1] <= requested[1]
            and version[2] <= requested[2]
        ]
        if not candidates:
            continue

        _, selected = max(candidates, key=lambda item: item[0])
        result.append({
            "timestamp": timestamp,
            "ip": ip,
            "service": service,
            "requested_version": ".".join(match.groups()[1:]),
            "routed_port": selected["port"],
        })

    return result


def test_router_script_exists_and_executable():
    script_path = "/home/user/router.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"The script {script_path} is not executable."

    content = Path(script_path).read_text(errors="replace")
    first_line = content.splitlines()[0] if content.splitlines() else ""
    assert re.fullmatch(r"#!\s*(?:/bin/bash|/usr/bin/bash|/usr/bin/env\s+bash)\s*", first_line), \
        "router.sh must be a Bash script with a Bash shebang."
    assert not re.search(r"(?i)(?:^|[^A-Za-z0-9_])(python(?:[0-9.]+)?|perl)(?:[^A-Za-z0-9_]|$)", content), \
        "router.sh may not invoke Python or Perl."

    run_router("/home/user/requests.log", "/home/user/routes.json")


def test_routed_json_exists():
    output_path = "/home/user/routed.json"
    assert os.path.isfile(output_path), f"The output file {output_path} was not created."


def test_routed_json_content():
    output_path = "/home/user/routed.json"
    assert os.path.isfile(output_path), f"The output file {output_path} was not created."

    with open(output_path, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_path} does not contain valid JSON.")

    expected_data = [
        {"timestamp": 1700000000, "ip": "10.0.0.1", "service": "auth", "requested_version": "1.2.5", "routed_port": 8081},
        {"timestamp": 1700000002, "ip": "10.0.0.1", "service": "auth", "requested_version": "1.3.5", "routed_port": 8082},
        {"timestamp": 1700000007, "ip": "10.0.0.1", "service": "auth", "requested_version": "1.2.0", "routed_port": 8081},
        {"timestamp": 1700000008, "ip": "192.168.1.5", "service": "payment", "requested_version": "1.1.4", "routed_port": 9090},
        {"timestamp": 1700000009, "ip": "192.168.1.5", "service": "payment", "requested_version": "1.1.6", "routed_port": 9091},
        {"timestamp": 1700000015, "ip": "10.0.0.1", "service": "auth", "requested_version": "2.1.0", "routed_port": 8083}
    ]

    assert isinstance(actual_data, list), f"The JSON in {output_path} should be an array."
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} routed requests, but got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, f"Mismatch at index {i}. Expected: {expected}, but got: {actual}"


def test_router_on_additional_fixtures():
    cases = [
        (
            [
                {"service": "alpha", "version": "1.0.9", "port": 7009},
                {"service": "alpha", "version": "1.1.0", "port": 7010},
                {"service": "alpha", "version": "1.1.2", "port": 7012},
                {"service": "alpha", "version": "1.2.0", "port": 7020},
                {"service": "alpha", "version": "2.0.0", "port": 7200},
                {"service": "beta", "version": "3.3.5", "port": 7335},
                {"service": "beta", "version": "3.4.6", "port": 7346},
            ],
            [
                "100 1.1.1.1 GET /api/alpha/v1.2.0",
                "101 1.1.1.2 GET /api/alpha/v1.1.1",
                "102 1.1.1.3 GET /api/alpha/v1.1.9",
                "103 1.1.1.4 GET /api/alpha/v2.0.0",
                "104 1.1.1.5 GET /api/beta/v3.4.5",
                "105 1.1.1.6 POST /api/alpha/v1.2.0",
                "106 1.1.1.7 GET /api/alpha/v1.2.0/extra",
                "107 1.1.1.8 GET /api/missing/v1.0.0",
            ],
        ),
        (
            [{"service": "clock", "version": "1.0.0", "port": 8100}],
            [
                "200 9.9.9.9 GET /api/clock/v1.0.0",
                "202 9.9.9.9 GET /api/clock/v1.0.0",
                "204 9.9.9.9 GET /api/clock/v1.0.0",
                "206 9.9.9.9 GET /api/clock/v1.0.0",
                "207 9.9.9.9 POST /api/clock/v1.0.0",
                "208 9.9.9.9 GET /api/clock/v1.0.0",
                "209 9.9.9.9 GET /api/clock/v1.0.0",
                "201 8.8.8.8 GET /api/clock/v1.0.0",
                "202 8.8.8.8 GET /api/clock/v1.0.0",
            ],
        ),
    ]

    with tempfile.TemporaryDirectory(prefix="router-tests-") as temp_dir:
        os.chmod(temp_dir, 0o755)
        for index, (routes, lines) in enumerate(cases):
            routes_path = Path(temp_dir) / f"routes-{index}.json"
            log_path = Path(temp_dir) / f"requests-{index}.log"
            routes_path.write_text(json.dumps(routes))
            log_path.write_text("\n".join(lines) + "\n")
            os.chmod(routes_path, 0o644)
            os.chmod(log_path, 0o644)

            actual = run_router(log_path, routes_path)
            expected = expected_output(lines, routes)
            assert isinstance(actual, list), "routed.json must contain a JSON array"
            assert actual == expected, (
                f"Incorrect result for additional fixture {index}. "
                f"Expected {expected!r}, got {actual!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
