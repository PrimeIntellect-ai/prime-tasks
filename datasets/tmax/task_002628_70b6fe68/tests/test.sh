#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/policy_check.sh"
SALT = b"s3cr3t_S@lt_99"


def invoke(path):
    return subprocess.run(
        ["bash", SCRIPT_PATH, path],
        capture_output=True,
        timeout=10,
    )


def test_adversarial_corpus():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    evil_bypassed = []

    for cf in clean_files:
        result = invoke(cf)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    for ef in evil_files:
        result = invoke(ef)
        if result.returncode == 0:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean rejected: {', '.join(clean_failed)}")

    assert not errors, " | ".join(errors)


def test_generated_hidden_cases():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    case_dir = tempfile.mkdtemp(prefix="policy_cases_")
    cases = []

    def add_case(payload, expected, signature=None):
        payload_bytes = payload.encode("utf-8")
        if signature is None:
            signature = hashlib.sha256(payload_bytes + SALT).hexdigest()
        path = os.path.join(case_dir, secrets.token_hex(16) + ".py")
        with open(path, "wb") as f:
            f.write(b"# SIGNATURE: " + signature.encode("ascii") + b"\n")
            f.write(payload_bytes)
        cases.append((path, expected))

    # Valid, dynamically signed benign files with varying payloads.
    for i in range(6):
        nonce = secrets.token_hex(20)
        if i % 2:
            payload = f'import subprocess\nvalue = "{nonce}"\nsubprocess.run(["printf", "%s", value], shell=False)\n'
        else:
            payload = f'value = "{nonce}"\nprint(value)\n'
        add_case(payload, 0)

    # Benign payloads carrying plausible but incorrect, non-constant signatures.
    for _ in range(5):
        nonce = secrets.token_hex(20)
        payload = f'value = "{nonce}"\nprint(value)\n'
        correct = hashlib.sha256(payload.encode("utf-8") + SALT).hexdigest()
        wrong = secrets.token_hex(32)
        while wrong == correct:
            wrong = secrets.token_hex(32)
        add_case(payload, 1, wrong)

    # Correctly signed OS-command-injection cases.
    for _ in range(4):
        nonce = secrets.token_hex(12)
        add_case(f'import os\ncommand = "echo {nonce}"\nos.system(command)\n', 1)

    shell_payloads = [
        'import subprocess\nsubprocess.run("echo generated", shell=True)\n',
        'import subprocess\nsubprocess.call("echo generated", shell = True)\n',
        'from subprocess import Popen\nPopen("echo generated", shell= True)\n',
        'import subprocess\nsubprocess.Popen("echo generated", shell =True)\n',
    ]
    for payload in shell_payloads:
        add_case(payload + f'# {secrets.token_hex(12)}\n', 1)

    random.SystemRandom().shuffle(cases)
    failures = []
    for path, expected in cases:
        result = invoke(path)
        if result.returncode != expected:
            failures.append(
                f"{os.path.basename(path)} expected exit {expected}, got {result.returncode}"
            )

    assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
