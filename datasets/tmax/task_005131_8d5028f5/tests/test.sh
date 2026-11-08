#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import subprocess
import tempfile
import uuid

import pytest

EXECUTABLE = "/app/build/validator"


def run_validator(path):
    try:
        return subprocess.run(
            [EXECUTABLE, path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Validator timed out on {path}")


def varint(value):
    out = bytearray()
    while value >= 0x80:
        out.append((value & 0x7f) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def protobuf_trace(events):
    result = bytearray()
    for event_type in events:
        value = event_type.encode("utf-8")
        event = b"\x0a" + varint(len(value)) + value
        result += b"\x0a" + varint(len(event)) + event
    return bytes(result)


def test_executable_exists_and_is_native_binary():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} not found."
    assert os.access(EXECUTABLE, os.X_OK), f"Executable {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "validator must be the compiled native executable"


def test_build_uses_protobuf_c_bindings():
    with open("/app/Makefile", encoding="utf-8", errors="replace") as f:
        makefile = f.read()
    with open("/app/src/validator.c", encoding="utf-8", errors="replace") as f:
        source = f.read()

    assert "protoc-c" in makefile, "Makefile must generate protobuf-c bindings with protoc-c"
    assert "-lprotobuf-c" in makefile, "Makefile must link libprotobuf-c"
    assert "trace.pb-c.c" in makefile, "Makefile must compile the generated protobuf-c source"
    assert re.search(r"trace__unpack\s*\(", source), "validator.c must deserialize Trace with trace__unpack"
    assert re.search(r"trace__free_unpacked\s*\(", source), "validator.c must release the unpacked Trace"
    assert re.search(r"validate_trace\s*\(", source), "validator.c must implement validation in C"


def test_clean_corpus():
    clean_files = glob.glob("/app/corpus/clean/*.bin")
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for path in clean_files:
        if run_validator(path) != 0:
            failed_files.append(os.path.basename(path))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean modified (rejected). "
            f"Offending files: {', '.join(failed_files)}"
        )


def test_evil_corpus():
    evil_files = glob.glob("/app/corpus/evil/*.bin")
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []
    for path in evil_files:
        if run_validator(path) == 0:
            failed_files.append(os.path.basename(path))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(evil_files)} evil bypassed (accepted). "
            f"Offending files: {', '.join(failed_files)}"
        )


def test_random_hidden_protobuf_traces():
    rng = random.SystemRandom()
    cases = []

    # Generate fresh valid traces with unpredictable sizes and paths.
    for _ in range(18):
        query_count = rng.randint(1, 60)
        cases.append((
            ["INIT", "AUTH"] + ["QUERY"] * query_count + ["LOGOUT", "END"],
            0,
        ))

    # Generate fresh invalid traces covering every forbidden state-machine shape.
    for _ in range(5):
        token = "UNKNOWN_" + uuid.uuid4().hex
        cases.extend([
            (["INIT", "AUTH", "LOGOUT", "END"], 1),
            (["AUTH", "QUERY", "LOGOUT", "END"], 1),
            (["INIT", "AUTH", "QUERY", "LOGOUT"], 1),
            (["INIT", "AUTH", "QUERY", "AUTH", "LOGOUT", "END"], 1),
            (["INIT", "AUTH", "QUERY", "LOGOUT", "END", "INIT"], 1),
            (["INIT", "AUTH", token, "LOGOUT", "END"], 1),
            ([], 1),
        ])

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="telemetry-" + uuid.uuid4().hex + "-") as directory:
        for events, expected in cases:
            path = os.path.join(directory, uuid.uuid4().hex)
            with open(path, "wb") as f:
                f.write(protobuf_trace(events))
            actual = run_validator(path)
            assert actual == expected, (
                f"wrong exit status for generated trace {events!r}: "
                f"expected {expected}, got {actual}"
            )


def test_malformed_and_unreadable_inputs_return_one():
    malformed = [
        b"",
        b"\x80",                         # unterminated varint
        b"\x0a\x05\x0a\x04A",          # truncated embedded Event
        b"\x0f",                         # illegal protobuf wire type
        protobuf_trace(["INIT", "AUTH", "QUERY", "LOGOUT", "END"]) + b"\x80",
    ]

    with tempfile.TemporaryDirectory(prefix="malformed-" + uuid.uuid4().hex + "-") as directory:
        paths = []
        for payload in malformed:
            path = os.path.join(directory, uuid.uuid4().hex)
            with open(path, "wb") as f:
                f.write(payload)
            paths.append(path)
        random.SystemRandom().shuffle(paths)
        for path in paths:
            assert run_validator(path) == 1, f"malformed protobuf was not rejected: {path}"

    missing = "/tmp/" + uuid.uuid4().hex
    assert run_validator(missing) == 1, "an unreadable/nonexistent input must return status 1"

    no_argument = subprocess.run(
        [EXECUTABLE], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3
    )
    assert no_argument.returncode == 1, "invocation without a file must return status 1"
TEST_EOF

if make -C /app clean >/tmp/verifier_make.log 2>&1 \
   && make -C /app >>/tmp/verifier_make.log 2>&1 \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    cat /tmp/verifier_make.log 2>/dev/null || true
    echo "0" > /logs/verifier/reward.txt
fi
