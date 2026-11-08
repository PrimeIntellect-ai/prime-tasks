#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import base64
import random
import pwd
import subprocess


def get_expected_subject():
    crt_path = "/home/user/server.crt"
    assert os.path.isfile(crt_path), f"Certificate file {crt_path} is missing."
    result = subprocess.run(
        ["openssl", "x509", "-in", crt_path, "-noout", "-subject"],
        capture_output=True,
        text=True,
        check=True
    )
    return result.stdout.strip()


def test_processed_audit_log_contents():
    b64_path = "/home/user/audit_log.b64"
    processed_path = "/home/user/processed_audit.log"

    assert os.path.isfile(b64_path), f"Input file {b64_path} is missing."
    assert os.path.isfile(processed_path), f"Output file {processed_path} is missing."

    with open(b64_path, "r") as f:
        encoded_content = f.read()

    decoded_content = base64.b64decode(encoded_content).decode("utf-8")

    ipv4_pattern = r"\b(?:\d{1,3}\.){3}\d{1,3}\b"
    redacted_content = re.sub(ipv4_pattern, "[REDACTED_IP]", decoded_content)
    needs_warning = "sudo " in decoded_content or "chmod 777" in decoded_content

    expected_lines = redacted_content.splitlines()
    if needs_warning:
        expected_lines.append("WARNING: PRIVILEGE ESCALATION DETECTED")
    expected_lines.append(get_expected_subject())
    expected_output = "\n".join(expected_lines) + "\n"

    with open(processed_path, "r") as f:
        actual_output = f.read()

    assert actual_output.strip() == expected_output.strip(), (
        f"Contents of {processed_path} do not match the expected output.\n"
        f"Expected:\n{expected_output}\n\nActual:\n{actual_output}"
    )


def test_rust_policy_checker_compiles_and_processes_fresh_inputs():
    source_path = "/home/user/policy_checker.rs"
    b64_path = "/home/user/audit_log.b64"
    processed_path = "/home/user/processed_audit.log"
    binary_path = "/tmp/policy_checker_verifier_bin"

    assert os.path.exists(source_path), f"Rust source {source_path} is missing."
    assert not os.path.islink(source_path), f"Rust source {source_path} must be a regular file."
    assert stat.S_ISREG(os.stat(source_path).st_mode), f"Rust source {source_path} must be a regular file."
    assert os.path.getsize(source_path) > 0, f"Rust source {source_path} is empty."

    compile_result = subprocess.run(
        ["rustc", source_path, "-o", binary_path],
        capture_output=True,
        text=True,
        timeout=60
    )
    assert compile_result.returncode == 0, (
        "policy_checker.rs did not compile with rustc.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )
    assert os.path.isfile(binary_path) and os.access(binary_path, os.X_OK), (
        "rustc did not produce an executable policy checker."
    )

    with open(b64_path, "rb") as f:
        original_b64 = f.read()
    with open(processed_path, "rb") as f:
        original_processed = f.read()

    rng = random.SystemRandom()
    ip1 = f"{rng.randint(1, 223)}.{rng.randint(0, 255)}.{rng.randint(0, 255)}.{rng.randint(1, 254)}"
    ip2 = f"{rng.randint(1, 223)}.{rng.randint(0, 255)}.{rng.randint(0, 255)}.{rng.randint(1, 254)}"
    cases = [
        f"Routine connection from {ip1}\nsudoers mentioned but no exact trigger\nchmod 775 /srv/app\n",
        f"Login source {ip2}\nsudo id\nchmod 777 /srv/private\n",
    ]

    user = pwd.getpwnam("user")

    def demote():
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    try:
        for decoded_content in cases:
            with open(b64_path, "wb") as f:
                f.write(base64.b64encode(decoded_content.encode("utf-8")) + b"\n")
            if os.path.exists(processed_path):
                os.remove(processed_path)

            run_result = subprocess.run(
                [binary_path],
                cwd="/home/user",
                capture_output=True,
                text=True,
                timeout=30,
                preexec_fn=demote
            )
            assert run_result.returncode == 0, (
                "Compiled Rust policy checker failed when executed.\n"
                f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
            )
            assert os.path.isfile(processed_path), (
                "Compiled Rust policy checker did not create /home/user/processed_audit.log."
            )

            redacted = re.sub(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", "[REDACTED_IP]", decoded_content)
            expected_lines = redacted.splitlines()
            if "sudo " in decoded_content or "chmod 777" in decoded_content:
                expected_lines.append("WARNING: PRIVILEGE ESCALATION DETECTED")
            expected = "\n".join(expected_lines) + "\n"

            with open(processed_path, "r") as f:
                actual = f.read()
            assert actual.strip() == expected.strip(), (
                "The compiled Rust program did not correctly decode, redact, and audit a fresh input.\n"
                f"Expected:\n{expected}\nActual:\n{actual}"
            )
    finally:
        with open(b64_path, "wb") as f:
            f.write(original_b64)
        with open(processed_path, "wb") as f:
            f.write(original_processed)
        if os.path.exists(binary_path):
            os.remove(binary_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
