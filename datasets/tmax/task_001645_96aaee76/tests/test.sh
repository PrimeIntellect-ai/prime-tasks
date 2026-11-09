#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import string
import subprocess
import tempfile
import pytest

FILTER_BIN = "/home/user/filter"
FILTER_SOURCE = "/home/user/filter.c"


def make_payload(path, classification, newline="\n"):
    body = ("payload-" + secrets.token_hex(random.randint(4, 70))).encode("ascii")
    user_agent = "Mozilla/" + secrets.token_hex(6)
    content_length = len(body)

    if classification == "bad_length":
        content_length += random.randint(1, 50)
    elif classification == "bad_ua":
        marker = random.choice(["$", "|", ";", "`"])
        user_agent = "client" + marker + secrets.token_hex(4)
    elif classification == "both":
        content_length += random.randint(1, 50)
        marker = random.choice(["$", "|", ";", "`"])
        user_agent = "client" + marker + secrets.token_hex(4)
    elif classification != "clean":
        raise ValueError(classification)

    headers = (
        f"User-Agent: {user_agent}{newline}"
        f"Content-Length: {content_length}{newline}"
        f"{newline}"
    ).encode("ascii")
    data = headers + body
    with open(path, "wb") as f:
        f.write(data)
    return data


def run_filter(binary, path):
    return subprocess.run([binary, path], capture_output=True, timeout=5).returncode


def test_black_frames_count():
    """Part 1: Verify the black frames count."""
    count_file = "/home/user/black_frames.txt"
    assert os.path.exists(count_file), f"File {count_file} does not exist."

    with open(count_file, "r") as f:
        content = f.read().strip()

    assert content == "7", f"Expected black frames count to be 7, but got {content}."


def test_filter_source_exists_compiles_and_binary_is_compiled():
    """Require the requested C source and independently compile it."""
    assert os.path.isfile(FILTER_SOURCE), f"C source {FILTER_SOURCE} does not exist."
    assert os.path.exists(FILTER_BIN), f"Filter binary {FILTER_BIN} does not exist."
    assert os.access(FILTER_BIN, os.X_OK), f"Filter binary {FILTER_BIN} is not executable."

    with open(FILTER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{FILTER_BIN} is not a compiled ELF executable."

    result = subprocess.run(
        ["gcc", FILTER_SOURCE, "-o", "/tmp/filter_rebuilt"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"filter.c did not compile:\n{result.stderr}"
    assert os.access("/tmp/filter_rebuilt", os.X_OK)


def test_payload_sanitizer_corpus():
    """Part 2: Preserve verification against the supplied corpus."""
    filter_bin = FILTER_BIN
    assert os.path.exists(filter_bin), f"Filter binary {filter_bin} does not exist."
    assert os.access(filter_bin, os.X_OK), f"Filter binary {filter_bin} is not executable."

    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    evil_failed = []

    for cf in clean_files:
        result = subprocess.run([filter_bin, cf], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    for ef in evil_files:
        result = subprocess.run([filter_bin, ef], capture_output=True)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(ef))

    error_messages = []
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed (accepted): {', '.join(evil_failed)}")

    assert not error_messages, "Corpus verification failed:\n" + "\n".join(error_messages)


def test_payload_sanitizer_runtime_generated_inputs():
    """Exercise both submitted and source-built programs on opaque, fresh paths."""
    assert os.path.isfile("/tmp/filter_rebuilt"), "Independently compiled filter is missing."
    root = tempfile.mkdtemp(prefix="payload-check-" + secrets.token_hex(8) + "-")
    try:
        cases = []
        kinds = ["clean"] * 32 + ["bad_length"] * 12 + ["bad_ua"] * 12 + ["both"] * 8
        random.SystemRandom().shuffle(kinds)

        for i, kind in enumerate(kinds):
            name = secrets.token_hex(16) + ".dat"
            path = os.path.join(root, name)
            newline = "\r\n" if i % 2 else "\n"
            make_payload(path, kind, newline)
            expected = 0 if kind == "clean" else 1
            cases.append((path, expected))

        random.SystemRandom().shuffle(cases)
        for binary in (FILTER_BIN, "/tmp/filter_rebuilt"):
            failures = []
            for path, expected in cases:
                actual = run_filter(binary, path)
                if actual != expected:
                    failures.append((os.path.basename(path), expected, actual))
            assert not failures, f"{binary} misclassified runtime-generated payloads: {failures[:10]}"
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_automation_script():
    """Part 3: Preserve the original automation assertions."""
    script_path = "/home/user/automation.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    incoming_dir = "/app/incoming/"
    safe_dir = "/home/user/safe/"

    if os.path.exists(incoming_dir) and os.listdir(incoming_dir):
        subprocess.run([script_path], check=False)

    assert os.path.exists(safe_dir), f"Safe directory {safe_dir} was not created."
    assert os.path.isdir(safe_dir), f"{safe_dir} is not a directory."

    incoming_files = os.listdir(incoming_dir) if os.path.exists(incoming_dir) else []
    assert len(incoming_files) == 0, f"Incoming directory is not empty. Files remaining: {', '.join(incoming_files)}"

    safe_files = os.listdir(safe_dir)
    assert len(safe_files) == 10, f"Expected exactly 10 clean files in {safe_dir}, but found {len(safe_files)}."


def test_automation_with_fresh_opaque_spaced_names():
    """Verify cleanup using newly generated payloads whose names do not reveal labels."""
    script_path = "/home/user/automation.sh"
    incoming_dir = "/app/incoming"
    safe_dir = "/home/user/safe"
    os.makedirs(incoming_dir, exist_ok=True)
    os.makedirs(safe_dir, exist_ok=True)
    assert os.listdir(incoming_dir) == [], "Incoming must be empty before the fresh automation test."

    expected_clean = {}
    expected_evil = []
    kinds = ["clean"] * 6 + ["bad_length", "bad_ua", "both", "bad_length", "bad_ua", "both"]
    random.SystemRandom().shuffle(kinds)

    for i, kind in enumerate(kinds):
        name = secrets.token_hex(6) + " payload " + secrets.token_hex(6) + ".bin"
        path = os.path.join(incoming_dir, name)
        data = make_payload(path, kind, "\r\n" if i % 2 else "\n")
        if kind == "clean":
            expected_clean[name] = data
        else:
            expected_evil.append(name)

    result = subprocess.run([script_path], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Automation script failed:\n{result.stdout}\n{result.stderr}"
    assert os.listdir(incoming_dir) == [], f"Incoming directory was not emptied: {os.listdir(incoming_dir)}"

    for name, original_data in expected_clean.items():
        destination = os.path.join(safe_dir, name)
        assert os.path.isfile(destination), f"Clean payload with spaced name was not moved: {name}"
        with open(destination, "rb") as f:
            assert f.read() == original_data, f"Moved clean payload was modified: {name}"

    for name in expected_evil:
        assert not os.path.exists(os.path.join(incoming_dir, name)), f"Evil payload remained incoming: {name}"
        assert not os.path.exists(os.path.join(safe_dir, name)), f"Evil payload was moved to safe: {name}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
