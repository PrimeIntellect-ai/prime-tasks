#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import secrets
import shutil
import string
import subprocess
import tempfile
import time
import pytest

FILTER_PATH = "/home/user/filter"


def run_filter(path):
    try:
        return subprocess.run(
            [FILTER_PATH, path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=0.5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter hung while processing {path}")


def expected_result(data, local_users):
    lines = data.splitlines()
    in_body = False
    has_from = False
    bad_subject = False
    bad_body = False
    recipients = []

    for line in lines:
        if not in_body:
            if line == "":
                in_body = True
            elif line.startswith("From:"):
                has_from = True
            elif line.startswith("Subject:"):
                value = line[8:]
                while value.startswith(" "):
                    value = value[1:]
                if len(value) > 80:
                    bad_subject = True
            elif line.startswith("To:"):
                recipients.extend(part.strip() for part in line[3:].split(","))
        elif len(line) >= 2 and line[0] == "." and line[1].isalnum() and line[1].isascii():
            bad_body = True

    bad_recipient = False
    for recipient in recipients:
        address = recipient
        if "<" in address and ">" in address:
            address = address[address.find("<") + 1:address.find(">")]
        username = address.split("@", 1)[0]
        if not username or username not in local_users:
            bad_recipient = True

    return 1 if (not has_from or bad_subject or bad_body or bad_recipient) else 0


def test_filter_executable():
    """Verify that the filter binary exists and is an ELF executable."""
    filter_path = "/home/user/filter"
    assert os.path.exists(filter_path), f"Filter binary not found at {filter_path}"
    assert os.path.isfile(filter_path), f"{filter_path} is not a file"
    assert os.access(filter_path, os.X_OK), f"{filter_path} is not executable"

    with open(filter_path, "rb") as f:
        magic = f.read(4)
        assert magic == b"\x7fELF", f"{filter_path} is not an ELF executable"


def test_systemd_service_active():
    """Verify that the mailer-daemon systemd user service is active."""
    service_name = "mailer-daemon.service"
    env = os.environ.copy()
    if "XDG_RUNTIME_DIR" not in env:
        env["XDG_RUNTIME_DIR"] = "/run/user/1000"

    cmd = ["su", "-", "user", "-c", f"XDG_RUNTIME_DIR=/run/user/1000 systemctl --user is-active {service_name}"]
    if os.geteuid() != 0:
        cmd = ["systemctl", "--user", "is-active", service_name]

    try:
        result = subprocess.run(cmd, env=env, capture_output=True, text=True)
        assert result.stdout.strip() == "active", f"Service {service_name} is not active. Output: {result.stdout.strip()}"
    except Exception as e:
        pytest.fail(f"Failed to check systemd service: {e}")


def test_adversarial_corpus():
    """Verify the filter correctly classifies the clean and evil corpora."""
    clean_dir = "/app/evaluation_corpus/clean"
    evil_dir = "/app/evaluation_corpus/evil"

    assert os.path.exists(clean_dir), f"Clean corpus directory not found at {clean_dir}"
    assert os.path.exists(evil_dir), f"Evil corpus directory not found at {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, "No files found in clean evaluation corpus"
    assert len(evil_files) > 0, "No files found in evil evaluation corpus"

    clean_failed = []
    for cf in clean_files:
        if run_filter(cf) != 0:
            clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        if run_filter(ef) != 1:
            evil_failed.append(os.path.basename(ef))

    error_msgs = []
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_generated_path_independent_corpus():
    """Exercise all failure rules and recipient policy under opaque random paths."""
    local_users = {entry.pw_name for entry in pwd.getpwall()}
    assert local_users, "No local users found in /etc/passwd"
    preferred = [name for name in ("user", "alice", "root") if name in local_users]
    valid_user = preferred[0] if preferred else next(iter(local_users))

    invalid_user = "missing_" + secrets.token_hex(10)
    while invalid_user in local_users:
        invalid_user = "missing_" + secrets.token_hex(10)

    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits
    cases = []

    with tempfile.TemporaryDirectory(prefix="mail-check-") as corpus_dir:
        for i in range(240):
            has_from = i % 7 != 0
            bad_recipient = i % 5 == 0
            bad_body = i % 11 == 0
            subject_length = (0, 1, 40, 79, 80, 81, 96)[i % 7]

            headers = []
            if has_from:
                headers.append("From: " + "sender" + secrets.token_hex(4) + "@example.net")
            headers.append("To: " + (invalid_user if bad_recipient else valid_user) + "@example.com")
            headers.append("Subject: " + "".join(rng.choice(alphabet) for _ in range(subject_length)))
            headers.append("X-Trace: " + secrets.token_hex(12))
            rng.shuffle(headers)

            body = ["payload " + secrets.token_hex(16)]
            if bad_body:
                body.insert(rng.randrange(len(body) + 1), ".A" + secrets.token_hex(8))
            else:
                body.append("." if i % 3 == 0 else "ordinary " + secrets.token_hex(6))

            data = "\n".join(headers) + "\n\n" + "\n".join(body) + "\n"
            path = os.path.join(corpus_dir, secrets.token_hex(16) + ".eml")
            with open(path, "w", encoding="ascii") as f:
                f.write(data)
            cases.append((path, expected_result(data, local_users)))

        rng.shuffle(cases)
        assert any(expected == 0 for _, expected in cases)
        assert any(expected == 1 for _, expected in cases)

        failures = []
        for path, expected in cases:
            actual = run_filter(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))
                if len(failures) >= 10:
                    break
        assert not failures, f"Generated corpus misclassifications (name, expected, actual): {failures}"


def test_daemon_processing():
    """Verify the daemon processes incoming files correctly."""
    incoming_dir = "/home/user/spool/incoming"
    processed_dir = "/home/user/spool/processed"
    quarantine_dir = "/home/user/spool/quarantine"

    assert os.path.isdir(incoming_dir), f"Directory {incoming_dir} does not exist"
    assert os.path.isdir(processed_dir), f"Directory {processed_dir} does not exist"
    assert os.path.isdir(quarantine_dir), f"Directory {quarantine_dir} does not exist"

    clean_files = os.listdir("/app/evaluation_corpus/clean")
    evil_files = os.listdir("/app/evaluation_corpus/evil")
    if not clean_files or not evil_files:
        pytest.skip("Evaluation corpus is empty, cannot test daemon processing")

    clean_sample = os.path.join("/app/evaluation_corpus/clean", clean_files[0])
    evil_sample = os.path.join("/app/evaluation_corpus/evil", evil_files[0])
    test_clean = os.path.join(incoming_dir, "test_clean.eml")
    test_evil = os.path.join(incoming_dir, "test_evil.eml")

    for path in [test_clean, test_evil, os.path.join(processed_dir, "test_clean.eml"), os.path.join(quarantine_dir, "test_evil.eml")]:
        if os.path.exists(path):
            os.remove(path)

    shutil.copy(clean_sample, test_clean)
    shutil.copy(evil_sample, test_evil)
    if os.geteuid() == 0:
        os.chown(test_clean, 1000, 1000)
        os.chown(test_evil, 1000, 1000)

    time.sleep(3)
    if os.path.exists(test_clean):
        pytest.fail("Clean file remained in incoming/ and was not processed")
    if os.path.exists(test_evil):
        pytest.fail("Evil file remained in incoming/ and was not processed")

    assert os.path.exists(os.path.join(processed_dir, "test_clean.eml")), "Clean email did not move to processed/"
    assert os.path.exists(os.path.join(quarantine_dir, "test_evil.eml")), "Evil email did not move to quarantine/"


def test_daemon_with_opaque_names():
    """Ensure daemon routing does not rely on clean/evil path names."""
    incoming = "/home/user/spool/incoming"
    processed = "/home/user/spool/processed"
    quarantine = "/home/user/spool/quarantine"
    token_a = secrets.token_hex(16) + ".eml"
    token_b = secrets.token_hex(16) + ".eml"
    valid_user = "user" if "user" in {p.pw_name for p in pwd.getpwall()} else pwd.getpwall()[0].pw_name

    safe_data = f"From: {secrets.token_hex(6)}@example.net\nTo: {valid_user}@example.com\nSubject: {secrets.token_hex(8)}\n\n{secrets.token_hex(12)}\n"
    unsafe_data = f"To: {valid_user}@example.com\nSubject: {secrets.token_hex(8)}\n\n{secrets.token_hex(12)}\n"
    entries = [(token_a, safe_data, processed), (token_b, unsafe_data, quarantine)]
    random.SystemRandom().shuffle(entries)

    for name, _, destination in entries:
        for path in (os.path.join(incoming, name), os.path.join(processed, name), os.path.join(quarantine, name)):
            if os.path.exists(path):
                os.remove(path)

    for name, data, _ in entries:
        path = os.path.join(incoming, name)
        with open(path, "w", encoding="ascii") as f:
            f.write(data)
        if os.geteuid() == 0:
            os.chown(path, 1000, 1000)

    deadline = time.time() + 8
    while time.time() < deadline:
        if all(os.path.exists(os.path.join(destination, name)) for name, _, destination in entries):
            break
        time.sleep(0.2)

    for name, _, destination in entries:
        assert not os.path.exists(os.path.join(incoming, name)), f"Daemon left {name} in incoming"
        assert os.path.exists(os.path.join(destination, name)), f"Daemon routed opaque file {name} incorrectly"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
