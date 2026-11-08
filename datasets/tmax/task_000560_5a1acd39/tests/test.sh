#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess


def test_tampered_file_identified():
    tampered_file_path = "/home/user/tampered_file.txt"
    assert os.path.isfile(tampered_file_path), f"File {tampered_file_path} is missing."

    with open(tampered_file_path, "r") as f:
        content = f.read().strip()

    assert content == "sysctl.conf", f"Expected 'sysctl.conf' in {tampered_file_path}, but found '{content}'."


def test_recover_cpp_exists():
    recover_cpp_path = "/home/user/recover.cpp"
    assert os.path.isfile(recover_cpp_path), f"C++ source file {recover_cpp_path} is missing."


def test_decrypted_payload_correct():
    decrypted_payload_path = "/home/user/decrypted_payload.txt"
    assert os.path.isfile(decrypted_payload_path), f"File {decrypted_payload_path} is missing."

    with open(decrypted_payload_path, "r") as f:
        content = f.read().strip()

    expected_payload = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAmaliciouskey attacker@host"
    assert content == expected_payload, f"Expected decrypted payload to be '{expected_payload}', but got '{content}'."


def test_recovery_implementation_compiles_and_decodes_fresh_input():
    source = "/home/user/recover.cpp"
    executable = "/home/user/recover"
    evidence_file = "/home/user/evidence/system_files/sysctl.conf"
    cmdline_file = "/home/user/evidence/proc_cmdline.log"
    output_file = "/home/user/decrypted_payload.txt"

    build = subprocess.run(
        ["g++", source, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"recover.cpp did not compile:\n{build.stderr}"
    assert os.path.isfile(executable) and os.access(executable, os.X_OK)

    with open(cmdline_file, "rb") as f:
        argv = [part.decode("utf-8") for part in f.read().split(b"\0") if part]
    assert len(argv) >= 3, f"Malformed proc_cmdline.log: expected executable, payload path, and key; got {argv!r}"
    try:
        key = int(argv[-1], 10)
    except ValueError:
        raise AssertionError(f"Malformed proc_cmdline.log: final argument is not an integer key: {argv[-1]!r}")
    assert 0 <= key <= 255, f"Key {key} cannot be used as a byte-wise XOR key"

    with open(evidence_file, "rb") as f:
        original_evidence = f.read()
    original_output = None
    if os.path.exists(output_file):
        with open(output_file, "rb") as f:
            original_output = f.read()

    probe_plaintext = b"ssh-ed25519 AAAA7f3c91e2b6485da0 verifier@host"
    probe_hex = bytes(byte ^ key for byte in probe_plaintext).hex().encode("ascii")
    replacement = b"===BEGIN PAYLOAD===\n" + probe_hex + b"\n===END PAYLOAD==="
    modified_evidence, count = re.subn(
        rb"===BEGIN PAYLOAD===.*?===END PAYLOAD===",
        replacement,
        original_evidence,
        count=1,
        flags=re.DOTALL,
    )
    assert count == 1, "The payload markers are missing from sysctl.conf"

    ciphertext_file = "/tmp/recovery_probe.hex"
    with open(ciphertext_file, "wb") as f:
        f.write(probe_hex + b"\n")

    invocations = [
        [executable],
        [executable, evidence_file, str(key)],
        [executable, str(key), evidence_file],
        [executable, probe_hex.decode("ascii"), str(key)],
        [executable, str(key), probe_hex.decode("ascii")],
        [executable, ciphertext_file, str(key)],
        [executable, evidence_file, str(key), output_file],
    ]

    decoded = False
    diagnostics = []
    try:
        with open(evidence_file, "wb") as f:
            f.write(modified_evidence)

        for command in invocations:
            try:
                if os.path.exists(output_file):
                    os.remove(output_file)
                run = subprocess.run(
                    command,
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=5,
                )
                file_result = None
                if os.path.isfile(output_file):
                    with open(output_file, "rb") as f:
                        file_result = f.read().strip()
                if file_result == probe_plaintext or run.stdout.strip() == probe_plaintext:
                    decoded = True
                    break
                diagnostics.append((command[1:], run.returncode, run.stdout[:100], run.stderr[:100]))
            except (subprocess.TimeoutExpired, OSError) as exc:
                diagnostics.append((command[1:], type(exc).__name__))
    finally:
        with open(evidence_file, "wb") as f:
            f.write(original_evidence)
        if original_output is None:
            if os.path.exists(output_file):
                os.remove(output_file)
        else:
            with open(output_file, "wb") as f:
                f.write(original_output)
        if os.path.exists(ciphertext_file):
            os.remove(ciphertext_file)

    assert decoded, "The compiled recovery program did not decode a fresh XOR-encrypted payload; attempts: %r" % (diagnostics,)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
