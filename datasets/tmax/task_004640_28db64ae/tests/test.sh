#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fnmatch
import json
import os
import secrets
import shlex
import stat
import subprocess
import tempfile
import textwrap
import threading
import time

import pytest

PASSPHRASE_FILE = "/home/user/leaked_passphrase.txt"
EXPECTED_PASSPHRASE = "Omega$hield2024"
RUST_PROJECT_DIR = "/home/user/rusty_scanner"
RUST_BIN = os.path.join(RUST_PROJECT_DIR, "target/debug/rusty_scanner")
SSH_CONFIG = "/home/user/.ssh/config"


def ensure_binary():
    if not os.path.isfile(RUST_BIN):
        subprocess.run(["cargo", "build"], cwd=RUST_PROJECT_DIR, check=True)


def host_block_matches(patterns, hostname):
    positive_match = False
    for pattern in patterns:
        negated = pattern.startswith("!")
        candidate = pattern[1:] if negated else pattern
        if fnmatch.fnmatchcase(hostname.lower(), candidate.lower()):
            if negated:
                return False
            positive_match = True
    return positive_match


def effective_hardening_values(path, hostname="verifier-target.invalid"):
    # OpenSSH-style parsing for active lines and Host blocks. OpenSSH uses the
    # first obtained value for each keyword, so retain only the first applicable
    # occurrence.
    applicable = True
    values = {}
    with open(path, "r", encoding="utf-8") as config:
        for raw_line in config:
            try:
                fields = shlex.split(raw_line, comments=True, posix=True)
            except ValueError as exc:
                pytest.fail(f"Malformed SSH config line {raw_line!r}: {exc}")
            if not fields:
                continue
            keyword = fields[0].lower()
            if keyword == "host":
                assert len(fields) > 1, "Host directive must include a pattern"
                applicable = host_block_matches(fields[1:], hostname)
                continue
            if applicable and keyword in ("permitrootlogin", "passwordauthentication"):
                assert len(fields) == 2, f"Malformed active {fields[0]} directive"
                values.setdefault(keyword, fields[1].lower())
    return values


def make_fake_ssh(base_dir):
    fake_dir = os.path.join(base_dir, "fake-bin")
    os.makedirs(fake_dir)
    fake_ssh = os.path.join(fake_dir, "ssh")
    script = r'''#!/usr/bin/python3
import json
import os
import stat
import subprocess
import sys
import time

with open(os.environ["FAKE_SECRET_FILE"], "rb") as handle:
    secret = handle.read()
stdin_data = sys.stdin.buffer.read()
argv = sys.argv[1:]

argv_leak = any(secret in arg.encode() for arg in argv)
env_leak = any(secret in value.encode() for value in os.environ.values())
methods = []
if secret in stdin_data:
    methods.append("stdin")

# Accept a securely permissioned temporary passphrase file supplied either as
# an argument or by path in the environment.
for candidate in list(argv) + list(os.environ.values()):
    try:
        info = os.stat(candidate)
        if stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o600:
            with open(candidate, "rb") as handle:
                if secret in handle.read():
                    methods.append("secure-file")
    except (OSError, ValueError):
        pass

# Also support the standard SSH_ASKPASS design when the helper itself does not
# receive the passphrase through argv or the environment.
askpass = os.environ.get("SSH_ASKPASS")
if askpass and os.path.isfile(askpass) and os.access(askpass, os.X_OK):
    try:
        output = subprocess.run(
            [askpass, "Enter passphrase:"], stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, timeout=2, check=False
        ).stdout
        if secret in output:
            methods.append("askpass")
    except Exception:
        pass

record = {
    "argv": argv,
    "argv_leak": argv_leak,
    "env_leak": env_leak,
    "methods": sorted(set(methods)),
}
encoded = (json.dumps(record) + "\n").encode()
fd = os.open(os.environ["FAKE_SSH_LOG"], os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
os.write(fd, encoded)
os.close(fd)
# Remain visible long enough for aggressive /proc polling.
time.sleep(0.08)
sys.exit(0)
'''
    with open(fake_ssh, "w", encoding="utf-8") as handle:
        handle.write(textwrap.dedent(script))
    os.chmod(fake_ssh, 0o755)
    return fake_dir


def fake_environment(base_dir, secret):
    fake_dir = make_fake_ssh(base_dir)
    secret_file = os.path.join(base_dir, "expected-secret")
    log_file = os.path.join(base_dir, "ssh-log.jsonl")
    with open(secret_file, "w", encoding="utf-8") as handle:
        handle.write(secret)
    os.chmod(secret_file, 0o600)
    env = os.environ.copy()
    env["PATH"] = fake_dir + os.pathsep + env.get("PATH", "")
    env["FAKE_SECRET_FILE"] = secret_file
    env["FAKE_SSH_LOG"] = log_file
    return env, log_file


def read_records(log_file):
    if not os.path.isfile(log_file):
        return []
    with open(log_file, "r", encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def assert_valid_ssh_record(records, key_path, target):
    assert records, "Scanner succeeded without spawning the test SSH executable"
    for record in records:
        argv = record["argv"]
        assert not record["argv_leak"], "Passphrase was placed in the SSH command line"
        assert not record["env_leak"], "Passphrase was exposed through the SSH environment"
        assert record["methods"], "Passphrase was not supplied to SSH via stdin, SSH_ASKPASS, or a secure 0600 file"
        assert any(target in arg for arg in argv), "SSH invocation did not use the requested target"
        assert any(key_path == arg or key_path in arg for arg in argv), "SSH invocation did not use the requested key"


def test_passphrase_extracted():
    assert os.path.isfile(PASSPHRASE_FILE), f"Passphrase file missing at {PASSPHRASE_FILE}"
    with open(PASSPHRASE_FILE, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_PASSPHRASE, f"Expected passphrase '{EXPECTED_PASSPHRASE}', got '{content}'"


def test_ssh_config_hardened():
    assert os.path.isfile(SSH_CONFIG), f"SSH config missing at {SSH_CONFIG}"
    with open(SSH_CONFIG, "r") as f:
        content = f.read().lower()

    # Retain the original content assertions.
    assert "permitrootlogin no" in content, "SSH config must disable root login (PermitRootLogin no)"
    assert "passwordauthentication no" in content, "SSH config must enforce key-based auth (PasswordAuthentication no)"

    # Ensure the required settings are active directives applicable to a normal
    # host, rather than comments or directives hidden in an unrelated Host block.
    values = effective_hardening_values(SSH_CONFIG)
    assert values.get("permitrootlogin") == "no", "PermitRootLogin no must be an active, applicable directive"
    assert values.get("passwordauthentication") == "no", "PasswordAuthentication no must be an active, applicable directive"


def test_rust_compiles():
    result = subprocess.run(
        ["cargo", "build"],
        cwd=RUST_PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    assert result.returncode == 0, f"Rust project failed to compile:\n{result.stderr.decode()}"
    assert os.path.isfile(RUST_BIN), f"Compiled binary not found at {RUST_BIN}"


def test_rust_permission_check(tmp_path):
    ensure_binary()
    dummy_key = tmp_path / "id_rsa_test"
    dummy_key.write_text("dummy key content")

    # Retain the original 0644 rejection assertion and additionally ensure SSH
    # is not attempted before the permission check rejects the key.
    dummy_key.chmod(0o644)
    bad_secret = "bad-" + secrets.token_urlsafe(18)
    bad_dir = tempfile.mkdtemp(dir=str(tmp_path))
    bad_env, bad_log = fake_environment(bad_dir, bad_secret)
    result_644 = subprocess.run(
        [RUST_BIN, "--key", str(dummy_key), "--passphrase", bad_secret, "--target", "127.0.0.1"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=bad_env,
        timeout=5
    )
    assert result_644.returncode != 0, "Scanner should abort when key file permissions are 0644"
    assert read_records(bad_log) == [], "Scanner attempted SSH before rejecting a 0644 key"

    # A correctly permissioned key must take the real success path, invoke SSH,
    # use the requested key/target, and deliver the passphrase securely.
    dummy_key.chmod(0o600)
    good_secret = "good-" + secrets.token_urlsafe(18)
    good_dir = tempfile.mkdtemp(dir=str(tmp_path))
    good_env, good_log = fake_environment(good_dir, good_secret)
    result_600 = subprocess.run(
        [RUST_BIN, "--key", str(dummy_key), "--passphrase", good_secret, "--target", "valid-target.invalid"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=good_env,
        timeout=5
    )
    assert result_600.returncode == 0, f"Scanner should succeed with a 0600 key: {result_600.stderr.decode()}"
    assert_valid_ssh_record(read_records(good_log), str(dummy_key), "valid-target.invalid")


def test_leak_rate(tmp_path):
    ensure_binary()
    num_runs = 50
    leaks_detected = 0

    dummy_key = tmp_path / "valid_id_rsa"
    dummy_key.write_text("dummy")
    dummy_key.chmod(0o600)

    for run_number in range(num_runs):
        test_passphrase = "proc-secret-" + secrets.token_urlsafe(24)
        run_dir = tempfile.mkdtemp(dir=str(tmp_path))
        env, log_file = fake_environment(run_dir, test_passphrase)
        stop_event = threading.Event()
        scanner_pid = {None}
        leaked_this_run = [False]

        def monitor_proc():
            while not stop_event.is_set():
                try:
                    for pid_text in os.listdir("/proc"):
                        if not pid_text.isdigit() or int(pid_text) == scanner_pid[0]:
                            continue
                        for proc_file in ("cmdline", "environ"):
                            try:
                                with open(f"/proc/{pid_text}/{proc_file}", "rb") as handle:
                                    if test_passphrase.encode() in handle.read():
                                        leaked_this_run[0] = True
                            except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
                                pass
                except OSError:
                    pass
                time.sleep(0.002)

        process = subprocess.Popen(
            [RUST_BIN, "--key", str(dummy_key), "--passphrase", test_passphrase,
             "--target", f"target-{run_number}.invalid"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            env=env
        )
        scanner_pid[0] = process.pid
        monitor_thread = threading.Thread(target=monitor_proc)
        monitor_thread.start()
        try:
            returncode = process.wait(timeout=5)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            stop_event.set()
            monitor_thread.join()

        assert returncode == 0, "Scanner must complete successfully with a valid 0600 key"
        records = read_records(log_file)
        assert_valid_ssh_record(records, str(dummy_key), f"target-{run_number}.invalid")
        if leaked_this_run[0]:
            leaks_detected += 1

    leak_rate = leaks_detected / num_runs
    assert leak_rate <= 0.0, f"Metric leak_rate {leak_rate} > threshold 0.0. Passphrase leaked {leaks_detected} times out of {num_runs} runs."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
