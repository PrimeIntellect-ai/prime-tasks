#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import random
import subprocess
import sys
import tempfile

import pytest

REPO_DIR = "/home/user/uptime_monitor"
SCRIPT_FILE = os.path.join(REPO_DIR, "monitor.py")


def get_expected_bad_commit():
    result = subprocess.run(
        ["git", "log", "--grep=Update SLA calculation logic to handle edge cases", "--format=%H"],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        check=True,
    )
    commit_hash = result.stdout.strip()
    assert commit_hash, "Could not find the expected bad commit in the git history."
    return commit_hash


def test_bad_commit_identified():
    bad_commit_file = "/home/user/bad_commit.txt"
    assert os.path.exists(bad_commit_file), f"{bad_commit_file} does not exist. Did you write the bad commit hash to this file?"

    with open(bad_commit_file, "r") as f:
        actual_commit = f.read().strip()

    expected_commit = get_expected_bad_commit()
    assert actual_commit == expected_commit, f"The commit hash in {bad_commit_file} is incorrect. Expected {expected_commit}, got {actual_commit}."


def test_sla_report_generated_and_correct():
    report_file = "/home/user/sla_report.json"
    logs_file = "/home/user/data/ping_logs.json"

    assert os.path.exists(report_file), f"The SLA report {report_file} was not generated."
    assert os.path.exists(logs_file), f"The input logs {logs_file} are missing."

    with open(logs_file, "r") as f:
        logs_data = json.load(f)

    with open(report_file, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The SLA report {report_file} is not valid JSON.")

    for svc, metrics in logs_data.items():
        assert svc in report_data, f"Service '{svc}' is missing from the SLA report."
        total = metrics["total_time_minutes"]
        downtime = metrics["downtime_minutes"]
        expected_sla = (total - downtime) / total * 100.0
        actual_sla = report_data[svc]
        assert abs(actual_sla - expected_sla) < 1e-4, (
            f"Incorrect SLA calculated for {svc}. Expected {expected_sla}, got {actual_sla}."
        )


def test_misconfigurations_fixed():
    req_file = os.path.join(REPO_DIR, "requirements.txt")

    assert os.path.isfile(SCRIPT_FILE), f"Script {SCRIPT_FILE} is missing."
    with open(SCRIPT_FILE, "r") as f:
        script_content = f.read()

    assert "import reqeusts" not in script_content, "The misspelled import 'reqeusts' is still present in monitor.py."

    if os.path.exists(req_file):
        with open(req_file, "r") as f:
            req_content = f.read()
        assert "reqeusts==" not in req_content, "The misspelled dependency 'reqeusts' is still present in requirements.txt."


def test_calculate_sla_function_on_derived_inputs():
    spec = importlib.util.spec_from_file_location("submitted_monitor", SCRIPT_FILE)
    assert spec is not None and spec.loader is not None, "monitor.py could not be loaded as a Python module."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    assert hasattr(module, "calculate_sla"), "monitor.py does not define calculate_sla."
    assert callable(module.calculate_sla), "calculate_sla is not callable."

    rng = random.SystemRandom()
    cases = [(1, 0), (1, 1), (1440, 15)]
    for _ in range(8):
        total = rng.randint(2, 100000)
        downtime = rng.randint(0, total)
        cases.append((total, downtime))

    for total, downtime in cases:
        expected = (total - downtime) / total * 100.0
        actual = module.calculate_sla(total, downtime)
        assert isinstance(actual, (int, float)), "calculate_sla must return a numeric percentage."
        assert abs(actual - expected) < 1e-9, (
            f"calculate_sla({total}, {downtime}) returned {actual}; expected {expected}."
        )


def test_monitor_executes_and_generates_dynamic_report():
    rng = random.SystemRandom()
    logs = {}
    for index in range(7):
        total = rng.randint(10, 100000)
        downtime = rng.randint(0, total)
        logs[f"dynamic_service_{index}_{rng.getrandbits(48):012x}"] = {
            "total_time_minutes": total,
            "downtime_minutes": downtime,
        }

    with tempfile.TemporaryDirectory() as temp_dir:
        logs_file = os.path.join(temp_dir, "unseen_logs.json")
        output_file = os.path.join(temp_dir, "generated_report.json")
        with open(logs_file, "w") as f:
            json.dump(logs, f)

        result = subprocess.run(
            [sys.executable, SCRIPT_FILE, "--logs", logs_file, "--output", output_file],
            cwd=REPO_DIR,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"monitor.py failed to execute. stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )
        assert os.path.isfile(output_file), "monitor.py did not create the requested output file."

        try:
            with open(output_file, "r") as f:
                report = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"monitor.py produced invalid JSON: {exc}")

        assert set(report) == set(logs), "The generated report does not contain exactly the input services."
        for service, metrics in logs.items():
            expected = (
                (metrics["total_time_minutes"] - metrics["downtime_minutes"])
                / metrics["total_time_minutes"]
                * 100.0
            )
            actual = report[service]
            assert isinstance(actual, (int, float)), f"SLA for {service} is not numeric."
            assert abs(actual - expected) < 1e-9, (
                f"Incorrect dynamically generated SLA for {service}: expected {expected}, got {actual}."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
