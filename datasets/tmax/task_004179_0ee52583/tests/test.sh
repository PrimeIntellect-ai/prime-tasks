#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
from pathlib import Path
import random
import secrets
import signal
import socket
import subprocess
import time

import pytest

SCRIPT = "/home/user/filter.py"
CLEAN_DIR = "/home/user/corpus/clean"
EVIL_DIR = "/home/user/corpus/evil"
WORDLIST = Path("/home/user/wordlist.txt")


def run_filter(token, timeout=10):
    return subprocess.run(
        ["python3", SCRIPT],
        input=token.encode("ascii") + b"\n",
        capture_output=True,
        timeout=timeout,
    )


def test_filter_script_exists():
    assert os.path.isfile(SCRIPT), f"Missing filter script: {SCRIPT}"
    assert WORDLIST.is_file(), f"Missing wordlist: {WORDLIST}"


def test_adversarial_corpus():
    assert os.path.isdir(CLEAN_DIR), f"Missing clean corpus directory: {CLEAN_DIR}"
    assert os.path.isdir(EVIL_DIR), f"Missing evil corpus directory: {EVIL_DIR}"

    clean_files = sorted(
        f for f in os.listdir(CLEAN_DIR)
        if os.path.isfile(os.path.join(CLEAN_DIR, f))
    )
    evil_files = sorted(
        f for f in os.listdir(EVIL_DIR)
        if os.path.isfile(os.path.join(EVIL_DIR, f))
    )

    assert clean_files, "Clean corpus must not be empty"
    assert evil_files, "Evil corpus must not be empty"

    clean_modified = []
    evil_bypassed = []

    for f in clean_files:
        path = os.path.join(CLEAN_DIR, f)
        with open(path, "rb") as stdin_f:
            res = subprocess.run(["python3", SCRIPT], stdin=stdin_f, capture_output=True)
            if res.returncode != 0:
                clean_modified.append(f)

    for f in evil_files:
        path = os.path.join(EVIL_DIR, f)
        with open(path, "rb") as stdin_f:
            res = subprocess.run(["python3", SCRIPT], stdin=stdin_f, capture_output=True)
            if res.returncode == 0:
                evil_bypassed.append(f)

    errors = []
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_bypassed)
        )
    if clean_modified:
        errors.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified: "
            + ", ".join(clean_modified)
        )
    if errors:
        pytest.fail(" | ".join(errors))


SERVER_SOURCE = r'''
import socket
import sys
import threading

valid = set(open(sys.argv[1], encoding="ascii").read().splitlines())
port = int(sys.argv[2])


def handle(conn):
    try:
        data = b""
        while b"\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
        token = data.split(b"\n", 1)[0].decode("ascii", "strict")
        conn.sendall(b"VALID\n" if token in valid else b"INVALID\n")
    except Exception:
        try:
            conn.sendall(b"INVALID\n")
        except Exception:
            pass
    finally:
        conn.close()


server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", port))
server.listen(32)
while True:
    conn, _ = server.accept()
    threading.Thread(target=handle, args=(conn,), daemon=True).start()
'''


def make_token(username, key, password_hash, signature=None):
    if signature is None:
        signature = secrets.token_hex(32)
    raw = f"{username}|{key}|{password_hash}|{signature}"
    return base64.b64encode(raw.encode("utf-8")).decode("ascii")


def stop_legacy_daemon():
    me = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            cmdline = Path(f"/proc/{entry}/cmdline").read_bytes()
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if b"/app/auth_daemon" in cmdline:
            try:
                os.kill(int(entry), signal.SIGKILL)
            except ProcessLookupError:
                pass
    time.sleep(0.25)


def choose_port():
    ports = list(range(8000, 9001))
    random.SystemRandom().shuffle(ports)
    for port in ports:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            s.bind(("127.0.0.1", port))
            return port
        except OSError:
            pass
        finally:
            s.close()
    raise AssertionError("No free oracle port in the required range")


def test_randomized_policy_and_daemon_checks():
    original_wordlist = WORDLIST.read_bytes()
    server_proc = None

    nonce = secrets.token_hex(8)
    weak_words = [f"verifier-weak-{nonce}-{i}" for i in range(8)]
    weak_hashes = {hashlib.sha256(w.encode()).hexdigest() for w in weak_words}
    good_keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI" + secrets.token_hex(8),
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTY" + secrets.token_hex(8),
    ]
    bad_keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB" + secrets.token_hex(8),
        "ssh-dss AAAAB3NzaC1kc3MAAACB" + secrets.token_hex(8),
    ]

    def strong_hash():
        while True:
            digest = hashlib.sha256(secrets.token_bytes(40)).hexdigest()
            if digest not in weak_hashes:
                return digest

    accepted = []
    rejected = []
    daemon_valid = set()

    # Secure, daemon-valid tokens must be accepted.
    for i in range(12):
        token = make_token(f"random_clean_{nonce}_{i}", good_keys[i % 2], strong_hash())
        accepted.append(token)
        daemon_valid.add(token)

    # Policy-compliant tokens with opaque but daemon-invalid signatures must fail.
    for i in range(12):
        token = make_token(f"random_bad_sig_{nonce}_{i}", good_keys[i % 2], strong_hash())
        rejected.append(token)

    # These signatures are daemon-valid, so rejection must come from key policy.
    for i in range(8):
        token = make_token(f"random_bad_key_{nonce}_{i}", bad_keys[i % 2], strong_hash())
        rejected.append(token)
        daemon_valid.add(token)

    # These signatures and keys are valid, so rejection must come from the live wordlist.
    for i, word in enumerate(weak_words):
        token = make_token(
            f"random_weak_password_{nonce}_{i}",
            good_keys[i % 2],
            hashlib.sha256(word.encode()).hexdigest(),
        )
        rejected.append(token)
        daemon_valid.add(token)

    rejected.extend([
        "not-base64-" + secrets.token_hex(8),
        base64.b64encode(b"only|three|fields").decode("ascii"),
        base64.b64encode(b"").decode("ascii"),
    ])

    server_path = Path("/tmp/verifier_auth_daemon.py")
    manifest_path = Path("/tmp/verifier_valid_tokens.txt")

    try:
        # Replace the supplied dictionary with an unpredictable dictionary for this
        # test so hard-coded copies of the visible corpus/wordlist cannot pass.
        WORDLIST.write_text("\n".join(weak_words) + "\n", encoding="utf-8")
        server_path.write_text(SERVER_SOURCE, encoding="utf-8")
        manifest_path.write_text("\n".join(sorted(daemon_valid)) + "\n", encoding="ascii")

        stop_legacy_daemon()
        port = choose_port()
        server_proc = subprocess.Popen(
            [
                "bash", "-c",
                'exec -a auth_daemon /usr/bin/python3.real "$1" "$2" "$3"',
                "bash", str(server_path), str(manifest_path), str(port),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        deadline = time.time() + 5
        while time.time() < deadline:
            assert server_proc.poll() is None, "Randomized oracle daemon exited early"
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                    break
            except OSError:
                time.sleep(0.05)
        else:
            pytest.fail("Randomized oracle daemon did not start")

        cases = [(token, 0) for token in accepted] + [(token, 1) for token in rejected]
        random.SystemRandom().shuffle(cases)
        failures = []
        for token, expected in cases:
            try:
                result = run_filter(token)
                if result.returncode != expected:
                    failures.append(
                        f"expected exit {expected}, got {result.returncode} for randomized case"
                    )
            except subprocess.TimeoutExpired:
                failures.append("filter timed out on randomized case")
        assert not failures, " | ".join(failures[:10])
    finally:
        WORDLIST.write_bytes(original_wordlist)
        if server_proc is not None:
            server_proc.terminate()
            try:
                server_proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                server_proc.kill()
                server_proc.wait(timeout=2)
        server_path.unlink(missing_ok=True)
        manifest_path.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
