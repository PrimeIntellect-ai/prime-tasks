#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/proto_filter.sh"
LEGACY_PATH = "/app/legacy_filter"
EVIL_DIR = "/test_data/evil"
CLEAN_DIR = "/test_data/clean"


def run_filter(program, filepath, as_user=False):
    kwargs = {}
    if as_user:
        account = pwd.getpwnam("user")

        def demote():
            os.setgroups([])
            os.setgid(account.pw_gid)
            os.setuid(account.pw_uid)

        kwargs["preexec_fn"] = demote
    try:
        return subprocess.run(
            [program, filepath],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            **kwargs,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter timed out on {filepath}")


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"

    data = Path(SCRIPT_PATH).read_bytes()
    assert b"\x00" not in data, "Submission is not a text Bash script"
    first_line = data.splitlines()[0] if data.splitlines() else b""
    assert first_line.startswith(b"#!") and b"bash" in first_line, \
        "Submission must be an executable Bash script"
    assert data != Path(LEGACY_PATH).read_bytes(), \
        "Submission must not be byte-identical to the legacy implementation"


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory missing: {EVIL_DIR}"
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith(".proto")]
    assert len(evil_files) > 0, f"No .proto files found in {EVIL_DIR}"

    bypassed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_DIR, filename)
        result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode == 0:
            bypassed_files.append(filename)

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed the filter (returned 0). Offending files: {', '.join(bypassed_files)}")


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing: {CLEAN_DIR}"
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith(".proto")]
    assert len(clean_files) > 0, f"No .proto files found in {CLEAN_DIR}"

    rejected_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_DIR, filename)
        result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            rejected_files.append(filename)

    if rejected_files:
        pytest.fail(f"{len(rejected_files)} of {len(clean_files)} clean files were incorrectly rejected (returned non-zero). Offending files: {', '.join(rejected_files)}")


def test_generated_hidden_corpus_matches_legacy():
    rng = random.Random(secrets.randbits(128))
    nonce = secrets.token_hex(12)
    cases = [
        'syntax = "proto3";\n',
        'import "pkg/valid.proto";\nmessage A {\n}\n',
        'import "foo/../bar.proto";\n',
        'import "../private.proto";\n',
        'import "/absolute/private.proto";\n',
        'service Admin {\n}\n',
        'service System {\n}\n',
        'service AdminService {\n}\n',
        'service Systematic {\n}\n',
        'service UserAdmin {\n}\n',
        'message A {\n message B {\n }\n}\n',
        'message A { message B { message C { } } }\n',
        '}\nmessage A { message B { message C { } } }\n',
        '// import "../also_rejected.proto";\n',
        '// service Admin is reserved\n',
        'option note = "{{{";\n',
    ]

    safe_lines = [
        'syntax = "proto3";',
        'package hidden_%s;' % nonce,
        'import "google/protobuf/empty.proto";',
        'service User_%s {' % nonce,
        'rpc Call (Req) returns (Req);',
        'message Req {',
        'string value = 1;',
        '}',
        '}',
        '// randomized_%s' % nonce,
    ]
    trigger_lines = [
        'import "../%s.proto";' % nonce,
        'import "/%s.proto";' % nonce,
        'service Admin%s {' % nonce,
        'service System%s {' % nonce,
        'message A { message B { message C {',
        '// service Admin%s' % nonce,
        '// import "../%s.proto";' % nonce,
    ]

    for _ in range(100):
        lines = [rng.choice(safe_lines) for _ in range(rng.randint(1, 8))]
        if rng.random() < 0.65:
            lines.insert(rng.randrange(len(lines) + 1), rng.choice(trigger_lines))
        for _ in range(rng.randint(0, 4)):
            lines.insert(rng.randrange(len(lines) + 1), rng.choice(['{', '}', 'message X {', '} // close']))
        cases.append("\n".join(lines) + "\n")

    with tempfile.TemporaryDirectory(prefix="proto-hidden-") as temp_dir:
        os.chmod(temp_dir, 0o755)
        paths = []
        for index, content in enumerate(cases):
            path = os.path.join(temp_dir, f"{nonce}_{index}_{secrets.token_hex(4)}.proto")
            Path(path).write_text(content)
            os.chmod(path, 0o644)
            paths.append(path)

        expected = [(run_filter(LEGACY_PATH, path) == 0) for path in paths]

        hidden_oracle = f"/root/.legacy_filter_verifier_{secrets.token_hex(12)}"
        os.replace(LEGACY_PATH, hidden_oracle)
        try:
            mismatches = []
            for index, (path, should_accept) in enumerate(zip(paths, expected)):
                accepted = run_filter(SCRIPT_PATH, path, as_user=True) == 0
                if accepted != should_accept:
                    mismatches.append(index)
            assert not mismatches, \
                f"Submission disagreed with the legacy filter on generated hidden cases: {mismatches}"
        finally:
            os.replace(hidden_oracle, LEGACY_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
