#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess


def run_classifier(classifier_script, input_path):
    try:
        return subprocess.run(
            [classifier_script, str(input_path)],
            capture_output=True,
            timeout=10,
        ).returncode
    except subprocess.TimeoutExpired:
        return None


def test_audit_trail():
    audit_path = "/home/user/audit_trail.txt"
    assert os.path.exists(audit_path), f"Audit trail file {audit_path} is missing."

    with open(audit_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) >= 2, f"Audit trail file {audit_path} does not contain enough lines."

    expected_line_1 = "exploit_payload_v2_bypass"
    expected_line_2 = "iptables -A INPUT -p tcp --dport 8080 -j ACCEPT"

    assert lines[0] == expected_line_1, f"Audit trail Line 1 is incorrect. Expected '{expected_line_1}', got '{lines[0]}'."
    assert lines[1] == expected_line_2, f"Audit trail Line 2 is incorrect. Expected '{expected_line_2}', got '{lines[1]}'."


def test_payload_classifier(tmp_path):
    path_file = "/home/user/classifier_path.txt"
    assert os.path.exists(path_file), f"Classifier path file {path_file} is missing."

    with open(path_file, "r") as f:
        classifier_script = f.read().strip()

    assert os.path.exists(classifier_script), f"Classifier script {classifier_script} is missing."
    assert os.path.isfile(classifier_script), f"Classifier path {classifier_script} is not a file."
    assert os.access(classifier_script, os.X_OK), f"Classifier script {classifier_script} is not executable."

    evil_dir = "/app/corpora/evil/"
    clean_dir = "/app/corpora/clean/"

    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    for evil_file in evil_files:
        if run_classifier(classifier_script, evil_file) != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_files:
        if run_classifier(classifier_script, clean_file) != 0:
            clean_modified.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")

    marker = "exploit_payload_v2_bypass"
    nonce_a = secrets.token_hex(24)
    nonce_b = secrets.token_hex(24)
    cases = [
        (f"{nonce_a}{marker}{nonce_b}\n", 1, "embedded malicious payload"),
        (f"header={secrets.token_hex(12)}\n{marker}\nfooter={secrets.token_hex(12)}\n", 1, "malicious payload on its own line"),
        (f"service_input:{marker}:{secrets.token_hex(20)}", 1, "malicious service input"),
        (f"benign compliance log {secrets.token_hex(32)}\n", 0, "random benign log"),
        (f"regular service input {secrets.token_hex(32)}\n", 0, "random regular input"),
        (f"exploit payload v2 bypass {secrets.token_hex(24)}\n", 0, "non-payload words"),
        (f"exploit_payload_v2_bypas {secrets.token_hex(24)}\n", 0, "near miss"),
        (f"{secrets.token_hex(24)} bypass audit completed successfully\n", 0, "benign bypass audit"),
    ]
    random.SystemRandom().shuffle(cases)

    generated_failures = []
    for content, expected_code, description in cases:
        sample = tmp_path / secrets.token_hex(16)
        sample.write_text(content)
        actual_code = run_classifier(classifier_script, sample)
        if actual_code != expected_code:
            generated_failures.append(
                f"{description}: expected exit {expected_code}, got {actual_code}"
            )

    if generated_failures:
        errors.append("Generated adversarial corpus failures:\n" + "\n".join(generated_failures))

    assert not errors, "Classifier failed:\n" + "\n".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
