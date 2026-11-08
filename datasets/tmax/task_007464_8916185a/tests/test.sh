#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import re
import shutil
import subprocess
import tempfile
import pytest

DEPLOY_PATH = "/home/user/deploy_cost_monitor.sh"
ANALYZER_PATH = "/home/user/calculate_costs.py"
PROFILE_PATH = "/home/user/.bash_profile"
DATA_PATH = "/home/user/project_data"
LOG_PATH = "/home/user/finops_alerts.log"


def test_deploy_script_exists_and_executable():
    path = "/home/user/deploy_cost_monitor.sh"
    assert os.path.exists(path), f"Deployment script {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"Deployment script {path} is not executable."


def test_bash_profile_idempotency():
    path = "/home/user/.bash_profile"
    assert os.path.exists(path), f"{path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    rate_count = content.count("FINOPS_RATE")
    limit_count = content.count("FINOPS_LIMIT")

    assert rate_count >= 1, "FINOPS_RATE is not set in .bash_profile."
    assert limit_count >= 1, "FINOPS_LIMIT is not set in .bash_profile."


def test_python_script_exists():
    path = "/home/user/calculate_costs.py"
    assert os.path.exists(path), f"Python script {path} was not created."
    assert os.path.isfile(path), f"{path} is not a file."


def test_execution_and_idempotency():
    script_path = "/home/user/deploy_cost_monitor.sh"
    log_path = "/home/user/finops_alerts.log"
    profile_path = "/home/user/.bash_profile"

    # Read initial profile state
    with open(profile_path, "r") as f:
        initial_profile = f.read()

    # Run the script again
    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute on subsequent run: {result.stderr}"

    # Check profile idempotency (should not have changed or at least not added duplicate lines)
    with open(profile_path, "r") as f:
        final_profile = f.read()

    assert initial_profile == final_profile or final_profile.count("FINOPS_RATE=0.15") == 1, \
        "The script is not idempotent: .bash_profile was modified on subsequent runs with duplicate entries."

    # Check alerts log
    assert os.path.exists(log_path), f"Alert log {log_path} does not exist."
    with open(log_path, "r") as f:
        lines = f.read().strip().split('\n')

    assert len(lines) >= 2, "Alert log should have multiple lines after running the script multiple times."
    expected_alert = "[ALERT] Cost exceeds limit: $60.00 (> $50.00) - Notifying admin@local"
    assert lines[-1] == expected_alert, f"Alert log line does not match expected format. Got: {lines[-1]}"
    assert lines[-2] == expected_alert, f"Alert log line does not match expected format. Got: {lines[-2]}"


def test_z_generated_analyzer_and_dynamic_behavior():
    # Ensure the deployment script really generates the analyzer rather than relying
    # on a pre-existing placeholder.
    with open(ANALYZER_PATH, "w") as f:
        f.write("# verifier sentinel: deployment must replace this file\n")

    first = subprocess.run(["bash", DEPLOY_PATH], capture_output=True, text=True)
    assert first.returncode == 0, f"Deployment failed while regenerating analyzer: {first.stderr}"
    assert os.path.isfile(ANALYZER_PATH), "Deployment did not recreate calculate_costs.py."
    with open(ANALYZER_PATH, "r") as f:
        assert "verifier sentinel" not in f.read(), "Deployment did not replace calculate_costs.py."

    with open(PROFILE_PATH, "rb") as f:
        profile_after_first = f.read()
    second = subprocess.run(["bash", DEPLOY_PATH], capture_output=True, text=True)
    assert second.returncode == 0, f"Deployment failed on repeated execution: {second.stderr}"
    with open(PROFILE_PATH, "rb") as f:
        profile_after_second = f.read()
    assert profile_after_first == profile_after_second, \
        "Repeated deployment changed .bash_profile; configuration is not idempotent."

    profile_text = profile_after_second.decode(errors="replace")
    active_lines = [line.split("#", 1)[0] for line in profile_text.splitlines()]
    rate_assignments = [line for line in active_lines if re.search(r"\bFINOPS_RATE\s*=", line)]
    limit_assignments = [line for line in active_lines if re.search(r"\bFINOPS_LIMIT\s*=", line)]
    assert len(rate_assignments) == 1, "FINOPS_RATE must be configured exactly once in .bash_profile."
    assert len(limit_assignments) == 1, "FINOPS_LIMIT must be configured exactly once in .bash_profile."

    sourced = subprocess.run(
        ["bash", "--noprofile", "--norc", "-c",
         'source "$1"; printf "__FINOPS_VALUES__%s|%s\\n" "$FINOPS_RATE" "$FINOPS_LIMIT"',
         "bash", PROFILE_PATH],
        capture_output=True, text=True
    )
    assert sourced.returncode == 0, f".bash_profile could not be sourced: {sourced.stderr}"
    markers = [line for line in sourced.stdout.splitlines() if line.startswith("__FINOPS_VALUES__")]
    assert markers and markers[-1] == "__FINOPS_VALUES__0.15|50", \
        ".bash_profile does not configure FINOPS_RATE=0.15 and FINOPS_LIMIT=50."

    backup_root = tempfile.mkdtemp(prefix="finops-verifier-")
    backup_data = os.path.join(backup_root, "original_project_data")
    log_existed = os.path.isfile(LOG_PATH)
    original_log = None
    if log_existed:
        with open(LOG_PATH, "rb") as f:
            original_log = f.read()

    def clear_log():
        if os.path.lexists(LOG_PATH):
            if os.path.isdir(LOG_PATH) and not os.path.islink(LOG_PATH):
                shutil.rmtree(LOG_PATH)
            else:
                os.unlink(LOG_PATH)

    def run_analyzer(env_updates):
        env = os.environ.copy()
        env.pop("FINOPS_RATE", None)
        env.pop("FINOPS_LIMIT", None)
        env.update(env_updates)
        return subprocess.run(
            ["python3", ANALYZER_PATH], capture_output=True, text=True, env=env
        )

    try:
        os.rename(DATA_PATH, backup_data)
        os.makedirs(os.path.join(DATA_PATH, "nested", "deeper"))

        # Use unpredictable sizes and pricing so a fixed 400 MB answer cannot pass.
        rng = random.SystemRandom()
        sizes = [
            rng.randrange(120_000, 900_000),
            rng.randrange(1_100_000, 2_400_000),
            rng.randrange(25_000, 600_000),
        ]
        paths = [
            os.path.join(DATA_PATH, "top.bin"),
            os.path.join(DATA_PATH, "nested", "middle.bin"),
            os.path.join(DATA_PATH, "nested", "deeper", "bottom.bin"),
        ]
        for path, size in zip(paths, sizes):
            with open(path, "wb") as f:
                f.truncate(size)

        total_bytes = sum(sizes)
        rate_text = f"{rng.randrange(37, 493) / 100:.2f}"
        rate = float(rate_text)
        expected_cost = (total_bytes / 1048576.0) * rate
        limit_text = repr(expected_cost - rng.randrange(10, 90) / 100.0)
        parsed_limit = float(limit_text)
        expected = (
            f"[ALERT] Cost exceeds limit: ${expected_cost:.2f} "
            f"(> ${parsed_limit:.2f}) - Notifying admin@local"
        )

        clear_log()
        result = run_analyzer({"FINOPS_RATE": rate_text, "FINOPS_LIMIT": limit_text})
        assert result.returncode == 0, f"Analyzer failed on dynamic input: {result.stderr}"
        assert os.path.isfile(LOG_PATH), "Analyzer did not create the alert log when cost exceeded the limit."
        with open(LOG_PATH, "r") as f:
            dynamic_lines = f.read().splitlines()
        assert dynamic_lines == [expected], \
            f"Analyzer did not recursively calculate and format the dynamic cost. Got: {dynamic_lines}"

        # Equality must not alert because the comparison is strictly greater than.
        clear_log()
        for path in paths:
            if os.path.exists(path):
                os.unlink(path)
        exact_size = 2 * 1048576
        with open(os.path.join(DATA_PATH, "nested", "deeper", "exact.bin"), "wb") as f:
            f.truncate(exact_size)
        result = run_analyzer({"FINOPS_RATE": "1.25", "FINOPS_LIMIT": "2.50"})
        assert result.returncode == 0, f"Analyzer failed at the exact limit: {result.stderr}"
        assert not os.path.exists(LOG_PATH), "Analyzer alerted when cost was equal to, not greater than, the limit."

        # With both variables absent they must silently default to zero and not log.
        clear_log()
        result = run_analyzer({})
        assert result.returncode == 0, f"Analyzer failed with unset FINOPS variables: {result.stderr}"
        assert not os.path.exists(LOG_PATH), "Analyzer did not default unset FINOPS variables to 0.0."

        # FINOPS_LIMIT independently defaults to zero when only the rate is set.
        clear_log()
        result = run_analyzer({"FINOPS_RATE": "1.00"})
        assert result.returncode == 0, f"Analyzer failed with FINOPS_LIMIT unset: {result.stderr}"
        expected_default_limit = "[ALERT] Cost exceeds limit: $2.00 (> $0.00) - Notifying admin@local"
        assert os.path.isfile(LOG_PATH), "Unset FINOPS_LIMIT did not default to 0.0."
        with open(LOG_PATH, "r") as f:
            assert f.read().splitlines() == [expected_default_limit]

        # FINOPS_RATE independently defaults to zero when only the limit is set.
        clear_log()
        result = run_analyzer({"FINOPS_LIMIT": "1.00"})
        assert result.returncode == 0, f"Analyzer failed with FINOPS_RATE unset: {result.stderr}"
        assert not os.path.exists(LOG_PATH), "Unset FINOPS_RATE did not default to 0.0."
    finally:
        clear_log()
        if os.path.exists(DATA_PATH):
            shutil.rmtree(DATA_PATH)
        if os.path.exists(backup_data):
            os.rename(backup_data, DATA_PATH)
        shutil.rmtree(backup_root, ignore_errors=True)
        if log_existed:
            with open(LOG_PATH, "wb") as f:
                f.write(original_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
