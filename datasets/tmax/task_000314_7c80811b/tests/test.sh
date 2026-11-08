#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import io
import os
import random
import re
import stat
import subprocess
import sys
import tempfile
import time

import pytest

sys.path.insert(0, "/app/quotalogger-2.1")
try:
    from quotalogger.parser import calculate_quotas
except ImportError:
    calculate_quotas = None


def expected_total(path):
    total = 0
    with open(path, "r") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) == 3:
                total += int(parts[2])
    return total


def unit_directives(path):
    section = None
    directives = {}
    with open(path, "r") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith(("#", ";")):
                continue
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1]
                continue
            if section == "Unit" and "=" in line:
                key, value = line.split("=", 1)
                directives.setdefault(key.strip(), []).extend(value.split())
    return directives


def test_service_dependencies():
    path = "/app/quotalogger-2.1/systemd/quotalogger.service"
    assert os.path.isfile(path), f"Service template {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "After=mock-db.service" in content, "Service template missing After=mock-db.service."
    assert "Requires=mock-db.service" in content, "Service template missing Requires=mock-db.service."

    directives = unit_directives(path)
    assert "mock-db.service" in directives.get("After", []), "After dependency is not in the [Unit] section."
    assert "mock-db.service" in directives.get("Requires", []), "Requires dependency is not in the [Unit] section."

    deployed = "/home/user/.config/systemd/user/quotalogger.service"
    assert os.path.isfile(deployed), f"Deployed user service {deployed} is missing."
    deployed_directives = unit_directives(deployed)
    assert "mock-db.service" in deployed_directives.get("After", []), "Deployed service lacks the After dependency."
    assert "mock-db.service" in deployed_directives.get("Requires", []), "Deployed service lacks the Requires dependency."


def test_service_is_active():
    try:
        result = subprocess.run(
            ["systemctl", "--user", "is-active", "quotalogger.service"],
            capture_output=True,
            text=True,
        )
        assert result.stdout.strip() == "active", f"quotalogger.service is not active. Output: {result.stdout.strip()}"
    except FileNotFoundError:
        pytest.fail("systemctl command not found.")


def test_parser_behavior_on_derived_inputs():
    assert calculate_quotas is not None, "Could not import calculate_quotas from quotalogger.parser"

    rng = random.SystemRandom()
    for count in (7, 113, 997):
        lines = []
        expected = 0
        for i in range(count):
            size = rng.randint(-50000, 50000)
            expected += size
            lines.append(f"user{rng.randint(1, 31)},file-{i},{size}\n")
            if i % 29 == 0:
                lines.extend(["malformed\n", "only,two\n", "too,many,fields,here\n", "\n"])
        rng.shuffle(lines)

        fd, path = tempfile.mkstemp(prefix="quota-verifier-", suffix=".log")
        try:
            with os.fdopen(fd, "w") as f:
                f.writelines(lines)
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                result = calculate_quotas(path)
            assert result == expected, f"calculate_quotas returned {result}, expected {expected}"
            assert output.getvalue() == f"TOTAL_USAGE: {expected}\n", "Parser printed output does not match the required format/value."
        finally:
            os.unlink(path)


def test_ci_script_and_results():
    script_path = "/home/user/ci_check.sh"
    assert os.path.isfile(script_path), f"CI script {script_path} is missing."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"CI script {script_path} is not executable."

    with open(script_path, "r") as f:
        script_source = f.read()
    executable_source = "\n".join(
        line for line in script_source.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )
    assert re.search(r"(^|[^A-Za-z0-9_-])quotalogger-cli([^A-Za-z0-9_-]|$)", executable_source), "CI script does not invoke quotalogger-cli."
    assert re.search(r"(^|[^A-Za-z0-9_-])grep([^A-Za-z0-9_-]|$)", executable_source), "CI script does not use grep."
    assert re.search(r"(^|[^A-Za-z0-9_-])awk([^A-Za-z0-9_-]|$)", executable_source), "CI script does not use awk."

    results_path = "/home/user/ci_results.txt"
    if os.path.exists(results_path):
        os.remove(results_path)

    log_path = "/app/data/test_logs.txt"
    with open(log_path, "rb") as f:
        original_log = f.read()

    rng = random.SystemRandom()
    generated = []
    expected = 0
    for i in range(347):
        size = rng.randint(100000, 900000)
        expected += size
        generated.append(f"ciuser{rng.randint(1, 19)},ci-file-{i},{size}\n")
    generated.extend(["ignored\n", "ignored,two\n", "ignored,too,many,columns\n"])
    rng.shuffle(generated)

    try:
        with open(log_path, "w") as f:
            f.writelines(generated)

        result = subprocess.run(
            ["/bin/bash", "-x", script_path],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"CI script failed to run: {result.stderr}"
    finally:
        with open(log_path, "wb") as f:
            f.write(original_log)

    trace = result.stderr
    assert re.search(r"(?m)^\++\s+(?:\S*/)?quotalogger-cli\s+/app/data/test_logs\.txt(?:\s|$)", trace), "CI script did not execute quotalogger-cli on the required log."
    assert re.search(r"(?m)^\++\s+(?:\S*/)?grep(?:\s|$)", trace), "CI script did not actually execute grep."
    assert re.search(r"(?m)^\++\s+(?:\S*/)?awk(?:\s|$)", trace), "CI script did not actually execute awk."

    assert os.path.isfile(results_path), f"CI results file {results_path} was not created by the script."
    with open(results_path, "r") as f:
        content = f.read().strip()
    assert content.isdigit(), f"CI results file should contain only a numeric value, got: '{content}'"
    assert content == str(expected), f"CI result was {content}, expected the CLI-derived total {expected}."


def test_parser_performance():
    assert calculate_quotas is not None, "Could not import calculate_quotas from quotalogger.parser"

    test_log_path = "/app/data/test_logs.txt"
    assert os.path.isfile(test_log_path), f"Test logs missing at {test_log_path}"
    expected = expected_total(test_log_path)

    output = io.StringIO()
    start_time = time.perf_counter()
    with contextlib.redirect_stdout(output):
        result = calculate_quotas(test_log_path)
    runtime = time.perf_counter() - start_time

    assert result == expected, f"Parser returned {result}, expected {expected}."
    assert output.getvalue() == f"TOTAL_USAGE: {expected}\n", "Parser output is incorrect."
    assert runtime < 1.0, f"Parser performance metric failed: runtime {runtime:.3f}s >= 1.0s threshold."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
