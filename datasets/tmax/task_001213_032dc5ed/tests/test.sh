#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import stat
import subprocess
import tempfile
import threading
import time


def test_completion_log():
    log_path = "/home/user/app/completion.log"
    assert os.path.isfile(log_path), f"Missing completion log: {log_path}"

    with open(log_path, "r") as f:
        raw = f.read()

    lines = [line.strip() for line in raw.splitlines() if line.strip()]
    assert len(lines) == 2, f"Expected exactly 2 lines in completion log, found {len(lines)}"
    assert lines[0] == "/home/user/app/sanitizer.sh", f"Line 1 incorrect: {lines[0]}"
    assert lines[1] == "/home/user/app/ipc/v1/db.fifo", f"Line 2 incorrect: {lines[1]}"
    assert raw.splitlines() == [
        "/home/user/app/sanitizer.sh",
        "/home/user/app/ipc/v1/db.fifo",
    ], "completion.log must contain exactly the required two lines"


def test_ipc_structure_and_permissions():
    v1_dir = "/home/user/app/ipc/v1"
    v2_dir = "/home/user/app/ipc/v2"

    assert os.path.isdir(v1_dir), f"Directory missing: {v1_dir}"
    assert os.path.isdir(v2_dir), f"Directory missing: {v2_dir}"

    v2_stat = os.stat(v2_dir)
    assert stat.S_IMODE(v2_stat.st_mode) == 0o700, f"Incorrect permissions on {v2_dir}, expected 0700"

    for fifo_name in ["backend.fifo", "db.fifo"]:
        v2_fifo = os.path.join(v2_dir, fifo_name)
        v1_symlink = os.path.join(v1_dir, fifo_name)

        assert os.path.exists(v2_fifo), f"FIFO missing: {v2_fifo}"
        assert stat.S_ISFIFO(os.stat(v2_fifo).st_mode), f"Not a FIFO: {v2_fifo}"
        assert stat.S_IMODE(os.stat(v2_fifo).st_mode) == 0o600, f"Incorrect permissions on {v2_fifo}, expected 0600"

        assert os.path.islink(v1_symlink), f"Symlink missing or not a link: {v1_symlink}"
        assert os.path.realpath(v1_symlink) == os.path.realpath(v2_fifo), f"Symlink {v1_symlink} does not point to {v2_fifo}"


def test_fifo_links_actually_transport_data():
    for fifo_name in ["backend.fifo", "db.fifo"]:
        source = f"/home/user/app/ipc/v2/{fifo_name}"
        link = f"/home/user/app/ipc/v1/{fifo_name}"
        payload = secrets.token_bytes(48)
        result = {}
        errors = []

        def reader():
            try:
                with open(link, "rb", buffering=0) as stream:
                    result["data"] = stream.read(len(payload))
            except BaseException as exc:
                errors.append(exc)

        thread = threading.Thread(target=reader, daemon=True)
        thread.start()
        time.sleep(0.05)
        with open(source, "wb", buffering=0) as stream:
            stream.write(payload)
        thread.join(3)

        assert not thread.is_alive(), f"IPC transfer hung for {fifo_name}"
        assert not errors, f"IPC reader failed for {fifo_name}: {errors}"
        assert result.get("data") == payload, f"Data did not traverse {link}"


def test_init_db_exp_exists():
    exp_path = "/home/user/app/init_db.exp"
    assert os.path.isfile(exp_path), f"Missing init_db.exp script: {exp_path}"


def test_init_db_expect_script_answers_both_prompts():
    exp_path = "/home/user/app/init_db.exp"
    cli_path = "/home/user/app/db_init_cli.py"
    assert os.path.isfile(exp_path), f"Missing init_db.exp script: {exp_path}"

    with open(cli_path, "rb") as stream:
        original = stream.read()
    original_mode = stat.S_IMODE(os.stat(cli_path).st_mode)

    marker = tempfile.mktemp(prefix="db-init-", dir="/tmp")
    mock_cli = r'''#!/usr/bin/env python3
import os
import sys

def prompt(text):
    sys.stdout.write(text)
    sys.stdout.flush()
    return sys.stdin.readline().rstrip("\r\n")

first = prompt("Enter DB Admin PIN:")
if first != "8675309":
    sys.exit(21)
second = prompt("Confirm PIN:")
if second != "8675309":
    sys.exit(22)
with open(os.environ["DB_INIT_MARKER"], "w") as out:
    out.write("initialized")
print("DB initialized")
'''

    try:
        with open(cli_path, "w") as stream:
            stream.write(mock_cli)
        os.chmod(cli_path, 0o755)

        env = os.environ.copy()
        env["DB_INIT_MARKER"] = marker
        result = subprocess.run(
            ["expect", exp_path],
            capture_output=True,
            text=True,
            timeout=15,
            env=env,
        )
        assert result.returncode == 0, (
            f"init_db.exp failed with status {result.returncode}; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(marker), "init_db.exp did not complete the prompted DB initialization"
        with open(marker) as stream:
            assert stream.read() == "initialized"
    finally:
        with open(cli_path, "wb") as stream:
            stream.write(original)
        os.chmod(cli_path, original_mode)
        if os.path.exists(marker):
            os.unlink(marker)


def test_sanitizer_adversarial_corpus():
    sanitizer = "/home/user/app/sanitizer.sh"
    assert os.path.isfile(sanitizer), f"Missing sanitizer script: {sanitizer}"

    evil_dir = "/home/user/corpus/evil"
    clean_dir = "/home/user/corpus/clean"

    evil_files = glob.glob(os.path.join(evil_dir, "*.txt"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.txt"))

    assert len(evil_files) > 0, "No evil corpus files found"
    assert len(clean_files) > 0, "No clean corpus files found"

    evil_bypassed = []
    for filename in evil_files:
        res = subprocess.run(["bash", sanitizer, filename], capture_output=True, text=True)
        if "REJECT" not in res.stdout:
            evil_bypassed.append(os.path.basename(filename))

    clean_modified = []
    for filename in clean_files:
        res = subprocess.run(["bash", sanitizer, filename], capture_output=True, text=True)
        if "ACCEPT" not in res.stdout:
            clean_modified.append(os.path.basename(filename))

    assert not evil_bypassed, f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}"
    assert not clean_modified, f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified)}"


def test_sanitizer_hidden_payloads_have_one_exact_decision():
    sanitizer = "/home/user/app/sanitizer.sh"
    assert os.path.isfile(sanitizer), f"Missing sanitizer script: {sanitizer}"

    rng = secrets.SystemRandom()

    def mixed_case(value):
        return "".join(ch.upper() if rng.randrange(2) else ch.lower() for ch in value)

    token = secrets.token_hex(24)
    payloads = [
        token,
        f"ordinary request body {token}",
        f"<{token}> harmless text",
        "<script > is not the specified substring",
        "DROP  TABLE has two spaces",
        "UNION\nSELECT is split across lines",
    ]
    forbidden = ["<script>", "DROP TABLE", "UNION SELECT", "passwd"]
    for needle in forbidden:
        payloads.append(f"{token[:13]}::{mixed_case(needle)}::{token[13:]}")
    payloads.append(
        f"{mixed_case('<script>')} {mixed_case('DROP TABLE')} "
        f"{mixed_case('UNION SELECT')} {mixed_case('passwd')}"
    )
    rng.shuffle(payloads)

    with tempfile.TemporaryDirectory(prefix="sanitizer-cases-") as directory:
        for index, payload in enumerate(payloads):
            path = os.path.join(directory, f"payload-{index}.txt")
            with open(path, "w") as stream:
                stream.write(payload)

            expected = "REJECT" if any(item.lower() in payload.lower() for item in forbidden) else "ACCEPT"
            result = subprocess.run(
                ["bash", sanitizer, path],
                capture_output=True,
                text=True,
                timeout=5,
            )
            assert result.returncode == 0, f"Sanitizer exited {result.returncode} for payload {index}"
            assert result.stdout.strip() == expected, (
                f"Payload {index} expected exactly {expected}, got stdout {result.stdout!r}"
            )


def test_startup_script_runs_after_ipc_and_initialization_are_ready():
    startup = "/home/user/app/start_services.sh"
    assert os.path.isfile(startup), f"Missing startup script: {startup}"
    result = subprocess.run(
        ["bash", startup],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"start_services.sh failed with status {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
