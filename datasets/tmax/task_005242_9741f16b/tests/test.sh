#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile

import pytest

APP_DIR = "/home/user/app"


@pytest.fixture(scope="session", autouse=True)
def execute_migration_on_fresh_inputs():
    migrate_path = os.path.join(APP_DIR, "migrate.sh")
    assert os.path.isfile(migrate_path), f"Migration script {migrate_path} does not exist."

    # Replace the fixed sample rows with fresh inputs so precomputed JSONL output
    # cannot pass. Keep the same simple CSV format required by the task.
    rows = []
    for index in range(4):
        user_id = str(100000 + secrets.randbelow(800000))
        relative_path = f"data/verifier_avatar_{index}.txt"
        content = (secrets.token_hex(12) + f"_avatar_{index}").encode("ascii")
        with open(os.path.join(APP_DIR, relative_path), "wb") as f:
            f.write(content)
        rows.append((user_id, relative_path))

    with open(os.path.join(APP_DIR, "legacy.csv"), "w", newline="") as f:
        f.write("user_id,filepath\n")
        for user_id, relative_path in rows:
            f.write(f"{user_id},{relative_path}\n")

    hasher_source = os.path.join(APP_DIR, "hasher.c")
    assert os.path.isfile(hasher_source), f"Source file {hasher_source} does not exist."

    # Independently compile the supplied source for behavioral comparison.
    temp_dir = tempfile.mkdtemp(prefix="verifier_hasher_")
    reference_hasher = os.path.join(temp_dir, "reference_hasher")
    subprocess.run(
        ["gcc", hasher_source, "-o", reference_hasher],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )

    # Force migrate.sh to recreate both requested artifacts rather than relying
    # on anything left from the agent's earlier run.
    for artifact in ("hasher", "new_schema.jsonl"):
        path = os.path.join(APP_DIR, artifact)
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["bash", migrate_path],
        cwd=APP_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Running {migrate_path} failed with exit code {result.returncode}. "
        f"stdout: {result.stdout.decode(errors='replace')} "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )

    hasher_path = os.path.join(APP_DIR, "hasher")
    assert os.path.isfile(hasher_path), f"Running migrate.sh did not create {hasher_path}."
    with open(hasher_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The generated hasher is not a compiled ELF executable."

    # Exercise the generated executable on independently generated binary input
    # and compare it with a fresh compilation of hasher.c.
    samples = [b"", b"profile", secrets.token_bytes(37)]
    for sample in samples:
        expected = subprocess.run(
            [reference_hasher], input=sample, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10, check=True
        ).stdout
        actual = subprocess.run(
            [hasher_path], input=sample, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10, check=True
        ).stdout
        assert expected == b"WEB_" + sample, "The supplied hasher.c no longer has the required behavior."
        assert actual == expected, "The generated hasher does not behave like the compiled hasher.c source."


def test_hasher_compiled():
    hasher_path = os.path.join(APP_DIR, "hasher")
    assert os.path.isfile(hasher_path), f"Compiled executable {hasher_path} does not exist. Ensure you compiled hasher.c."
    assert os.access(hasher_path, os.X_OK), f"File {hasher_path} is not executable."


def test_new_schema_jsonl():
    jsonl_path = os.path.join(APP_DIR, "new_schema.jsonl")
    assert os.path.isfile(jsonl_path), f"Target file {jsonl_path} does not exist. Ensure your script generates it."

    csv_path = os.path.join(APP_DIR, "legacy.csv")
    assert os.path.isfile(csv_path), f"Source file {csv_path} does not exist."

    expected_data = {}
    with open(csv_path, "r") as f:
        lines = f.read().strip().split('\n')
        for line in lines[1:]:
            if not line.strip():
                continue
            user_id, filepath = line.split(',')

            full_filepath = os.path.join(APP_DIR, filepath)
            assert os.path.isfile(full_filepath), f"Expected data file {full_filepath} is missing."

            with open(full_filepath, "rb") as bf:
                content = bf.read()

            modified_content = b"WEB_" + content
            chunk = modified_content[:8]
            expected_hash = sum(chunk) % 255
            expected_data[str(user_id)] = expected_hash

    actual_data = {}
    with open(jsonl_path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
                assert "user_id" in obj, f"Missing 'user_id' in JSON object: {line}"
                assert "avatar_hash" in obj, f"Missing 'avatar_hash' in JSON object: {line}"
                actual_data[str(obj["user_id"])] = obj["avatar_hash"]
            except json.JSONDecodeError as e:
                pytest.fail(f"Could not parse line in {jsonl_path} as JSON: '{line}'. Error: {e}")

    assert actual_data == expected_data, f"Contents of {jsonl_path} do not match the expected computed hashes. Expected: {expected_data}, Actual: {actual_data}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
