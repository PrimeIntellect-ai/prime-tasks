#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import json
import base64
import urllib.parse
import ast
import secrets
import subprocess
import pytest

SCRIPT_FILE = "/home/user/analyze_logs.py"
LOG_FILE = "/home/user/traffic_logs.json"
OUTPUT_FILE = "/home/user/malicious_ips.txt"


def get_expected_malicious_ips(log_file):
    """Derive expected malicious IPs from the supplied traffic log."""
    with open(log_file, 'r') as f:
        logs = json.load(f)

    malicious_ips = set()

    for log in logs:
        cookies = log.get("cookies", {})
        if "X-Debug-Session" in cookies:
            encoded_payload = cookies["X-Debug-Session"]
            try:
                b64_decoded = urllib.parse.unquote(encoded_payload)
                payload = base64.b64decode(b64_decoded).decode('utf-8')
                tree = ast.parse(payload)
                is_malicious = False

                for node in ast.walk(tree):
                    if isinstance(node, ast.Import):
                        for alias in node.names:
                            if alias.name in ("os", "subprocess"):
                                is_malicious = True
                    elif isinstance(node, ast.ImportFrom):
                        if node.module in ("os", "subprocess"):
                            is_malicious = True
                    elif isinstance(node, ast.Call):
                        if isinstance(node.func, ast.Name):
                            if node.func.id in ("eval", "exec"):
                                is_malicious = True

                if is_malicious:
                    malicious_ips.add(log.get("source_ip"))
            except Exception:
                pass

    return sorted(list(malicious_ips))


def test_script_exists():
    """Test that the student created the analysis script."""
    assert os.path.exists(SCRIPT_FILE), f"The script file {SCRIPT_FILE} was not found."
    assert os.path.isfile(SCRIPT_FILE), f"The path {SCRIPT_FILE} is not a file."


def test_output_file_exists():
    """Test that the output file was generated."""
    assert os.path.exists(OUTPUT_FILE), f"The output file {OUTPUT_FILE} was not found. Did the script run successfully?"
    assert os.path.isfile(OUTPUT_FILE), f"The path {OUTPUT_FILE} is not a file."


def test_malicious_ips_content():
    """Test that the output file contains exactly the expected malicious IPs in the correct order."""
    expected_ips = get_expected_malicious_ips(LOG_FILE)

    with open(OUTPUT_FILE, 'r') as f:
        actual_ips = [line.strip() for line in f if line.strip()]

    assert actual_ips == expected_ips, (
        f"The contents of {OUTPUT_FILE} do not match the expected IPs.\n"
        f"Expected: {expected_ips}\n"
        f"Found:    {actual_ips}\n"
        "Ensure you are extracting unique IPs, sorting them in ascending string order, "
        "and correctly parsing the AST for os/subprocess imports and eval/exec calls."
    )


def encode_payload(payload):
    encoded = base64.b64encode(payload.encode("utf-8")).decode("ascii")
    return urllib.parse.quote(encoded, safe="")


def random_ips(count):
    result = set()
    while len(result) < count:
        result.add(f"10.{secrets.randbelow(256)}.{secrets.randbelow(256)}.{secrets.randbelow(254) + 1}")
    return list(result)


def test_script_executes_and_analyzes_fresh_logs_safely():
    """Execute the submitted artifact against fresh, unpredictable traffic."""
    ips = random_ips(8)
    marker = f"/tmp/analyze_logs_payload_executed_{secrets.token_hex(12)}"

    payloads = [
        (ips[0], f"import os as harmless\nopen({marker!r}, 'w').write('executed')", True),
        (ips[1], "from subprocess import Popen as Process\nx = Process", True),
        (ips[2], "value = eval('40 + 2')", True),
        (ips[3], "def later():\n    exec('x = 1')", True),
        (ips[4], "import sys\nprint(sys.version)", False),
        (ips[5], "text = 'import os; exec(1)'\nprint(text)", False),
        (ips[6], "class Holder:\n    def eval(self, value):\n        return value\nHolder().eval('safe')", False),
    ]

    logs = []
    for source_ip, payload, _ in payloads:
        logs.append({
            "source_ip": source_ip,
            "method": "POST",
            "headers": {"User-Agent": "verification"},
            "cookies": {
                "ordinary": "cookie",
                "X-Debug-Session": encode_payload(payload),
            },
        })

    # A duplicate malicious source must not produce a duplicate output line.
    logs.append({
        "source_ip": ips[0],
        "method": "GET",
        "headers": {},
        "cookies": {"X-Debug-Session": encode_payload("import subprocess")},
    })
    # A request without the target cookie must be ignored.
    logs.append({
        "source_ip": ips[7],
        "method": "GET",
        "headers": {},
        "cookies": {"session": encode_payload("import os")},
    })

    secrets.SystemRandom().shuffle(logs)
    with open(LOG_FILE, "w") as f:
        json.dump(logs, f)

    expected_ips = get_expected_malicious_ips(LOG_FILE)
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    if os.path.exists(marker):
        os.remove(marker)

    result = subprocess.run(
        [sys.executable, SCRIPT_FILE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )

    assert not os.path.exists(marker), "The decoded Python payload was executed; it must only be parsed with ast."
    assert result.returncode == 0, (
        f"Running {SCRIPT_FILE} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_FILE), "Running the script did not create malicious_ips.txt."

    with open(OUTPUT_FILE, "r") as f:
        actual_ips = [line.strip() for line in f if line.strip()]

    assert actual_ips == expected_ips, (
        "The script did not correctly analyze the fresh verification traffic.\n"
        f"Expected: {expected_ips}\nFound: {actual_ips}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
