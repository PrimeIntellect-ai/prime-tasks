#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import urllib.request
import urllib.error
import time
import pytest
import re
import random
import secrets
import string
import tempfile


def test_nginx_config_fixed():
    config_path = "/app/nginx/nginx.conf"
    assert os.path.exists(config_path), f"Nginx config is missing at {config_path}"

    with open(config_path, 'r') as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:5000;" in content, "Nginx config should proxy to port 5000"


def test_env_file_fixed():
    env_path = "/app/c2/.env"
    assert os.path.exists(env_path), f"Environment file is missing at {env_path}"

    with open(env_path, 'r') as f:
        content = f.read()
    assert "REDIS_PASSWORD=Sup3rS3cr3tC2" in content, "The .env file should contain the correct REDIS_PASSWORD"


def test_keys_permissions():
    keys_dir = "/app/c2/keys"
    assert os.path.exists(keys_dir), f"Keys directory is missing at {keys_dir}"

    for filename in os.listdir(keys_dir):
        filepath = os.path.join(keys_dir, filename)
        if os.path.isfile(filepath):
            file_stat = os.stat(filepath)
            perms = stat.S_IMODE(file_stat.st_mode)
            assert perms == 0o600, f"Permissions for {filepath} should be 600, but are {oct(perms)}"


def test_end_to_end_flow():
    url = "http://127.0.0.1:8080/register?token=test_end_to_end"

    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx/Flask infrastructure: {e}")

    try:
        result = subprocess.run(
            ["redis-cli", "-a", "Sup3rS3cr3tC2", "EXISTS", "session:test_end_to_end"],
            capture_output=True, text=True, check=True
        )
        assert result.stdout.strip() == "1", "The token was not saved to Redis correctly."
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to query Redis: {e}")


def test_c2_filter_script():
    script_path = "/home/user/c2_filter.sh"
    assert os.path.exists(script_path), f"Script missing at {script_path}"
    assert os.path.isfile(script_path), f"Script path is not a regular file: {script_path}"

    evil_corpus = "/app/corpora/blue_team_probes.txt"
    clean_corpus = "/app/corpora/valid_beacons.txt"

    evil_out = "/tmp/evil_out.txt"
    clean_out = "/tmp/clean_out.txt"

    result_evil = subprocess.run(["bash", script_path, evil_corpus, evil_out], capture_output=True, text=True)
    assert result_evil.returncode == 0, f"Script failed on evil corpus: {result_evil.stderr}"

    assert os.path.exists(evil_out), "Output file for evil corpus not created"
    with open(evil_out, 'r') as f:
        evil_lines = [line.strip() for line in f if line.strip()]

    assert len(evil_lines) == 0, f"Expected 0 lines in evil output, but got {len(evil_lines)}. Bypassed probes: {evil_lines}"

    result_clean = subprocess.run(["bash", script_path, clean_corpus, clean_out], capture_output=True, text=True)
    assert result_clean.returncode == 0, f"Script failed on clean corpus: {result_clean.stderr}"

    assert os.path.exists(clean_out), "Output file for clean corpus not created"
    with open(clean_out, 'r') as f:
        clean_lines = [line.strip() for line in f if line.strip()]

    with open(clean_corpus, 'r') as f:
        original_clean_lines = [line.strip() for line in f if line.strip()]

    assert len(clean_lines) == len(original_clean_lines), f"Expected {len(original_clean_lines)} lines in clean output, got {len(clean_lines)}"

    for orig, processed in zip(original_clean_lines, clean_lines):
        expected = re.sub(r'token=[^&]+', 'token=[REDACTED]', orig)
        assert processed == expected, f"Clean line improperly modified. Expected: {expected}, Got: {processed}"


def expected_filter(lines):
    result = []
    for line in lines:
        if any(ch in line for ch in ("'", '"', '<', '>')):
            continue
        if "token=" not in line:
            continue
        result.append(re.sub(r'token=[^&]+', 'token=[REDACTED]', line))
    return result


def random_safe_text(length=12):
    alphabet = string.ascii_letters + string.digits + "_-.:/"
    return ''.join(secrets.choice(alphabet) for _ in range(length))


def test_c2_filter_generated_inputs_and_order():
    script_path = "/home/user/c2_filter.sh"
    rng = random.SystemRandom()

    with tempfile.TemporaryDirectory(prefix="c2-filter-") as directory:
        for round_number in range(5):
            marker = random_safe_text(18)
            lines = []

            for i in range(8):
                token = random_safe_text(8 + i)
                lines.append(f"/beacon/{marker}/{i}?mode={random_safe_text(5)}&token={token}&seq={i}")

            lines.extend([
                f"/first/{marker}?token={random_safe_text()}&next=yes",
                f"/last/{marker}?before=yes&token={random_safe_text()}",
                f"/encoded/{marker}?token={random_safe_text()}&value=%27%22%3C%3E",
                f"/multi/{marker}?token={random_safe_text()}&x=1&token={random_safe_text()}&done=1",
                f"/missing/{marker}?mode=poll&value={random_safe_text()}",
                f"/plain/{marker}",
                f"/probe/{marker}?token={random_safe_text()}&q='scan",
                f'/probe/{marker}?q="scan&token={random_safe_text()}',
                f"/probe/{marker}?token={random_safe_text()}&q=<script>",
                f"/probe/{marker}?q=1>0&token={random_safe_text()}",
            ])
            rng.shuffle(lines)
            expected = expected_filter(lines)

            input_path = os.path.join(directory, f"input-{round_number}-{secrets.token_hex(8)}.log")
            output_path = os.path.join(directory, f"output-{round_number}-{secrets.token_hex(8)}.log")
            with open(input_path, "w", encoding="utf-8") as f:
                f.write("\n".join(lines) + "\n")
            with open(output_path, "w", encoding="utf-8") as f:
                f.write("stale-output-must-be-replaced\n")

            run = subprocess.run(
                ["bash", script_path, input_path, output_path],
                capture_output=True, text=True, timeout=10
            )
            assert run.returncode == 0, f"Script failed on generated corpus: {run.stderr}"
            assert os.path.isfile(output_path), "Script did not create a regular output file"
            with open(output_path, "r", encoding="utf-8") as f:
                actual = f.read().splitlines()
            assert actual == expected, f"Generated corpus mismatch. Expected {expected!r}, got {actual!r}"


def test_c2_filter_requires_exactly_two_arguments():
    script_path = "/home/user/c2_filter.sh"
    with tempfile.TemporaryDirectory(prefix="c2-filter-args-") as directory:
        input_path = os.path.join(directory, "input.log")
        output_path = os.path.join(directory, "output.log")
        with open(input_path, "w", encoding="utf-8") as f:
            f.write(f"/?token={random_safe_text()}\n")

        invocations = [
            ["bash", script_path],
            ["bash", script_path, input_path],
            ["bash", script_path, input_path, output_path, "unexpected-extra-argument"],
        ]
        for command in invocations:
            result = subprocess.run(command, capture_output=True, text=True, timeout=10)
            assert result.returncode != 0, f"Script accepted an invalid argument count: {command[2:]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
