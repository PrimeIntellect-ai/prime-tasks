#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import pwd
import random
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

ORACLE = "/app/oracle_cleaner"
PROJECT = pathlib.Path("/home/user/cleaner")
AGENT = PROJECT / "target/release/cleaner"
PIPELINE = pathlib.Path("/home/user/pipeline.sh")
DB = pathlib.Path("/home/user/clean_data.db")
RAW = pathlib.Path("/app/raw_data.jsonl")


def user_preexec():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def run_as_user(argv, *, input_bytes=None, timeout=60, env=None):
    child_env = os.environ.copy()
    child_env.update({"HOME": "/home/user", "USER": "user", "LOGNAME": "user"})
    if env:
        child_env.update(env)
    return subprocess.run(
        argv,
        input=input_bytes,
        capture_output=True,
        timeout=timeout,
        env=child_env,
        preexec_fn=user_preexec,
    )


def run_without_oracle(argv, *, input_bytes=None, timeout=60):
    """Run submitted artifacts as the unprivileged agent user with the oracle inaccessible."""
    hidden_dir = tempfile.mkdtemp(prefix="held-oracle-", dir="/tmp")
    os.chmod(hidden_dir, 0o700)
    hidden_oracle = os.path.join(hidden_dir, "oracle")
    os.rename(ORACLE, hidden_oracle)
    try:
        return run_as_user(argv, input_bytes=input_bytes, timeout=timeout)
    finally:
        os.rename(hidden_oracle, ORACLE)
        os.rmdir(hidden_dir)


@pytest.fixture(scope="session")
def rebuilt_cleaner():
    assert PROJECT.is_dir(), "Rust project missing at /home/user/cleaner"
    assert (PROJECT / "Cargo.toml").is_file(), "Cargo.toml missing"
    assert (PROJECT / "src/main.rs").is_file(), "src/main.rs missing"

    assert AGENT.exists(), f"Agent binary not found at {AGENT}"
    assert os.access(AGENT, os.X_OK), "Agent binary is not executable"
    assert AGENT.read_bytes()[:4] == b"\x7fELF", "Required cleaner artifact is not a native executable"
    assert AGENT.read_bytes() != pathlib.Path(ORACLE).read_bytes(), "Cleaner is a copy of the oracle"

    target = tempfile.mkdtemp(prefix="cleaner-build-", dir="/tmp")
    proc = subprocess.run(
        ["/opt/rust/bin/cargo", "build", "--release", "--target-dir", target],
        cwd=str(PROJECT),
        capture_output=True,
        timeout=240,
        env={**os.environ, "CARGO_HOME": "/opt/rust", "RUSTUP_HOME": "/opt/rust"},
    )
    assert proc.returncode == 0, f"Rust project does not build:\n{proc.stderr.decode(errors='replace')}"
    rebuilt = pathlib.Path(target) / "release/cleaner"
    assert rebuilt.exists() and os.access(rebuilt, os.X_OK), "Cargo did not produce cleaner"
    assert rebuilt.read_bytes()[:4] == b"\x7fELF", "Cargo output is not a native executable"
    os.chmod(rebuilt, 0o755)
    yield str(rebuilt)
    shutil.rmtree(target, ignore_errors=True)


def test_fuzz_equivalence(rebuilt_cleaner):
    # Differential testing is retained on inputs for which the legacy oracle implements
    # the specification. The submitted executable is run only after the oracle is hidden.
    random.seed(42)
    lines = []
    for _ in range(10000):
        if random.random() < 0.5:
            dev_id = "DEV-" + "".join(random.choices("ABCDEF0123456789", k=4))
        else:
            dev_id = "".join(random.choices("ABCDEF0123456789", k=8))
        temp = random.uniform(-50.0, 150.0)
        notes = "notes-" + "".join(random.choices("abcdefghijklmnopqrstuvwxyz0123456789", k=12))
        lines.append(json.dumps(
            {"device_id": dev_id, "temperature": temp, "notes": notes},
            separators=(",", ":"),
        ))
    input_data = ("\n".join(lines) + "\n").encode()

    proc_oracle = subprocess.run([ORACLE], input=input_data, capture_output=True, timeout=60)
    assert proc_oracle.returncode == 0, "Oracle failed on fuzz input"

    proc_agent = run_without_oracle([rebuilt_cleaner], input_bytes=input_data, timeout=60)
    assert proc_agent.returncode == 0, proc_agent.stderr.decode(errors="replace")
    assert proc_agent.stdout == proc_oracle.stdout, "Cleaner differs from the reference behavior"


def test_unicode_repair_and_schema(rebuilt_cleaner):
    # These expectations are derived from the written requirement rather than the legacy
    # oracle, which incorrectly discards malformed Unicode escapes.
    raw_lines = [
        r'{"device_id":"DEV-U1","temperature":1.5,"notes":"caf\u00e9"}',
        r'{"device_id":"DEV-U2","temperature":2.5,"notes":"bad\u12G4tail"}',
        r'{"device_id":"DEV-U3","temperature":3.5,"notes":"high\uD800tail"}',
        r'{"device_id":"DEV-U4","temperature":4.5,"notes":"low\uDC00tail"}',
        r'{"device_id":"DEV-U5","temperature":5.5,"notes":"pair\uD83D\uDE00"}',
        r'{"device_id":"BAD-U6","temperature":6.5,"notes":"drop"}',
        r'{"device_id":"DEV-U7","temperature":100.0,"notes":"drop"}',
        r'{"device_id":"DEV-U8","temperature":101.0,"notes":"drop"}',
        'not json',
    ]
    expected_objects = [
        {"device_id": "DEV-U1", "temperature": 1.5, "notes": "café"},
        {"device_id": "DEV-U2", "temperature": 2.5, "notes": "bad�tail"},
        {"device_id": "DEV-U3", "temperature": 3.5, "notes": "high�tail"},
        {"device_id": "DEV-U4", "temperature": 4.5, "notes": "low�tail"},
        {"device_id": "DEV-U5", "temperature": 5.5, "notes": "pair😀"},
    ]
    input_data = ("\n".join(raw_lines) + "\n").encode()
    proc = run_without_oracle([rebuilt_cleaner], input_bytes=input_data)
    assert proc.returncode == 0, proc.stderr.decode(errors="replace")

    output_lines = proc.stdout.splitlines()
    assert len(output_lines) == len(expected_objects), proc.stdout.decode(errors="replace")
    assert [json.loads(line) for line in output_lines] == expected_objects
    for line in output_lines:
        assert b"\\u00e9" not in line and b"\\ud83d" not in line.lower()
        assert line == line.strip() and b"\n" not in line
        # Re-encoding the parsed object with compact UTF-8 JSON must give the same line.
        parsed = json.loads(line)
        assert line == json.dumps(parsed, ensure_ascii=False, separators=(",", ":")).encode()


def test_pipeline_and_db(rebuilt_cleaner):
    assert PIPELINE.exists(), "pipeline.sh missing at /home/user/pipeline.sh"
    script = PIPELINE.read_text(errors="replace")
    assert "/app/raw_data.jsonl" in script, "pipeline does not read the required raw dataset"
    assert "/home/user/cleaner/target/release/cleaner" in script, "pipeline does not invoke the cleaner"
    assert "sqlite3" in script, "pipeline does not use the sqlite3 CLI"
    assert "|" in script, "pipeline does not implement the required pipe"

    token = uuid.uuid4().hex[:10]
    good1 = f"DEV-{token}-A"
    good2 = f"DEV-{token}-B"
    bad_prefix = f"BAD-{token}"
    too_hot = f"DEV-{token}-HOT"
    test_raw = (
        f'{{"device_id":"{good1}","temperature":12.0,"notes":"alpha"}}\n'
        f'{{"device_id":"{bad_prefix}","temperature":12.0,"notes":"reject"}}\n'
        f'{{"device_id":"{too_hot}","temperature":100.0,"notes":"reject"}}\n'
        f'{{"device_id":"{good2}","temperature":-3.0,"notes":"beta"}}\n'
    ).encode()

    original_raw = RAW.read_bytes()
    try:
        RAW.write_bytes(test_raw)
        if DB.exists():
            DB.unlink()
        proc = run_without_oracle(["/bin/bash", str(PIPELINE)], timeout=90)
        assert proc.returncode == 0, f"pipeline failed:\n{proc.stderr.decode(errors='replace')}"
    finally:
        RAW.write_bytes(original_raw)

    assert DB.exists(), "clean_data.db missing at /home/user/clean_data.db"
    conn = sqlite3.connect(str(DB))
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='readings'")
        assert cursor.fetchone() is not None, "Table 'readings' not found in clean_data.db"
        cursor.execute("SELECT COUNT(*) FROM readings")
        count = cursor.fetchone()[0]
        assert count > 0, "Table 'readings' is empty, pipeline did not insert data properly."
        assert count == 2, f"pipeline imported {count} rows instead of the two valid records"
        cursor.execute("SELECT * FROM readings")
        rows = cursor.fetchall()
    finally:
        conn.close()

    rendered = "\n".join("|".join("" if value is None else str(value) for value in row) for row in rows)
    assert good1 in rendered and good2 in rendered, "valid cleaned records were not imported"
    assert bad_prefix not in rendered and too_hot not in rendered, "invalid records were imported"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
