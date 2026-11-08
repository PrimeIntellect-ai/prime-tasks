#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import shlex
import stat
import subprocess

import pytest

SCRIPT_FILE = "/home/user/process.sh"
INPUT_FILE = "/home/user/corrupt_logs.jsonl"
OUTPUT_FILE = "/home/user/clean_logs.jsonl"

CANONICAL_LINES = [
    r'{"id": "1", "ip": "10.0.0.1", "message": "Error in module A \u1234"}',
    r'{"id": "2", "ip": "10.0.0.2", "message": "Error in module B \uGHIJ"}',
    r'{"id": "3", "ip": "10.0.0.3", "message": "Error in module C \u0000"}',
    r'{"id": "4", "ip": "10.0.0.4", "message": "Error in module B \uGHIJ"}',
    r'{"id": "5", "ip": "192.168.1.5", "message": "Crash dump \uX999 details"}',
    r'{"id": "6", "ip": "192.168.1.5", "message": "Crash dump \uX999 details"}',
    r'{"id": "7", "ip": "172.16.0.7", "message": "Valid hex \uABCD but bad string \uQQQQ"}',
]

EXPECTED = []


def shell_tokens(source):
    tokens = []
    for line in source.splitlines():
        lexer = shlex.shlex(line, posix=True, punctuation_chars=";&|()")
        lexer.whitespace_split = True
        lexer.commenters = "#"
        try:
            tokens.extend(list(lexer))
        except ValueError:
            continue
    return tokens


def assert_parallel_construct(source):
    tokens = shell_tokens(source)
    has_parallel = "parallel" in tokens
    has_coproc = "coproc" in tokens
    has_background_wait = "&" in tokens and "wait" in tokens
    has_xargs_parallel = False
    for i, token in enumerate(tokens):
        if token != "xargs":
            continue
        args = tokens[i + 1:i + 12]
        for j, arg in enumerate(args):
            if re.fullmatch(r"-P(?:[1-9][0-9]*)?", arg):
                if arg != "-P" or (j + 1 < len(args) and re.fullmatch(r"[1-9][0-9]*", args[j + 1])):
                    has_xargs_parallel = True
            if re.fullmatch(r"--max-procs(?:=[1-9][0-9]*)?", arg):
                if "=" in arg or (j + 1 < len(args) and re.fullmatch(r"[1-9][0-9]*", args[j + 1])):
                    has_xargs_parallel = True
    assert has_parallel or has_coproc or has_background_wait or has_xargs_parallel, \
        "process.sh does not contain a parallel-processing construct"


def normalize_invalid_unicode(raw_line):
    def replace(match):
        chars = match.group(1)
        return match.group(0) if re.fullmatch(r"[0-9a-fA-F]{4}", chars) else r"\uFFFD"
    return re.sub(r"\\u(.{4})", replace, raw_line)


def derive_expected(lines):
    expected = []
    seen = set()
    for raw_line in lines:
        obj = json.loads(normalize_invalid_unicode(raw_line))
        obj["ip"] = re.sub(r"\.\d{1,3}$", ".XXX", obj["ip"])
        digest = hashlib.sha256(obj["message"].encode("utf-8")).hexdigest()
        if digest in seen:
            continue
        seen.add(digest)
        obj["msg_hash"] = digest
        expected.append(obj)
    return expected


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    global EXPECTED

    assert os.path.lexists(SCRIPT_FILE), f"Required script {SCRIPT_FILE} does not exist."
    assert not os.path.islink(SCRIPT_FILE), f"{SCRIPT_FILE} must be a regular script, not a symlink."
    assert os.path.isfile(SCRIPT_FILE), f"{SCRIPT_FILE} is not a regular file."
    mode = os.stat(SCRIPT_FILE).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), f"{SCRIPT_FILE} is not executable."

    with open(SCRIPT_FILE, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert first_line.startswith("#!") and "bash" in first_line, f"{SCRIPT_FILE} is not a Bash script."
    assert_parallel_construct(source)

    with open(INPUT_FILE, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(CANONICAL_LINES) + "\n")
    EXPECTED = derive_expected(CANONICAL_LINES)

    if os.path.lexists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    result = subprocess.run(
        [SCRIPT_FILE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, \
        f"process.sh exited with status {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def read_output_objects():
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        lines = f.read().strip().split("\n")
    objects = []
    for i, line in enumerate(lines):
        if not line.strip():
            continue
        try:
            objects.append(json.loads(line))
        except json.JSONDecodeError as e:
            pytest.fail(f"Line {i+1} is not valid JSON: {e}\nLine content: {line}")
    return lines, objects


def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a regular file."


def test_output_format_and_deduplication():
    lines, objects = read_output_objects()
    assert len(lines) == 5, f"Expected exactly 5 unique log lines after deduplication, found {len(lines)}."

    seen_hashes = set()
    for i, obj in enumerate(objects):
        for field in ["id", "ip", "message", "msg_hash"]:
            assert field in obj, f"Line {i+1} is missing the '{field}' field."
        seen_hashes.add(obj["msg_hash"])
    assert len(seen_hashes) == 5, "Duplicate messages found in the output. Deduplication failed."


def test_output_matches_normalized_input_and_keeps_first_duplicates():
    _, objects = read_output_objects()
    assert len(objects) == len(EXPECTED)
    actual_by_hash = {obj.get("msg_hash"): obj for obj in objects}
    expected_by_hash = {obj["msg_hash"]: obj for obj in EXPECTED}
    assert actual_by_hash == expected_by_hash, \
        "Output does not exactly match the normalized, masked, first-occurrence-deduplicated input records."
    assert {obj["id"] for obj in objects} == {"1", "2", "3", "5", "7"}, \
        "Deduplication did not preserve the first record for each duplicate message."


def test_ip_anonymization():
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        for i, line in enumerate(f):
            if not line.strip():
                continue
            obj = json.loads(line)
            ip = obj.get("ip", "")
            assert re.match(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.XXX$", ip), \
                f"IP address '{ip}' on line {i+1} is not masked correctly."


def test_unicode_normalization_and_hashing():
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    matches = re.findall(r"\\u(.{4})", content)
    for match in matches:
        assert re.match(r"^[0-9a-fA-F]{4}$", match), \
            f"Found invalid unicode escape sequence in raw output: \\u{match}"

    lines = content.strip().split("\n")
    for i, line in enumerate(lines):
        if not line.strip():
            continue
        obj = json.loads(line)
        msg = obj["message"]
        expected_hash = hashlib.sha256(msg.encode("utf-8")).hexdigest()
        actual_hash = obj["msg_hash"]
        assert actual_hash == expected_hash, \
            f"msg_hash incorrect on line {i+1}.\nExpected: {expected_hash}\nActual: {actual_hash}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
