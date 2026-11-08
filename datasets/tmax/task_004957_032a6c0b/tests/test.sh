#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import socket
import subprocess
import time
import pytest

MAIL_FILTER_SOURCE = "/home/user/mail_filter.c"
MAIL_FILTER_BIN = "/home/user/mail_filter"
COMPILED_FILTER_BIN = "/tmp/mail_filter_from_source"
FORWARDER_SCRIPT = "/home/user/start_forwarder.sh"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def make_email(token, cost_cents, nonce):
    headers = [
        f"From: alert-{nonce}@finops.local",
        "To: admin@finops.local",
        f"Subject: Cost Alert {nonce}",
        f"X-Request-ID: {nonce}",
    ]
    if token is not None:
        headers.append(f"X-FinOps-Token: {token}")
    return ("\n".join(headers) +
            f"\n\nAlert-Note: generated-{nonce}\n"
            f"Total-Cost: ${cost_cents // 100}.{cost_cents % 100:02d}\n").encode()


def run_filter(path, message):
    return subprocess.run(
        [path], input=message, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=5
    ).returncode


def test_mail_filter_exists_and_executable():
    assert os.path.isfile(MAIL_FILTER_BIN), f"Binary {MAIL_FILTER_BIN} does not exist."
    assert os.access(MAIL_FILTER_BIN, os.X_OK), f"Binary {MAIL_FILTER_BIN} is not executable."


def test_mail_filter_source_exists_and_compiles_without_warnings():
    assert os.path.isfile(MAIL_FILTER_SOURCE), f"Source {MAIL_FILTER_SOURCE} does not exist."
    proc = subprocess.run(
        ["gcc", "-Wall", "-Wextra", "-Werror", MAIL_FILTER_SOURCE, "-o", COMPILED_FILTER_BIN],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert proc.returncode == 0, "mail_filter.c did not compile without warnings:\n" + proc.stderr
    assert os.path.isfile(COMPILED_FILTER_BIN)
    assert os.access(COMPILED_FILTER_BIN, os.X_OK)


def test_adversarial_corpus_mail_filter():
    """
    Test the mail_filter binary against the clean and evil corpora.
    Clean emails must exit 0, Evil emails must exit 1.
    """
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.eml')]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.eml')]

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for cf in clean_files:
        with open(cf, 'rb') as f:
            proc = subprocess.run([MAIL_FILTER_BIN], stdin=f, capture_output=True)
            if proc.returncode != 0:
                clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        with open(ef, 'rb') as f:
            proc = subprocess.run([MAIL_FILTER_BIN], stdin=f, capture_output=True)
            if proc.returncode != 1:
                evil_failed.append(os.path.basename(ef))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed[:5])}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failed[:5])}")

    assert not errors, "Corpus verification failed:\n" + "\n".join(errors)


def test_runtime_generated_policy_cases():
    cases = []
    for _ in range(12):
        nonce = secrets.token_hex(12)
        cents = secrets.randbelow(799000) + 1000
        cases.append((make_email("99A-XYZ", cents, nonce), 0, "clean"))

    for _ in range(6):
        nonce = secrets.token_hex(12)
        cents = secrets.randbelow(799000) + 1000
        cases.append((make_email(None, cents, nonce), 1, "missing token"))

    for _ in range(6):
        nonce = secrets.token_hex(12)
        cents = secrets.randbelow(799000) + 1000
        cases.append((make_email("BAD-" + secrets.token_hex(5), cents, nonce), 1, "wrong token"))

    for cents in [800000, 800001, 900000 + secrets.randbelow(600000)]:
        nonce = secrets.token_hex(12)
        cases.append((make_email("99A-XYZ", cents, nonce), 1, "cost not below 8000"))

    for binary in (MAIL_FILTER_BIN, COMPILED_FILTER_BIN):
        for message, expected, description in cases:
            actual = run_filter(binary, message)
            assert actual == expected, (
                f"{binary} returned {actual}, expected {expected} for generated {description} case"
            )


def test_forwarder_script_exists_and_executable():
    assert os.path.isfile(FORWARDER_SCRIPT), f"Script {FORWARDER_SCRIPT} does not exist."
    assert os.access(FORWARDER_SCRIPT, os.X_OK), f"Script {FORWARDER_SCRIPT} is not executable."


def send_message(message):
    sender = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sender.settimeout(2.0)
    sender.connect(('127.0.0.1', 10025))
    sender.sendall(message)
    sender.shutdown(socket.SHUT_WR)
    sender.close()


def receive_message(receiver):
    conn, _ = receiver.accept()
    conn.settimeout(2.0)
    received = b""
    try:
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            received += chunk
    finally:
        conn.close()
    return received


def test_forwarder_functionality():
    """
    Test the bash automation script.
    It should listen on 10025, pipe to mail_filter, and forward to 10026 if accepted.
    """
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.eml')]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.eml')]

    clean_email_path = clean_files[0]
    evil_email_path = evil_files[0]

    with open(clean_email_path, 'rb') as f:
        clean_email_data = f.read()
    with open(evil_email_path, 'rb') as f:
        evil_email_data = f.read()

    generated_clean = make_email(
        "99A-XYZ", secrets.randbelow(799000) + 1000, secrets.token_hex(16)
    )
    generated_evil = make_email(
        "99A-XYZ", 800000 + secrets.randbelow(700000), secrets.token_hex(16)
    )

    receiver = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    receiver.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    receiver.bind(('127.0.0.1', 10026))
    receiver.listen(4)
    receiver.settimeout(2.0)

    forwarder_proc = subprocess.Popen(
        [FORWARDER_SCRIPT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    time.sleep(1)

    try:
        # Preserve the original corpus-based forwarding assertions.
        send_message(clean_email_data)
        try:
            received_data = receive_message(receiver)
            assert received_data == clean_email_data, "Forwarded clean email data does not match original."
        except socket.timeout:
            pytest.fail("Did not receive forwarded clean email on port 10026.")

        send_message(evil_email_data)
        try:
            received_data = receive_message(receiver)
            assert received_data == b"", "Received data for evil email on port 10026, but should have been dropped."
        except socket.timeout:
            pass

        # Exercise the forwarder with messages generated only at verification time.
        send_message(generated_clean)
        try:
            received_data = receive_message(receiver)
            assert received_data == generated_clean, "Generated clean email was not forwarded byte-for-byte."
        except socket.timeout:
            pytest.fail("Generated clean email was not forwarded on port 10026.")

        send_message(generated_evil)
        try:
            received_data = receive_message(receiver)
            assert received_data == b"", "Generated evil email was forwarded."
        except socket.timeout:
            pass

    finally:
        try:
            os.killpg(forwarder_proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            forwarder_proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(forwarder_proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            forwarder_proc.wait(timeout=2)
        receiver.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
