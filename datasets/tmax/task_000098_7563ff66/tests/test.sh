#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shlex
import subprocess
import tempfile
from collections import Counter

import pytest

HARDEN = "/home/user/harden.sh"
FIREWALL = "/home/user/firewall.sh"
ORIGINAL_LOG = "/app/access.log"


def read_spec():
    result = subprocess.run(
        ["tesseract", "/app/config_spec.png", "stdout"],
        text=True,
        capture_output=True,
        timeout=20,
        check=True,
    )
    text = result.stdout
    socket_match = re.search(r"unix:/[A-Za-z0-9_./-]+", text)
    limit_match = re.search(r"Rate\s*Limit\s*:\s*(\d+)", text, re.I)
    assert socket_match, f"Could not OCR a backend socket from the specification: {text!r}"
    assert limit_match, f"Could not OCR a rate limit from the specification: {text!r}"
    return socket_match.group(0), int(limit_match.group(1))


def expected_ips(log_path, threshold):
    counts = Counter()
    line_re = re.compile(r"^(\d{1,3}(?:\.\d{1,3}){3})\s+.*?\[([^ ]+)\s")
    with open(log_path, encoding="utf-8") as handle:
        for line in handle:
            match = line_re.search(line)
            if match:
                counts[(match.group(1), match.group(2))] += 1
    return {ip for (ip, _second), count in counts.items() if count > threshold}


def parse_firewall(expected):
    assert os.path.isfile(FIREWALL), f"Expected {FIREWALL} to exist. Ensure harden.sh generates it."
    assert os.access(FIREWALL, os.X_OK), f"Expected {FIREWALL} to be executable."
    with open(FIREWALL, encoding="utf-8") as handle:
        lines = [line.strip() for line in handle if line.strip() and not line.lstrip().startswith("#")]

    ips = []
    for line in lines:
        match = re.fullmatch(r"ufw\s+deny\s+from\s+(\d{1,3}(?:\.\d{1,3}){3})", line)
        assert match, f"Unexpected content in firewall.sh: {line!r}"
        ips.append(match.group(1))

    assert len(ips) == len(set(ips)), f"firewall.sh contains duplicate deny commands: {ips}"
    assert set(ips) == expected, f"Expected firewall IPs {expected}, got {set(ips)}"


def run_harden(log_path, threshold):
    if os.path.exists(FIREWALL):
        os.unlink(FIREWALL)
    env = os.environ.copy()
    env["LOG_PATH"] = log_path
    subprocess.run(["/bin/bash", HARDEN], env=env, check=True, timeout=20)
    parse_firewall(expected_ips(log_path, threshold))


def write_log(path, records):
    with open(path, "w", encoding="utf-8") as handle:
        for ip, second in records:
            handle.write(f'{ip} - - [{second} +0000] "GET / HTTP/1.1" 200 123\n')


def test_nginx_fixed_conf():
    path = "/home/user/nginx_fixed.conf"
    assert os.path.isfile(path), f"Expected {path} to exist."
    with open(path, encoding="utf-8") as handle:
        content = handle.read()

    # Preserve the original assertion while also verifying an actual replacement.
    assert "unix:/home/user/run/backend.sock" in content, "The fixed Nginx config does not contain the correct backend socket path."
    socket, _ = read_spec()
    original = """http {
    upstream backend {
        server unix:/tmp/wrong.sock;
    }
    server {
        listen 80;
        location / {
            proxy_pass http://backend;
        }
    }
}
"""
    expected = original.replace("unix:/tmp/wrong.sock", socket)
    assert content == expected, "nginx_fixed.conf must be the supplied configuration with only the incorrect socket replaced."
    assert "unix:/tmp/wrong.sock" not in content, "The incorrect upstream socket remains in nginx_fixed.conf."


def test_harden_script_exists_and_is_bash():
    assert os.path.isfile(HARDEN), f"Expected {HARDEN} to exist."
    with open(HARDEN, encoding="utf-8") as handle:
        content = handle.read()
    first_line = content.splitlines()[0] if content.splitlines() else ""
    assert re.match(r"^#!\s*(?:/usr/bin/env(?:\s+-S)?\s+bash|/(?:usr/)?bin/bash)(?:\s|$)", first_line), "harden.sh must be a Bash script with a Bash shebang."
    subprocess.run(["/bin/bash", "-n", HARDEN], check=True, timeout=10)

    active = "\n".join(line for line in content.splitlines() if not line.lstrip().startswith("#"))
    forbidden = re.search(r"(?:^|[;&|()]|\b(?:exec|command|env)\s+)(?:\s*)(python(?:3)?|perl|ruby|node|php)(?:\s|$)", active, re.M)
    assert not forbidden, f"Log parsing must be implemented in Bash, not by invoking {forbidden.group(1)}."


def test_harden_uses_log_path_and_parses_per_second():
    _, threshold = read_spec()
    nonce = secrets.randbelow(180) + 20
    ip_a = f"198.51.100.{nonce}"
    ip_b = f"203.0.113.{nonce}"
    ip_c = f"192.0.2.{nonce}"
    ip_d = f"198.51.100.{nonce + 1}"

    with tempfile.TemporaryDirectory(prefix="harden-verifier-") as directory:
        first = os.path.join(directory, secrets.token_hex(8) + ".log")
        records = []
        records += [(ip_a, "11/Nov/2024:01:02:03")] * (threshold + 1)
        records += [(ip_b, "11/Nov/2024:01:02:04")] * threshold
        records += [(ip_b, "11/Nov/2024:01:02:05")] * threshold
        records += [(ip_c, "11/Nov/2024:01:02:06")] * threshold
        write_log(first, records)
        run_harden(first, threshold)

        second = os.path.join(directory, secrets.token_hex(8) + ".access")
        records = []
        records += [(ip_d, "12/Nov/2024:23:59:58")] * (threshold + 4)
        records += [(ip_a, "12/Nov/2024:23:59:58")] * (threshold - 1)
        records += [(ip_a, "12/Nov/2024:23:59:59")] * (threshold - 1)
        write_log(second, records)
        run_harden(second, threshold)

    # Leave firewall.sh generated from the supplied access log for the original checks.
    run_harden(ORIGINAL_LOG, threshold)


def test_firewall_script_f1_score():
    assert os.path.isfile(FIREWALL), f"Expected {FIREWALL} to exist. Ensure your harden.sh script generates it."
    with open(FIREWALL, encoding="utf-8") as handle:
        content = handle.read()

    extracted_ips = set(re.findall(r"ufw deny from ([0-9\.]+)", content))
    ground_truth = {"192.168.1.100", "10.0.0.55"}
    tp = len(extracted_ips.intersection(ground_truth))
    fp = len(extracted_ips - ground_truth)
    fn = len(ground_truth - extracted_ips)
    if tp == 0:
        f1 = 0.0
    else:
        precision = tp / (tp + fp)
        recall = tp / (tp + fn)
        f1 = 2 * precision * recall / (precision + recall)
    assert f1 >= 0.95, f"F1 score of identified IPs is {f1:.2f}, expected >= 0.95. Extracted IPs: {extracted_ips}"


def test_firewall_script_executable():
    if not os.path.isfile(FIREWALL):
        pytest.skip("firewall.sh does not exist, skipping executable check.")
    assert os.access(FIREWALL, os.X_OK), f"Expected {FIREWALL} to be executable."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
