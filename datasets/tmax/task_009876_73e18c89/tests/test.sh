#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import fcntl
import json
import os
import shutil
import subprocess
import time
import uuid

SCRIPT = "/home/user/curate_artifacts.py"
REPO = "/home/user/artifact_repo"
LOG = os.path.join(REPO, "curation.log")
CSV = os.path.join(REPO, "valid_inventory.csv")


def run_script(timeout=20):
    return subprocess.run(
        ["python3", SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def read_csv():
    with open(CSV, "r", newline="") as f:
        return list(csv.reader(f))


def write_records(records):
    with open(LOG, "w") as f:
        for index, record in enumerate(records):
            json.dump(record, f, indent=2)
            f.write("\n")
            if index != len(records) - 1:
                f.write("---\n")


def test_script_exists_and_uses_fcntl():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."

    with open(SCRIPT, "r") as f:
        content = f.read()

    assert "fcntl.flock" in content or "fcntl.lockf" in content, (
        "Script does not contain 'fcntl.flock' or 'fcntl.lockf' for file locking."
    )

    tree = ast.parse(content, filename=SCRIPT)
    non_streaming_calls = [
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr in {"read", "readlines", "read_text"}
    ]
    assert not non_streaming_calls, (
        "The curation script must iterate through the large log rather than reading "
        f"an entire file at once; found calls to {non_streaming_calls}."
    )


def test_csv_output_correctness():
    if os.path.exists(CSV):
        os.remove(CSV)

    result = run_script()
    assert result.returncode == 0, (
        f"Script failed on the supplied repository. stdout={result.stdout!r} "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(CSV), f"Output CSV {CSV} does not exist."

    rows = read_csv()
    assert len(rows) > 0, "CSV file is empty."
    assert rows[0] == ["ArtifactID", "ResolvedPath", "Checksum"], (
        f"CSV header is incorrect. Got {rows[0]}"
    )

    expected_rows = [
        ["pkg-101", "/home/user/artifact_repo/binaries/v1/core.bin", "a1b2c3d4"],
        ["pkg-103", "/home/user/artifact_repo/binaries/valid_pkg.bin", "12345678"],
        ["pkg-105", "/home/user/artifact_repo/binaries/v2/util.bin", "87654321"],
    ]
    assert len(rows) - 1 == len(expected_rows), (
        f"Expected {len(expected_rows)} data rows, but got {len(rows) - 1}."
    )
    for i, expected in enumerate(expected_rows):
        actual = rows[i + 1]
        assert actual == expected, (
            f"Row {i + 1} incorrect. Expected {expected}, got {actual}"
        )


def test_script_processes_altered_streaming_log_and_symlinks():
    original_log = open(LOG, "rb").read()
    original_csv = open(CSV, "rb").read() if os.path.exists(CSV) else None
    token = uuid.uuid4().hex
    dynamic_dir = os.path.join(REPO, "binaries", "verify_" + token)
    os.makedirs(dynamic_dir)

    real_one = os.path.join(dynamic_dir, "one.bin")
    real_two = os.path.join(dynamic_dir, "two.bin")
    with open(real_one, "wb") as f:
        f.write(os.urandom(31))
    with open(real_two, "wb") as f:
        f.write(os.urandom(47))

    alias = os.path.join(dynamic_dir, "alias.bin")
    os.symlink(real_two, alias)
    loop = os.path.join(dynamic_dir, "loop")
    os.symlink(loop, loop)

    rel = lambda path: os.path.relpath(path, REPO)
    first_id = "live-" + uuid.uuid4().hex
    second_id = "live-" + uuid.uuid4().hex
    records = [
        {
            "artifact_id": first_id,
            "path": rel(real_one),
            "checksum": "c-" + uuid.uuid4().hex,
            "status": "staged",
        }
    ]
    # Numerous individually delimited records ensure the implementation handles
    # records sequentially rather than depending on the original five rows.
    for i in range(6000):
        records.append({
            "artifact_id": f"old-{token}-{i}",
            "path": rel(real_one),
            "checksum": str(i),
            "status": "archived",
        })
    records.extend([
        {
            "artifact_id": "missing-" + token,
            "path": rel(os.path.join(dynamic_dir, "missing.bin")),
            "checksum": "missing",
            "status": "staged",
        },
        {
            "artifact_id": "loop-" + token,
            "path": rel(os.path.join(loop, "child.bin")),
            "checksum": "loop",
            "status": "staged",
        },
        {
            "artifact_id": second_id,
            "path": rel(alias),
            "checksum": "c-" + uuid.uuid4().hex,
            "status": "staged",
        },
    ])

    expected = [
        ["ArtifactID", "ResolvedPath", "Checksum"],
        [first_id, os.path.realpath(real_one), records[0]["checksum"]],
        [second_id, os.path.realpath(alias), records[-1]["checksum"]],
    ]

    try:
        write_records(records)
        if os.path.exists(CSV):
            os.remove(CSV)
        result = run_script(timeout=30)
        assert result.returncode == 0, (
            f"Script crashed on altered input or a symlink loop. "
            f"stdout={result.stdout!r} stderr={result.stderr!r}"
        )
        assert os.path.isfile(CSV), "Script did not create the inventory for altered input."
        assert read_csv() == expected
    finally:
        with open(LOG, "wb") as f:
            f.write(original_log)
        if original_csv is None:
            if os.path.exists(CSV):
                os.remove(CSV)
        else:
            with open(CSV, "wb") as f:
                f.write(original_csv)
        shutil.rmtree(dynamic_dir, ignore_errors=True)


def test_script_obeys_an_exclusive_csv_lock():
    original_log = open(LOG, "rb").read()
    original_csv = open(CSV, "rb").read() if os.path.exists(CSV) else None
    token = uuid.uuid4().hex
    artifact = os.path.join(REPO, "binaries", "lock_" + token + ".bin")
    with open(artifact, "wb") as f:
        f.write(b"lock test")

    record = {
        "artifact_id": "lock-" + token,
        "path": os.path.relpath(artifact, REPO),
        "checksum": token,
        "status": "staged",
    }
    process = None
    lock_file = None
    try:
        write_records([record])
        with open(CSV, "w"):
            pass
        lock_file = open(CSV, "r+")

        source = open(SCRIPT, "r").read()
        use_lockf = "fcntl.lockf" in source and "fcntl.flock" not in source
        if use_lockf:
            fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)
        else:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

        process = subprocess.Popen(
            ["python3", SCRIPT],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(0.6)
        assert process.poll() is None, (
            "The script completed while another process held an exclusive lock "
            "on valid_inventory.csv."
        )

        if use_lockf:
            fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)
        else:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()
        lock_file = None

        stdout, stderr = process.communicate(timeout=15)
        assert process.returncode == 0, (
            f"Script failed after the lock was released. stdout={stdout!r} stderr={stderr!r}"
        )
        assert read_csv() == [
            ["ArtifactID", "ResolvedPath", "Checksum"],
            [record["artifact_id"], os.path.realpath(artifact), token],
        ]
    finally:
        if lock_file is not None:
            try:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
                fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)
            except OSError:
                pass
            lock_file.close()
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        with open(LOG, "wb") as f:
            f.write(original_log)
        if original_csv is None:
            if os.path.exists(CSV):
                os.remove(CSV)
        else:
            with open(CSV, "wb") as f:
                f.write(original_csv)
        if os.path.lexists(artifact):
            os.remove(artifact)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
