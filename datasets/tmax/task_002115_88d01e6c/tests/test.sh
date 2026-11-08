#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import subprocess


def run_program(exe_path, token, filename, content):
    try:
        return subprocess.run(
            [exe_path, token, filename, content],
            capture_output=True,
            text=True,
            timeout=2,
        )
    except subprocess.TimeoutExpired:
        return None


def test_patched_upload_program():
    patched_file = "/home/user/src/upload_patched.c"
    assert os.path.isfile(patched_file), (
        f"Patched file {patched_file} not found. The service must be patched and saved to this path."
    )

    exe_path = "/tmp/upload_patched"
    compile_res = subprocess.run(
        ["gcc", patched_file, "-o", exe_path],
        capture_output=True,
        text=True,
    )
    assert compile_res.returncode == 0, (
        f"Compilation of {patched_file} failed:\n{compile_res.stderr}"
    )

    extracted_text = "R0t4t10n_K3y_2024"
    old_token = "OLD_c0mpr0m1s3d_t0k3n"
    expected_token = hashlib.sha256(
        f"{extracted_text}:{old_token}".encode()
    ).hexdigest()

    upload_dir = "/tmp/uploads"
    shutil.rmtree(upload_dir, ignore_errors=True)
    os.makedirs(upload_dir)

    nonce = secrets.token_hex(12)
    benign_files = [f"valid_upload_{nonce}_{i}.txt" for i in range(25)]

    correct_responses = 0
    total_requests = 50

    # Exercise the documented four-argument interface and verify uploaded bytes.
    for i, fname in enumerate(benign_files):
        content = f"upload-{nonce}-{i}\nline two with spaces !@#$%^&*()"
        destination = os.path.join(upload_dir, fname)
        res = run_program(exe_path, expected_token, fname, content)
        if (
            res is not None
            and res.returncode == 0
            and os.path.isfile(destination)
            and open(destination, "r", encoding="utf-8").read() == content
        ):
            correct_responses += 1

    # Make traversal paths resolvable so vulnerable code cannot pass merely because
    # fopen fails for a missing intermediate directory.
    os.makedirs(os.path.join(upload_dir, "dir"), exist_ok=True)
    os.makedirs(os.path.join(upload_dir, "some_dir"), exist_ok=True)
    os.makedirs(os.path.join(upload_dir, "another_dir"), exist_ok=True)
    os.makedirs(os.path.join(upload_dir, "...."), exist_ok=True)

    malicious_cases = []
    for i in range(5):
        outside1 = f"/tmp/verifier_outside_{nonce}_{i}"
        outside2 = f"/tmp/verifier_outside2_{nonce}_{i}"
        absolute = f"/tmp/verifier_absolute_{nonce}_{i}"
        dotted = os.path.join(upload_dir, "....", f"multiple_{nonce}_{i}.txt")
        internal = os.path.join(upload_dir, f"target_{nonce}_{i}")
        malicious_cases.extend([
            (f"../verifier_outside_{nonce}_{i}", outside1),
            (f"dir/../../verifier_outside2_{nonce}_{i}", outside2),
            (absolute, absolute),
            (f"....//multiple_{nonce}_{i}.txt", dotted),
            (f"some_dir/../another_dir/../target_{nonce}_{i}", internal),
        ])

    sentinel = f"sentinel-{nonce}"
    for fname, resolved_target in malicious_cases:
        os.makedirs(os.path.dirname(resolved_target), exist_ok=True)
        with open(resolved_target, "w", encoding="utf-8") as f:
            f.write(sentinel)

        res = run_program(exe_path, expected_token, fname, f"ATTACK-{nonce}")
        unchanged = open(resolved_target, "r", encoding="utf-8").read() == sentinel
        if res is not None and res.returncode != 0 and unchanged:
            correct_responses += 1

    accuracy = correct_responses / total_requests
    assert accuracy == 1.0, (
        f"Security and functionality accuracy is {accuracy} (Threshold: 1.0). "
        f"Passed {correct_responses}/{total_requests} tests. "
        "Ensure the patch strictly rejects filenames containing '../' or starting with '/', "
        "correctly validates the new SHA-256 token, and preserves uploaded content."
    )

    # Invalid credentials, including the compromised token, must be rejected and
    # must not create or alter an upload.
    invalid_tokens = [old_token, secrets.token_hex(32)]
    for i, invalid_token in enumerate(invalid_tokens):
        fname = f"invalid_auth_{nonce}_{i}.txt"
        destination = os.path.join(upload_dir, fname)
        assert not os.path.exists(destination)
        res = run_program(exe_path, invalid_token, fname, f"unauthorized-{nonce}")
        assert res is not None and res.returncode != 0, (
            "The service accepted an invalid or compromised authentication token."
        )
        assert not os.path.exists(destination), (
            "The service wrote upload content despite failed authentication."
        )


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
