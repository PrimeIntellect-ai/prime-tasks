#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/health_eval.py"
DEPLOY_SCRIPT = "/home/user/deploy_health_check.sh"
DEPLOYED_SCRIPT = "/home/user/health_checks/bin/health_eval.py"
ORACLE_SCRIPT = "/tests/oracle_health_eval"
EXPECTED_PARTS = [
    "*/5 * * * *",
    "/home/user/health_checks/bin/health_eval.py",
    "10.0.0.1",
    "500",
]


def is_matching_cron_line(line):
    line = line.strip()
    return bool(line) and not line.startswith("#") and all(part in line for part in EXPECTED_PARTS)


def read_user_crontab():
    result = subprocess.run(
        ["crontab", "-u", "user", "-l"],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return result.stdout
    if result.returncode == 1:
        return ""
    pytest.fail(f"Failed to read user crontab: {result.stderr}")


def remove_existing_test_cron_entries():
    current = read_user_crontab()
    kept = [line for line in current.splitlines() if not is_matching_cron_line(line)]
    if kept:
        subprocess.run(
            ["crontab", "-u", "user", "-"],
            input="\n".join(kept) + "\n",
            text=True,
            capture_output=True,
            check=True,
        )
    else:
        subprocess.run(
            ["crontab", "-u", "user", "-r"],
            capture_output=True,
            text=True,
        )


def test_fuzz_equivalence():
    """Fuzz the agent's Python script against the verification-only oracle."""
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing: {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script missing: {ORACLE_SCRIPT}"

    random.seed(42)
    for _ in range(1000):
        ip = f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 255)}"
        latency = str(random.randint(0, 20000))

        agent_proc = subprocess.run(
            ["python3", AGENT_SCRIPT, ip, latency],
            capture_output=True,
            text=True,
        )
        assert agent_proc.returncode == 0, (
            f"Agent script failed on inputs: {ip} {latency}\nStderr: {agent_proc.stderr}"
        )
        agent_out = agent_proc.stdout.strip()

        oracle_proc = subprocess.run(
            ["python3", ORACLE_SCRIPT, ip, latency],
            capture_output=True,
            text=True,
        )
        assert oracle_proc.returncode == 0, (
            f"Oracle script failed on inputs: {ip} {latency}\nStderr: {oracle_proc.stderr}"
        )
        oracle_out = oracle_proc.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on inputs IPv4={ip}, Latency={latency}.\n"
            f"Expected (Oracle): {oracle_out}\nGot (Agent): {agent_out}"
        )


def test_deployment_script_is_idempotent_and_creates_artifacts():
    """Execute the deployment twice as user and verify its resulting state."""
    assert os.path.isfile(DEPLOY_SCRIPT), f"Deployment script missing: {DEPLOY_SCRIPT}"

    shutil.rmtree("/home/user/health_checks", ignore_errors=True)
    remove_existing_test_cron_entries()

    for run_number in (1, 2):
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "bash", DEPLOY_SCRIPT],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, (
            f"Deployment script failed on run {run_number}.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )

    assert os.path.isfile(DEPLOYED_SCRIPT), f"Deployed script missing: {DEPLOYED_SCRIPT}"
    with open(AGENT_SCRIPT, "rb") as source, open(DEPLOYED_SCRIPT, "rb") as deployed:
        assert deployed.read() == source.read(), "Deployed script is not a copy of health_eval.py"

    perms = stat.S_IMODE(os.stat(DEPLOYED_SCRIPT).st_mode)
    assert perms == 0o755, f"Deployed script permissions are {oct(perms)}, expected 0o755"

    crontab_output = read_user_crontab()
    match_count = 0
    for line in crontab_output.strip().split("\n"):
        if is_matching_cron_line(line):
            match_count += 1

    assert match_count > 0, "Cron job entry not found."
    assert match_count == 1, (
        f"Cron job entry is duplicated. Found {match_count} matches, expected exactly 1."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
