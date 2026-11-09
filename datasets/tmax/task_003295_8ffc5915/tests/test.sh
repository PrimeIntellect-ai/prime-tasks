#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shlex
import string
import subprocess
import tempfile
import time
import uuid

import pytest

SCRIPT_PATH = "/home/user/sanitize.py"
BINARY_PATH = "/app/net_diag_shell"


def run_sanitizer(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def oracle_exit_code(data):
    result = subprocess.run(
        [BINARY_PATH],
        input=data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, "net_diag_shell failed while deriving expected result"
    responses = result.stdout.splitlines()
    assert all(response in (b"OK", b"Error") for response in responses)
    return 1 if b"Error" in responses else 0


def test_sanitize_py_exists():
    """Test that the /home/user/sanitize.py script exists."""
    assert os.path.exists(SCRIPT_PATH), f"Missing script at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"


def test_adversarial_corpus():
    """Retain validation against the supplied clean and evil corpora."""
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.exists(SCRIPT_PATH), "sanitize.py is missing"
    assert os.path.exists(clean_dir), "clean corpus is missing"
    assert os.path.exists(evil_dir), "evil corpus is missing"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    for path in clean_files:
        if run_sanitizer(path).returncode != 0:
            clean_failed.append(os.path.basename(path))

    evil_failed = []
    for path in evil_files:
        if run_sanitizer(path).returncode != 1:
            evil_failed.append(os.path.basename(path))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    assert not errors, "Corpus validation failed: " + "; ".join(errors)


def test_sanitizer_against_fresh_oracle_derived_inputs():
    """Exercise fresh paths and inputs, deriving every answer from the binary."""
    rng = random.SystemRandom()
    nonce = uuid.uuid4().hex
    safe_alphabet = string.ascii_letters + string.digits + ".:_-/ "
    forbidden_fragments = [
        "192.168.100.", "127.0.0.1", "localhost", "0.0.0.0",
        ";", "|", "&", "$", "`",
    ]

    def safe_text(min_len=3, max_len=60):
        while True:
            value = "".join(rng.choice(safe_alphabet) for _ in range(rng.randint(min_len, max_len)))
            encoded = value.encode()
            if oracle_exit_code(encoded + b"\n") == 0:
                return value

    cases = [
        b"",
        b"8.8.4.4\nexample.org\n",
        b"LOCALHOST\n192.168.10.25\n127.0.0.2\n",
        b"host;name\n",
        b"host|name\n",
        b"host&name\n",
        b"host$name\n",
        b"host`name\n",
        b"prefixlocalhostsuffix\n",
        b"prefix192.168.100.77suffix\n",
        b"prefix127.0.0.1suffix\n",
        b"prefix0.0.0.0suffix\n",
    ]

    for _ in range(45):
        lines = [safe_text() for _ in range(rng.randint(1, 6))]
        cases.append(("\n".join(lines) + ("\n" if rng.choice([True, False]) else "")).encode())

    for fragment in forbidden_fragments:
        for _ in range(7):
            lines = [safe_text() for _ in range(rng.randint(1, 5))]
            position = rng.randrange(len(lines))
            insertion = rng.randrange(len(lines[position]) + 1)
            lines[position] = lines[position][:insertion] + fragment + lines[position][insertion:]
            cases.append(("\n".join(lines) + ("\n" if rng.choice([True, False]) else "")).encode())

    rng.shuffle(cases)
    observed_codes = set()
    with tempfile.TemporaryDirectory(prefix=f"diag_validation_{nonce}_") as directory:
        for index, data in enumerate(cases):
            path = os.path.join(directory, f"input_{uuid.uuid4().hex}_{index}.dat")
            with open(path, "wb") as handle:
                handle.write(data)
            expected = oracle_exit_code(data)
            observed_codes.add(expected)
            result = run_sanitizer(path)
            assert result.returncode == expected, (
                f"sanitize.py returned {result.returncode}, expected {expected} for a fresh "
                f"oracle-derived case; stderr={result.stderr.decode(errors='replace')!r}"
            )
    assert observed_codes == {0, 1}, "Generated suite did not exercise both accepted and rejected inputs"


def test_profile_env():
    """Test that DIAG_ENV=production is exported in .profile and reaches child processes."""
    profile_path = "/home/user/.profile"
    assert os.path.exists(profile_path), f"Missing profile at {profile_path}"

    with open(profile_path, "r") as handle:
        content = handle.read()

    assert re.search(r"export\s+DIAG_ENV=[\"']?production[\"']?", content) or \
           re.search(r"DIAG_ENV=[\"']?production[\"']?\s*\n\s*export\s+DIAG_ENV", content), \
           "DIAG_ENV=production is not correctly exported in /home/user/.profile"

    result = subprocess.run(
        ["bash", "--noprofile", "--norc", "-c", ". /home/user/.profile && env"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, f"Failed to source .profile: {result.stderr}"
    environment = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    assert environment.get("DIAG_ENV") == "production", "DIAG_ENV is not exported as production"


def test_audit_script():
    """Test that audit.sh is executable and actually appends the current date."""
    script_path = "/home/user/audit.sh"
    log_path = "/home/user/audit.log"

    assert os.path.exists(script_path), f"Missing script at {script_path}"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"

    before = b""
    if os.path.exists(log_path):
        with open(log_path, "rb") as handle:
            before = handle.read()

    start = int(time.time())
    subprocess.run([script_path], check=True, timeout=5)
    end = int(time.time())

    assert os.path.exists(log_path), f"Log file {log_path} was not created"
    with open(log_path, "rb") as handle:
        after = handle.read()
    assert len(after.strip()) > 0, "Log file is empty, expected date output"
    assert after.startswith(before) and len(after) > len(before), "audit.sh did not append to audit.log"

    appended = after[len(before):].decode(errors="replace")
    appended_lines = [line.strip() for line in appended.splitlines() if line.strip()]
    assert appended_lines, "audit.sh appended no date line"

    valid_current_date = False
    for line in appended_lines:
        parsed = subprocess.run(
            ["date", "-d", line, "+%s"], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        if parsed.returncode == 0:
            try:
                stamp = int(parsed.stdout.strip())
            except ValueError:
                continue
            if start - 5 <= stamp <= end + 5:
                valid_current_date = True
                break
    assert valid_current_date, "audit.sh did not append a parseable current date"


def test_cron_job():
    """Test that cron invokes audit.sh with an exact every-five-minutes schedule."""
    try:
        output = subprocess.check_output(["crontab", "-l"], text=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab for user")

    lines = [line.strip() for line in output.splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    minute_list = "0,5,10,15,20,25,30,35,40,45,50,55"
    found = False
    for line in lines:
        try:
            parts = shlex.split(line, comments=True)
        except ValueError:
            continue
        if len(parts) != 6:
            continue
        schedule = parts[:5]
        every_five = schedule[0] in ("*/5", minute_list) and schedule[1:] == ["*", "*", "*", "*"]
        if every_five and parts[5] == "/home/user/audit.sh":
            found = True
            break

    assert found, "Could not find a valid 5-minute cron job for /home/user/audit.sh in crontab"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
