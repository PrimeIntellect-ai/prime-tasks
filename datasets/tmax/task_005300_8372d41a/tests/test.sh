#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import stat
import subprocess


def run_python(script_path):
    return subprocess.run(
        ["python3", script_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )


def test_proof_file_exists_content_and_upload_traversal():
    proof_path = "/home/user/proof.txt"
    upload_path = "/home/user/upload.py"

    assert os.path.exists(proof_path), f"File {proof_path} does not exist. The vulnerability was not verified."
    assert os.path.isfile(proof_path), f"{proof_path} is not a file."
    with open(proof_path, "r") as f:
        content = f.read().strip()
    assert content == "VULN_VERIFIED", f"Content of {proof_path} is '{content}', expected 'VULN_VERIFIED'."

    expected_upload = b'''import sys
import os

if len(sys.argv) != 3:
    print("Usage: python upload.py <filename> <content>")
    sys.exit(1)

filename = sys.argv[1]
content = sys.argv[2]
base_dir = "/home/user/uploads"

# Vulnerable: No sanitization of 'filename'
filepath = os.path.join(base_dir, filename)

with open(filepath, 'w') as f:
    f.write(content)
print(f"File saved to {filepath}")
'''
    assert os.path.isfile(upload_path), f"Upload utility {upload_path} is missing or is not a file."
    with open(upload_path, "rb") as f:
        assert f.read() == expected_upload, f"{upload_path} was modified."

    os.unlink(proof_path)
    result = subprocess.run(
        ["python3", upload_path, "../proof.txt", "VULN_VERIFIED"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, f"Traversal invocation failed: {result.stderr}"
    assert os.path.isfile(proof_path), "The traversal invocation did not recreate /home/user/proof.txt."
    with open(proof_path, "rb") as f:
        assert f.read() == b"VULN_VERIFIED", "The traversal invocation wrote incorrect proof content."


def test_hash_script_and_log_exist_correct_and_executable():
    script_path = "/home/user/hash_check.py"
    log_path = "/home/user/hash_log.txt"
    bin_path = "/home/user/suspicious_bin"

    assert os.path.exists(script_path), f"Python script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a regular file."
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."
    assert os.path.exists(bin_path), f"Suspicious binary {bin_path} is missing."

    with open(bin_path, "rb") as f:
        original_payload = f.read()
    expected_hash = hashlib.sha256(original_payload).hexdigest()

    with open(log_path, "r") as f:
        log_content = f.read().strip()
    assert log_content == expected_hash, f"Hash in {log_path} is incorrect. Expected {expected_hash}, got {log_content}."

    # The submitted script itself must create the log for the real payload.
    os.unlink(log_path)
    result = run_python(script_path)
    assert result.returncode == 0, f"Running {script_path} failed: {result.stderr}"
    assert os.path.isfile(log_path), f"Running {script_path} did not create {log_path}."
    with open(log_path, "r") as f:
        regenerated = f.read().strip()
    assert regenerated == expected_hash, f"Running {script_path} generated an incorrect hash."

    # Exercise the script on unpredictable content so a hard-coded log writer cannot pass.
    original_stat = os.stat(bin_path)
    probe_payload = secrets.token_bytes(137)
    probe_hash = hashlib.sha256(probe_payload).hexdigest()
    probe_result = None
    probe_log = None
    try:
        with open(bin_path, "wb") as f:
            f.write(probe_payload)
        if os.path.lexists(log_path):
            os.unlink(log_path)
        probe_result = run_python(script_path)
        if os.path.isfile(log_path):
            with open(log_path, "r") as f:
                probe_log = f.read().strip()
    finally:
        with open(bin_path, "wb") as f:
            f.write(original_payload)
        os.chmod(bin_path, stat.S_IMODE(original_stat.st_mode))
        os.chown(bin_path, original_stat.st_uid, original_stat.st_gid)
        os.utime(bin_path, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns))

        # Restore the required final log using the submitted script.
        if os.path.lexists(log_path):
            os.unlink(log_path)
        run_python(script_path)

    assert probe_result is not None and probe_result.returncode == 0, (
        f"Running {script_path} on probe content failed: "
        f"{probe_result.stderr if probe_result else 'no result'}"
    )
    assert probe_log is not None, f"Running {script_path} on probe content did not create {log_path}."
    assert probe_log == probe_hash, "The hash script did not calculate SHA-256 from the current suspicious_bin content."

    assert os.path.isfile(log_path), f"Final log file {log_path} was not regenerated."
    with open(log_path, "r") as f:
        final_log = f.read().strip()
    assert final_log == expected_hash, f"Final hash in {log_path} is incorrect after script execution."


def test_ssh_directory_permissions():
    ssh_dir = "/home/user/.ssh"
    assert os.path.exists(ssh_dir), f"Directory {ssh_dir} does not exist."
    st = os.stat(ssh_dir)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o700, f"Permissions for {ssh_dir} are {oct(perms)}, expected 0o700."


def test_authorized_keys_permissions():
    keys_file = "/home/user/.ssh/authorized_keys"
    assert os.path.exists(keys_file), f"File {keys_file} does not exist."
    st = os.stat(keys_file)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"Permissions for {keys_file} are {oct(perms)}, expected 0o600."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
