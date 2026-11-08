#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess


def decrypt(enc_file, output_file):
    key_file = "/home/user/certs/audit_key.pem"
    cmd = [
        "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-salt",
        "-in", enc_file,
        "-pass", f"file:{key_file}",
        "-out", output_file,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"Decryption failed: {result.stderr}"
    assert os.path.isfile(output_file), "Decrypted file was not created."


def redact_expected(content):
    return re.sub(r"([?&](?:api_key|card)=)[^&\\s\"]*", r"\1REDACTED", content)


def test_scripts_exist_and_executable():
    """Test that the required scripts exist and are executable."""
    scripts = [
        "/home/user/process_logs.sh",
        "/home/user/run_sandbox.sh"
    ]
    for script in scripts:
        assert os.path.isfile(script), f"Script {script} is missing."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."


def test_sandbox_script_contents():
    """Test that run_sandbox.sh uses bwrap with required security constraints."""
    script_path = "/home/user/run_sandbox.sh"
    with open(script_path, "r") as f:
        content = f.read()

    assert "bwrap" in content, "run_sandbox.sh must use bwrap."
    assert "--unshare-net" in content, "run_sandbox.sh must unshare the network namespace."
    assert "--dev" in content, "run_sandbox.sh must mount /dev."
    assert "--ro-bind" in content, "run_sandbox.sh must use --ro-bind."


def test_encrypted_file_exists():
    """Test that the encrypted audit log was generated."""
    enc_file = "/home/user/audit_trail/secure_audit.log.enc"
    assert os.path.isfile(enc_file), f"Encrypted log file {enc_file} is missing."
    assert os.path.getsize(enc_file) > 0, f"Encrypted log file {enc_file} is empty."
    with open(enc_file, "rb") as f:
        assert f.read(8) == b"Salted__", "Encrypted log must use an OpenSSL salt."


def test_decryption_and_redaction():
    """Test that the file decrypts to the complete, correctly redacted source log."""
    enc_file = "/home/user/audit_trail/secure_audit.log.enc"
    decrypted_file = "/tmp/decrypted.log"
    decrypt(enc_file, decrypted_file)

    try:
        with open(decrypted_file, "r") as f:
            content = f.read()
        with open("/home/user/raw_logs/access.log", "r") as f:
            source = f.read()

        # Preserve the original checks.
        sensitive_data = ["4555666677778888", "AKIAIOSFODNN7EXAMPLE", "SECRET_999", "1234"]
        for secret in sensitive_data:
            assert secret not in content, f"Sensitive data '{secret}' was not redacted."

        assert "card=REDACTED" in content, "Missing 'card=REDACTED' in the logs."
        assert "api_key=REDACTED" in content, "Missing 'api_key=REDACTED' in the logs."

        benign_data = ["item=shoes", "format=json", "user=admin"]
        for benign in benign_data:
            assert benign in content, f"Benign parameter '{benign}' was incorrectly modified or removed."

        assert content == redact_expected(source), \
            "Decrypted audit trail is not the complete redacted access log."
    finally:
        if os.path.exists(decrypted_file):
            os.remove(decrypted_file)


def test_execute_sandbox_on_derived_input_and_validate_bwrap_arguments():
    """Execute the wrapper and verify both behavior and structured bwrap restrictions."""
    raw_path = "/home/user/raw_logs/access.log"
    enc_path = "/home/user/audit_trail/secure_audit.log.enc"
    bwrap_path = "/usr/bin/bwrap"
    capture_path = "/tmp/verifier_bwrap_capture.json"
    decrypted_path = "/tmp/decrypted_dynamic.log"

    dynamic_source = (
        '203.0.113.8 - - [11/Sep/2026:01:02:03 +0000] "GET /x?api_key=DYNAMIC_ALPHA&keep=a%20b&card=987654321&mode=full HTTP/1.1" 200 77\n'
        '198.51.100.9 - - [11/Sep/2026:01:02:04 +0000] "POST /y?foo=one&card=DYNAMIC_BETA&api_key=DYNAMIC_GAMMA HTTP/1.1" 201 88\n'
        '192.0.2.10 - - [11/Sep/2026:01:02:05 +0000] "GET /z?xapi_key=UNCHANGED&cardinal=UNCHANGED&card=LAST_SECRET HTTP/1.1" 200 99\n'
    )

    with open(raw_path, "rb") as f:
        old_raw = f.read()
    old_raw_mode = stat.S_IMODE(os.stat(raw_path).st_mode)
    with open(enc_path, "rb") as f:
        old_enc = f.read()
    old_enc_mode = stat.S_IMODE(os.stat(enc_path).st_mode)
    with open(bwrap_path, "rb") as f:
        old_bwrap = f.read()
    old_bwrap_mode = stat.S_IMODE(os.stat(bwrap_path).st_mode)

    # This executable test double records the actual bwrap argv and runs only the
    # command appearing after valid bwrap options. It avoids dependence on whether
    # the outer test container permits creating nested namespaces.
    shim = r'''#!/usr/bin/python3
import json, os, subprocess, sys
args = sys.argv[1:]
zero = {
 "--help", "--version", "--unshare-all", "--unshare-user",
 "--unshare-user-try", "--unshare-ipc", "--unshare-pid", "--unshare-net",
 "--unshare-uts", "--unshare-cgroup", "--unshare-cgroup-try", "--share-net",
 "--die-with-parent", "--new-session", "--as-pid-1", "--clearenv",
 "--disable-userns", "--assert-userns-disabled"
}
one = {
 "--dev", "--proc", "--tmpfs", "--mqueue", "--dir", "--chdir",
 "--uid", "--gid", "--hostname", "--lock-file", "--sync-fd",
 "--userns", "--userns2", "--pidns", "--info-fd", "--json-status-fd",
 "--remount-ro", "--exec-label", "--file-label", "--seccomp"
}
two = {
 "--bind", "--bind-try", "--dev-bind", "--dev-bind-try", "--ro-bind",
 "--ro-bind-try", "--symlink", "--setenv", "--unsetenv", "--file",
 "--bind-data", "--ro-bind-data", "--perms"
}
i = 0
while i < len(args):
    a = args[i]
    if a == "--":
        i += 1
        break
    if not a.startswith("--"):
        break
    if a in zero:
        i += 1
    elif a in one:
        i += 2
    elif a in two:
        i += 3
    else:
        print("Unsupported or malformed bwrap option: " + a, file=sys.stderr)
        sys.exit(97)
command = args[i:]
with open("/tmp/verifier_bwrap_capture.json", "w") as f:
    json.dump({"args": args, "command": command}, f)
if not command:
    sys.exit(98)
sys.exit(subprocess.run(command).returncode)
'''

    try:
        with open(raw_path, "w") as f:
            f.write(dynamic_source)
        os.chmod(raw_path, old_raw_mode)
        if os.path.exists(enc_path):
            os.remove(enc_path)
        if os.path.exists(capture_path):
            os.remove(capture_path)

        with open(bwrap_path, "w") as f:
            f.write(shim)
        os.chmod(bwrap_path, 0o755)

        result = subprocess.run(
            ["/home/user/run_sandbox.sh"],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, \
            f"run_sandbox.sh failed when executed: {result.stdout}\n{result.stderr}"
        assert os.path.isfile(capture_path), "run_sandbox.sh did not execute bwrap."
        assert os.path.isfile(enc_path) and os.path.getsize(enc_path) > 0, \
            "Executing run_sandbox.sh did not generate the encrypted audit trail."

        with open(capture_path) as f:
            captured = json.load(f)
        args = captured["args"]
        command = captured["command"]

        def has_pair(option, source, destination):
            return any(
                args[i] == option and args[i + 1] == source and args[i + 2] == destination
                for i in range(len(args) - 2)
            )

        def has_single(option, destination):
            return any(
                args[i] == option and args[i + 1] == destination
                for i in range(len(args) - 1)
            )

        assert "--unshare-net" in args, "bwrap invocation must unshare the network namespace."
        assert has_pair("--ro-bind", "/", "/"), \
            "bwrap must mount the entire root filesystem read-only."
        assert has_single("--dev", "/dev"), "bwrap must create a functional /dev tree."
        assert has_pair("--ro-bind", "/home/user/raw_logs", "/home/user/raw_logs"), \
            "raw_logs must be explicitly mounted read-only."
        assert has_pair("--ro-bind", "/home/user/certs", "/home/user/certs"), \
            "certs must be explicitly mounted read-only."
        assert has_pair("--bind", "/home/user/audit_trail", "/home/user/audit_trail"), \
            "audit_trail must be mounted read-write."

        writable_mounts = {"--bind", "--bind-try", "--dev-bind", "--dev-bind-try"}
        for i, arg in enumerate(args[:-2]):
            if arg in writable_mounts:
                destination = os.path.normpath(args[i + 2])
                if destination == "/home/user" or destination.startswith("/home/user/"):
                    assert destination == "/home/user/audit_trail", \
                        f"Unexpected writable user mount: {destination}"
                assert destination != "/", "Root filesystem must not be mounted read-write."
        for i, arg in enumerate(args[:-1]):
            if arg in {"--tmpfs", "--dir"}:
                destination = os.path.normpath(args[i + 1])
                assert not (destination == "/home/user" or destination.startswith("/home/user/")), \
                    f"Unexpected writable user mount: {destination}"

        direct = command == ["/home/user/process_logs.sh"]
        via_shell = (
            len(command) == 2
            and command[0] in {"sh", "bash", "/bin/sh", "/bin/bash", "/usr/bin/bash"}
            and command[1] == "/home/user/process_logs.sh"
        )
        assert direct or via_shell, \
            "The command executed inside bwrap must be /home/user/process_logs.sh."

        with open(enc_path, "rb") as f:
            assert f.read(8) == b"Salted__", "Dynamic output was not salted."
        decrypt(enc_path, decrypted_path)
        with open(decrypted_path) as f:
            actual = f.read()
        assert actual == redact_expected(dynamic_source), \
            "Pipeline output did not exactly preserve and redact the dynamic access log."
        for secret in ["DYNAMIC_ALPHA", "987654321", "DYNAMIC_BETA", "DYNAMIC_GAMMA", "LAST_SECRET"]:
            assert secret not in actual, f"Dynamic secret '{secret}' was not redacted."
        for benign in ["keep=a%20b", "mode=full", "foo=one", "xapi_key=UNCHANGED", "cardinal=UNCHANGED"]:
            assert benign in actual, f"Benign dynamic data '{benign}' was modified or removed."
    finally:
        with open(bwrap_path, "wb") as f:
            f.write(old_bwrap)
        os.chmod(bwrap_path, old_bwrap_mode)
        with open(raw_path, "wb") as f:
            f.write(old_raw)
        os.chmod(raw_path, old_raw_mode)
        with open(enc_path, "wb") as f:
            f.write(old_enc)
        os.chmod(enc_path, old_enc_mode)
        for path in [capture_path, decrypted_path]:
            if os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
