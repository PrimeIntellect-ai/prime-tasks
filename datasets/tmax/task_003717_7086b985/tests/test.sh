#!/bin/bash
set -e
mkdir -p /logs/verifier

ENGINE_BACKUP="/tmp/graph_engine.verifier.$$"
cp -p /app/graph_engine "$ENGINE_BACKUP"
restore_engine() {
    cp -p "$ENGINE_BACKUP" /app/graph_engine
    rm -f "$ENGINE_BACKUP"
}
trap restore_engine EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import json
import os
import secrets
import subprocess

import pytest

EXECUTABLE = "/home/user/sanitizer"
SOURCE = "/home/user/sanitizer.c"
REBUILT = "/tmp/sanitizer_rebuilt"
ENGINE = "/app/graph_engine"


def run_program(path, query, timeout=5):
    return subprocess.run(
        [path], input=query, capture_output=True, timeout=timeout
    )


def test_complete_sanitizer():
    # Preserve the original artifact assertions and additionally require C source.
    assert os.path.exists(EXECUTABLE), f"Sanitizer executable not found at {EXECUTABLE}"
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a file"
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer must be a compiled executable"

    assert os.path.exists(SOURCE), f"C source not found at {SOURCE}"
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file"
    build = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", REBUILT],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"sanitizer.c does not compile:\n{build.stderr}"
    assert os.access(REBUILT, os.X_OK)

    # Keep the original corpus checks against the submitted executable.
    clean_files = glob.glob("/home/user/clean/*")
    evil_files = glob.glob("/home/user/evil/*")
    assert len(clean_files) > 0, "No clean files found in corpus"
    assert len(evil_files) > 0, "No evil files found in corpus"

    expected_json = [
        {"node_id": "101", "label": "Person", "prop_value": "Developer"},
        {"node_id": "102", "label": "System", "prop_value": "Database"},
    ]
    evil_bypassed = []
    clean_modified = []

    for filename in evil_files:
        with open(filename, "rb") as f:
            result = subprocess.run(
                [EXECUTABLE], stdin=f, capture_output=True, timeout=5
            )
        if result.returncode != 1 or result.stdout.strip() != b"REJECT":
            evil_bypassed.append(os.path.basename(filename))

    for filename in clean_files:
        with open(filename, "rb") as f:
            result = subprocess.run(
                [EXECUTABLE], stdin=f, capture_output=True, timeout=5
            )
        if result.returncode != 0:
            clean_modified.append(os.path.basename(filename))
            continue
        try:
            if json.loads(result.stdout) != expected_json:
                clean_modified.append(os.path.basename(filename))
        except (json.JSONDecodeError, UnicodeDecodeError):
            clean_modified.append(os.path.basename(filename))

    errors = []
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_bypassed)
        )
    if clean_modified:
        errors.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified/failed: "
            + ", ".join(clean_modified)
        )
    assert not errors, " | ".join(errors)

    # Replace the engine with a runtime-randomized PSV producer. Its output is
    # derived from the exact stdin it receives, so hardcoded corpus answers fail.
    nonce = secrets.token_hex(12)
    log_path = f"/tmp/engine_input_{secrets.token_hex(10)}"
    stub = f'''#!/usr/bin/env python3
import hashlib
import sys

data = sys.stdin.buffer.read()
with open({log_path!r}, "wb") as out:
    out.write(data)
digest = hashlib.sha256(data).hexdigest()[:24]
print("key_{nonce}|token_{nonce}|size_{nonce}")
print(f"{{digest}}|{nonce}|{{len(data)}}")
print(f"row2_{{digest}}|value_{nonce}|{{len(data) + 7}}")
'''
    with open(ENGINE, "w", encoding="utf-8") as f:
        f.write(stub)
    os.chmod(ENGINE, 0o755)

    programs = [EXECUTABLE, REBUILT]
    for program in programs:
        for i in range(4):
            query = (
                f"MATCH (n:Safe_{secrets.token_hex(8)}) "
                f"WHERE n.v = '{secrets.token_hex(12)}' RETURN n, {i}\n"
            ).encode()
            if os.path.exists(log_path):
                os.unlink(log_path)
            result = run_program(program, query)
            assert result.returncode == 0, (
                f"Safe query failed for {program}: return code {result.returncode}, "
                f"stderr={result.stderr!r}"
            )
            assert os.path.exists(log_path), f"{program} did not execute /app/graph_engine"
            with open(log_path, "rb") as f:
                assert f.read() == query, f"{program} did not feed the query unchanged to the engine"

            digest = hashlib.sha256(query).hexdigest()[:24]
            expected = [
                {
                    f"key_{nonce}": digest,
                    f"token_{nonce}": nonce,
                    f"size_{nonce}": str(len(query)),
                },
                {
                    f"key_{nonce}": f"row2_{digest}",
                    f"token_{nonce}": f"value_{nonce}",
                    f"size_{nonce}": str(len(query) + 7),
                },
            ]
            try:
                actual = json.loads(result.stdout)
            except (json.JSONDecodeError, UnicodeDecodeError) as exc:
                pytest.fail(f"{program} emitted invalid JSON: {exc}; output={result.stdout!r}")
            assert actual == expected, f"{program} did not convert the runtime PSV output correctly"

        # Exercise both required malicious substrings in fresh, unpredictable queries.
        evil_queries = [
            f"MATCH (a_{secrets.token_hex(6)})-[:CORRUPT]->(b) RETURN b\n".encode(),
            (
                f"MATCH (n_{secrets.token_hex(6)}) USING INDEX stale_rels "
                f"RETURN n, '{secrets.token_hex(8)}'\n"
            ).encode(),
        ]
        for query in evil_queries:
            if os.path.exists(log_path):
                os.unlink(log_path)
            result = run_program(program, query)
            assert result.returncode == 1, f"{program} did not exit 1 for a malicious query"
            assert result.stdout.strip() == b"REJECT", f"{program} did not print REJECT"
            assert not os.path.exists(log_path), (
                f"{program} invoked graph_engine before rejecting a malicious query"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
