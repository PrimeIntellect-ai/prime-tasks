#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import shutil
import string
import subprocess


def test_csp_comment():
    fixed_script = "/home/user/upload_handler_fixed.py"
    assert os.path.isfile(fixed_script), f"Fixed script {fixed_script} does not exist."
    assert not os.path.islink(fixed_script), f"Fixed script {fixed_script} must be a regular file, not a symlink."

    with open(fixed_script, "r") as f:
        first_line = f.readline().strip()

    expected_csp = "# CSP: default-src 'self'; script-src 'none'; object-src 'none'"
    assert first_line == expected_csp, f"Expected first line to be exactly {expected_csp!r}, but got {first_line!r}."


def test_ssh_hardening_script():
    script_path = "/home/user/apply_ssh_hardening.sh"
    assert os.path.isfile(script_path), f"SSH hardening script {script_path} does not exist."
    assert not os.path.islink(script_path), f"SSH hardening script {script_path} must be a regular file, not a symlink."

    with open(script_path, "r") as f:
        content = f.read()

    assert "AllowUsers auditor" in content, "Missing 'AllowUsers auditor' in the SSH hardening script."
    assert "PermitRootLogin no" in content, "Missing 'PermitRootLogin no' in the SSH hardening script."

    config_path = "/etc/ssh/sshd_config"
    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    existed = os.path.exists(config_path)
    original = None
    if existed:
        with open(config_path, "rb") as f:
            original = f.read()

    baseline = b"# verifier baseline\n"
    try:
        with open(config_path, "wb") as f:
            f.write(baseline)

        proc = subprocess.run(
            ["bash", script_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert proc.returncode == 0, (
            f"SSH hardening script failed with code {proc.returncode}: {proc.stderr!r}"
        )

        with open(config_path, "rb") as f:
            resulting = f.read()
        assert resulting.startswith(baseline), "SSH hardening script did not append to the existing configuration."

        appended_text = resulting[len(baseline):].decode("utf-8")
        appended_lines = [line.strip() for line in appended_text.splitlines() if line.strip()]
        assert "AllowUsers auditor" in appended_lines, "The script did not append the exact 'AllowUsers auditor' rule."
        assert "PermitRootLogin no" in appended_lines, "The script did not append the exact 'PermitRootLogin no' rule."
    finally:
        if existed:
            with open(config_path, "wb") as f:
                f.write(original)
        elif os.path.exists(config_path):
            os.remove(config_path)


def clear_uploads_dir():
    uploads_dir = "/home/user/uploads"
    if os.path.exists(uploads_dir):
        shutil.rmtree(uploads_dir)
    os.makedirs(uploads_dir, exist_ok=True)


def get_uploads_state():
    uploads_dir = "/home/user/uploads"
    state = {}
    for root, _, files in os.walk(uploads_dir):
        for filename in files:
            path = os.path.join(root, filename)
            rel_path = os.path.relpath(path, uploads_dir)
            with open(path, "rb") as f:
                state[rel_path] = f.read()
    return state


def remove_escape_target(path):
    uploads = os.path.realpath("/home/user/uploads")
    target = os.path.abspath(path)
    if os.path.commonpath([uploads, target]) == uploads:
        return
    if os.path.isfile(target) or os.path.islink(target):
        os.remove(target)


def expected_result(raw_filename, raw_payload):
    if "/" in raw_filename or "\\" in raw_filename or ".." in raw_filename:
        return 1, "CWE-22 DETECTED\n", {}
    return 0, "", {raw_filename: raw_payload}


def run_case(fixed_script, raw_filename, raw_payload):
    b64_filename = base64.b64encode(raw_filename.encode("utf-8")).decode("ascii")
    b64_payload = base64.b64encode(raw_payload).decode("ascii")
    expected_code, expected_stdout, expected_state = expected_result(raw_filename, raw_payload)

    clear_uploads_dir()
    escape_target = os.path.join("/home/user/uploads", raw_filename)
    remove_escape_target(escape_target)

    proc = subprocess.run(
        ["python3", fixed_script, b64_filename, b64_payload],
        capture_output=True,
        text=True,
        timeout=10,
    )
    actual_state = get_uploads_state()

    assert proc.returncode == expected_code, (
        f"Exit code mismatch on input {raw_filename!r}. Expected: {expected_code}, Agent: {proc.returncode}"
    )
    assert proc.stdout == expected_stdout, (
        f"Stdout mismatch on input {raw_filename!r}. Expected: {expected_stdout!r}, Agent: {proc.stdout!r}"
    )
    assert actual_state == expected_state, (
        f"File system state mismatch in /home/user/uploads/ on input {raw_filename!r}."
    )

    target = os.path.abspath(escape_target)
    uploads = os.path.realpath("/home/user/uploads")
    if os.path.commonpath([uploads, target]) != uploads:
        assert not os.path.exists(target), f"Traversal input created an out-of-directory path: {target}"


def test_fuzz_equivalence():
    fixed_script = "/home/user/upload_handler_fixed.py"
    assert os.path.isfile(fixed_script), f"{fixed_script} is missing."

    random.seed(42)
    traversal_patterns = [
        "../verifier_escape_",
        "..\\verifier_escape_",
        "/tmp/verifier_absolute_",
        "../../verifier_escape_",
        "/tmp/verifier_path_",
        "dir/nested_",
    ]

    for _ in range(500):
        if random.random() < 0.5:
            raw_filename = "".join(
                random.choices(string.ascii_letters + string.digits, k=random.randint(1, 50))
            )
        else:
            prefix = random.choice(traversal_patterns)
            suffix = "".join(
                random.choices(string.ascii_letters + string.digits, k=random.randint(1, 20))
            )
            raw_filename = prefix + suffix

        raw_payload = bytes(random.getrandbits(8) for _ in range(random.randint(1, 100)))
        run_case(fixed_script, raw_filename, raw_payload)


def test_argument_and_decode_failures():
    fixed_script = "/home/user/upload_handler_fixed.py"

    for args in ([], ["only-one-argument"]):
        clear_uploads_dir()
        proc = subprocess.run(
            ["python3", fixed_script, *args],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert proc.returncode == 1
        assert proc.stdout == ""
        assert get_uploads_state() == {}

    clear_uploads_dir()
    valid_name = base64.b64encode(b"valid_name").decode("ascii")
    proc = subprocess.run(
        ["python3", fixed_script, valid_name, "A"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert proc.returncode == 1
    assert proc.stdout == ""
    assert get_uploads_state() == {}
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
