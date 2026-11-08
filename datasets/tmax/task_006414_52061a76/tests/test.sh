#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import pwd
import re
import secrets
import shutil
import subprocess

import pytest

SERVICE_DIR = "/home/user/auth_service"
SOURCE = os.path.join(SERVICE_DIR, "auth_server.cpp")
EXECUTABLE = os.path.join(SERVICE_DIR, "auth_server")
HARNESS = "/tmp/validate_token_harness"


def decode_b64_segment(segment):
    assert re.fullmatch(r"[A-Za-z0-9_+/]*={0,2}", segment), "Token segment is not base64 encoded"
    padded = segment + "=" * ((-len(segment)) % 4)
    try:
        return base64.b64decode(padded, altchars=b"-_", validate=True).decode("utf-8")
    except Exception as exc:
        raise AssertionError(f"Invalid base64 token segment: {exc}")


@pytest.fixture(scope="session", autouse=True)
def build_service_and_harness():
    compile_proc = subprocess.run(
        ["make"], cwd=SERVICE_DIR, capture_output=True, text=True
    )
    assert compile_proc.returncode == 0, f"Compilation failed: {compile_proc.stderr}"
    assert os.path.isfile(EXECUTABLE), "auth_server executable was not created"
    assert os.access(EXECUTABLE, os.X_OK), "auth_server is not executable"

    harness_source = r'''
#define main auth_service_original_main
#include "/home/user/auth_service/auth_server.cpp"
#undef main
#include <cstdlib>
#include <iostream>
#include <string>

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    int depth = std::atoi(argv[2]);
    bool result = validate_token(std::string(argv[1]), depth);
    std::cout << (result ? "VALID\n" : "INVALID\n");
    return result ? 0 : 1;
}
'''
    with open("/tmp/validate_token_harness.cpp", "w") as f:
        f.write(harness_source)
    harness_compile = subprocess.run(
        ["g++", "-O2", "-std=c++11", "/tmp/validate_token_harness.cpp", "-o", HARNESS],
        capture_output=True,
        text=True,
    )
    assert harness_compile.returncode == 0, (
        "Could not build validation harness: " + harness_compile.stderr
    )


def run_harness(token, depth):
    return subprocess.run(
        [HARNESS, token, str(depth)], capture_output=True, text=True, timeout=5
    )


def test_exploit_jwt_exists_and_valid():
    filepath = os.path.join(SERVICE_DIR, "exploit.jwt")
    assert os.path.isfile(filepath), f"{filepath} does not exist"

    with open(filepath, "r") as f:
        content = f.read().strip()

    assert content.count(".") == 2, "Exploit token must have exactly two dots (HEADER.PAYLOAD.SIGNATURE)"
    header_segment, payload_segment, _ = content.split(".")
    assert header_segment, "Exploit header must not be empty"
    assert payload_segment, "Exploit payload must not be empty"

    try:
        header = json.loads(decode_b64_segment(header_segment))
        payload = json.loads(decode_b64_segment(payload_segment))
    except json.JSONDecodeError as exc:
        raise AssertionError(f"Decoded exploit segments must contain JSON: {exc}")

    assert isinstance(header, dict), "Decoded exploit header must be a JSON object"
    assert isinstance(header.get("alg"), str) and header["alg"].lower() == "none", (
        "Exploit header must specify alg=none"
    )
    assert isinstance(payload, dict) and payload.get("role") == "admin", (
        "Exploit payload must claim the admin role"
    )


def test_auth_server_compiled_and_patched():
    with open(os.path.join(SERVICE_DIR, "exploit.jwt"), "r") as f:
        exploit_token = f.read().strip()

    run_proc = subprocess.run(
        [EXECUTABLE, exploit_token], capture_output=True, text=True, timeout=5
    )
    assert run_proc.returncode != 0, "Patched auth_server should exit with a non-zero status when given the exploit token"
    assert "ACCESS DENIED" in run_proc.stdout, "Patched auth_server should output ACCESS DENIED"


def test_algorithm_rejection_and_normal_validation_are_behavioral():
    nonce = secrets.token_hex(16)
    payload = '{"role":"user","nonce":"' + nonce + '"}'

    for alg in ("none", "NONE", ""):
        token = '{"alg":"' + alg + '"}.' + payload + ".VALID_SIG"
        proc = run_harness(token, 2)
        assert proc.returncode != 0, f"validate_token accepted forbidden alg={alg!r}"
        assert "INVALID" in proc.stdout

    valid_token = '{"alg":"HS256"}.' + payload + ".VALID_SIG"
    valid_proc = run_harness(valid_token, 2)
    assert valid_proc.returncode == 0, "A valid signed token with sufficient chain depth must remain valid"
    assert "VALID" in valid_proc.stdout

    bad_signature = '{"alg":"HS256"}.' + payload + ".BAD_" + secrets.token_hex(8)
    bad_proc = run_harness(bad_signature, 2)
    assert bad_proc.returncode != 0, "Invalid signatures must not be accepted"


def test_cert_chain_validation():
    nonce = secrets.token_hex(16)
    valid_sig_token = '{"alg":"HS256"}.{"role":"user","nonce":"' + nonce + '"}.VALID_SIG'

    run_proc = subprocess.run(
        [EXECUTABLE, valid_sig_token], capture_output=True, text=True, timeout=5
    )
    assert run_proc.returncode != 0, "Patched auth_server should reject tokens if cert chain depth < 2"
    assert "ACCESS DENIED" in run_proc.stdout, "Patched auth_server should output ACCESS DENIED for insufficient cert chain depth"

    depth_one = run_harness(valid_sig_token, 1)
    assert depth_one.returncode != 0, "verify_cert_chain must reject depth 1"
    depth_zero = run_harness(valid_sig_token, 0)
    assert depth_zero.returncode != 0, "verify_cert_chain must reject depth 0"
    depth_two = run_harness(valid_sig_token, 2)
    assert depth_two.returncode == 0, "verify_cert_chain must permit depth 2 for an otherwise valid token"


def parse_bwrap_command(argv):
    zero_arg = {
        "--unshare-all", "--unshare-user", "--unshare-user-try", "--unshare-ipc",
        "--unshare-pid", "--unshare-net", "--unshare-uts", "--unshare-cgroup",
        "--unshare-cgroup-try", "--share-net", "--disable-userns",
        "--assert-userns-disabled", "--die-with-parent", "--new-session",
        "--clearenv", "--as-pid-1",
    }
    one_arg = {
        "--args", "--userns", "--userns2", "--pidns", "--uid", "--gid",
        "--hostname", "--chdir", "--unsetenv", "--lock-file", "--sync-fd",
        "--block-fd", "--remount-ro", "--proc", "--dev", "--tmpfs", "--mqueue",
        "--dir", "--seccomp", "--add-seccomp-fd", "--exec-label", "--file-label",
        "--cap-add", "--cap-drop", "--perms", "--size",
    }
    two_arg = {
        "--setenv", "--bind", "--bind-try", "--dev-bind", "--dev-bind-try",
        "--ro-bind", "--ro-bind-try", "--file", "--bind-data", "--ro-bind-data",
        "--symlink",
    }

    parsed = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--":
            i += 1
            break
        if not arg.startswith("--"):
            break
        if arg in zero_arg:
            parsed.append((arg,))
            i += 1
        elif arg in one_arg:
            assert i + 1 < len(argv), f"Missing argument for {arg}"
            parsed.append((arg, argv[i + 1]))
            i += 2
        elif arg in two_arg:
            assert i + 2 < len(argv), f"Missing arguments for {arg}"
            parsed.append((arg, argv[i + 1], argv[i + 2]))
            i += 3
        else:
            raise AssertionError(f"Unrecognized bwrap option in sandbox script: {arg}")
    return parsed, argv[i:]


def test_start_sandboxed_sh():
    filepath = os.path.join(SERVICE_DIR, "start_sandboxed.sh")
    assert os.path.isfile(filepath), f"{filepath} does not exist"
    assert os.access(filepath, os.X_OK), f"{filepath} is not executable"

    with open(filepath, "r") as f:
        content = f.read()

    assert "bwrap" in content, "Script must use bwrap"
    assert "--ro-bind / /" in content, "Script must bind mount / as read-only"
    assert "--tmpfs /tmp" in content, "Script must provide a tmpfs at /tmp"
    assert "--unshare-all" in content, "Script must unshare all namespaces"
    assert "./auth_server" in content, "Script must execute ./auth_server"
    assert "--dev /dev" in content, "Script must bind mount /dev"
    assert "--proc /proc" in content, "Script must bind mount /proc"

    real_bwrap = shutil.which("bwrap")
    assert real_bwrap, "bwrap is not installed"
    backup = real_bwrap + ".verifier-backup"
    log_path = "/tmp/bwrap-argv-" + secrets.token_hex(12) + ".json"
    wrapper = "#!/usr/bin/python3\nimport json,sys\nwith open(" + repr(log_path) + ", 'w') as f: json.dump(sys.argv[1:], f)\n"

    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    assert not os.path.exists(backup), "Unexpected stale bwrap verifier backup"
    os.rename(real_bwrap, backup)
    try:
        with open(real_bwrap, "w") as f:
            f.write(wrapper)
        os.chmod(real_bwrap, 0o755)
        proc = subprocess.run(
            [filepath],
            cwd=SERVICE_DIR,
            capture_output=True,
            text=True,
            timeout=10,
            preexec_fn=demote,
        )
    finally:
        if os.path.exists(real_bwrap):
            os.unlink(real_bwrap)
        os.rename(backup, real_bwrap)

    assert proc.returncode == 0, f"Sandbox launcher failed: {proc.stderr}"
    assert os.path.isfile(log_path), "The sandbox script did not actually invoke bwrap"
    with open(log_path, "r") as f:
        argv = json.load(f)
    os.unlink(log_path)

    options, command = parse_bwrap_command(argv)
    assert ("--ro-bind", "/", "/") in options, "bwrap must read-only bind / to /"
    assert ("--dev", "/dev") in options, "bwrap must mount /dev"
    assert ("--proc", "/proc") in options, "bwrap must mount /proc"
    assert ("--tmpfs", "/tmp") in options, "bwrap must mount a writable tmpfs at /tmp"
    assert ("--unshare-all",) in options, "bwrap must unshare all namespaces"
    assert ("--uid", str(account.pw_uid)) in options, "bwrap must use the current user's UID"
    assert ("--gid", str(account.pw_gid)) in options, "bwrap must use the current user's GID"
    assert command and command[0] == "./auth_server", "bwrap must execute ./auth_server as its command"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
