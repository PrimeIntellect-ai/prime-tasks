#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import PurePosixPath

HOME = "/home/user"
RECORDS = f"{HOME}/old_records"
ARCHIVE = f"{HOME}/old_records_archive.tar.gz"
SUMMARY = f"{HOME}/summary.txt"
PROJECT = f"{HOME}/space_saver"

ORIGINAL_EXPECTED = {
    "server1/logs/app.log": (
        b"[INFO] Application started\n"
        b"[WARN] Connection timeout\n"
        b"[INFO] Retrying connection\n"
    ),
    "server2/archive/deep/old_data.txt": (
        b"Data line 1\n"
        b"Data line 2\n"
        b"Data line 3\n"
    ),
    "server2/archive/ignore_me.csv": (
        b"id,name\n"
        b"1,alice\n"
        b"2,bob\n"
        b"[VERBOSE-DUMP] this should not be removed because it's a .csv file\n"
    ),
    "root_level.log": b"[INFO] Root initialized\n",
}


def normalized_member_name(name):
    path = PurePosixPath(name)
    assert not path.is_absolute(), f"Archive contains absolute path: {name}"
    parts = [part for part in path.parts if part not in ("", ".")]
    assert ".." not in parts, f"Archive contains unsafe path: {name}"
    if parts and parts[0] == "old_records":
        parts = parts[1:]
    return "/".join(parts)


def archive_files_exact(expected):
    assert os.path.isfile(ARCHIVE), f"{ARCHIVE} does not exist."
    assert tarfile.is_tarfile(ARCHIVE), f"{ARCHIVE} is not a valid tar file."

    actual = {}
    with tarfile.open(ARCHIVE, "r:gz") as tar:
        for member in tar.getmembers():
            rel = normalized_member_name(member.name)
            if member.isdir():
                continue
            assert rel, f"Unexpected non-directory archive member: {member.name}"
            assert member.isfile(), f"Unexpected non-regular archive member: {member.name}"
            assert rel not in actual, f"Duplicate archive member: {rel}"
            extracted = tar.extractfile(member)
            assert extracted is not None
            actual[rel] = extracted.read()

    assert set(actual) == set(expected), (
        f"Archive file set differs. Missing={set(expected)-set(actual)}, "
        f"extra={set(actual)-set(expected)}"
    )
    for rel, wanted in expected.items():
        assert actual[rel] == wanted, f"Archived contents differ for {rel}"


def find_file(root_dir, filename):
    for dirpath, _, filenames in os.walk(root_dir):
        if filename in filenames:
            return os.path.join(dirpath, filename)
    return None


def test_original_final_state_and_contents():
    assert not os.path.exists(RECORDS), f"{RECORDS} directory should be deleted."

    assert os.path.isfile(SUMMARY), f"{SUMMARY} does not exist."
    with open(SUMMARY, "r") as f:
        content = f.read().strip()
    assert content == "8", f"Expected summary.txt to contain '8', but found '{content}'."

    assert os.path.isfile(ARCHIVE), f"{ARCHIVE} does not exist."
    assert tarfile.is_tarfile(ARCHIVE), f"{ARCHIVE} is not a valid tar file."

    with tarfile.open(ARCHIVE, "r:gz") as tar:
        with tempfile.TemporaryDirectory() as tmpdir:
            tar.extractall(path=tmpdir)
            app_log = find_file(tmpdir, "app.log")
            old_data = find_file(tmpdir, "old_data.txt")
            ignore_me = find_file(tmpdir, "ignore_me.csv")
            root_log = find_file(tmpdir, "root_level.log")

            assert app_log is not None, "app.log missing in archive."
            assert old_data is not None, "old_data.txt missing in archive."
            assert ignore_me is not None, "ignore_me.csv missing in archive."
            assert root_log is not None, "root_level.log missing in archive."

            with open(app_log) as f:
                data = f.read()
                assert "[VERBOSE-DUMP]" not in data
                assert "[INFO] Application started" in data
                assert "[WARN] Connection timeout" in data
            with open(old_data) as f:
                data = f.read()
                assert "[VERBOSE-DUMP]" not in data
                assert "Data line 1" in data
                assert "Data line 2" in data
            with open(root_log) as f:
                data = f.read()
                assert "[VERBOSE-DUMP]" not in data
                assert "[INFO] Root initialized" in data
            with open(ignore_me) as f:
                data = f.read()
                assert "[VERBOSE-DUMP]" in data
                assert "1,alice" in data

    archive_files_exact(ORIGINAL_EXPECTED)


def test_rust_project_on_fresh_unpredictable_input():
    assert os.path.isdir(PROJECT), "Rust project /home/user/space_saver is missing."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing."
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "src/main.rs is missing."

    shutil.rmtree(RECORDS, ignore_errors=True)
    for path in (ARCHIVE, SUMMARY):
        if os.path.lexists(path):
            os.remove(path)

    token = secrets.token_hex(12)
    total_to_remove = 9 + secrets.randbelow(8)
    paths = [
        f"node_{token}/logs/service_{token}.log",
        f"node_{token}/deep/history/report_{token}.txt",
        f"other_{token}/audit_{token}.log",
    ]
    allocations = [2, 3, total_to_remove - 5]
    expected = {}

    for index, (rel, count) in enumerate(zip(paths, allocations)):
        full = os.path.join(RECORDS, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        kept = [
            f"ordinary-{token}-{index}-a\n".encode(),
            f"prefix [VERBOSE-DUMP] embedded-{token}-{index}\n".encode(),
            f" [VERBOSE-DUMP] leading-space-{token}-{index}\n".encode(),
            f"ordinary-{token}-{index}-b\n".encode(),
        ]
        source = kept[:1]
        source.extend(
            f"[VERBOSE-DUMP] generated-{token}-{index}-{n}\n".encode()
            for n in range(count)
        )
        source.extend(kept[1:])
        with open(full, "wb") as f:
            f.write(b"".join(source))
        expected[rel] = b"".join(kept)

    csv_rel = f"node_{token}/keep_{token}.csv"
    csv_data = (
        f"id,value\n1,{token}\n"
        f"[VERBOSE-DUMP] csv-must-remain-{token}\n"
    ).encode()
    csv_full = os.path.join(RECORDS, csv_rel)
    os.makedirs(os.path.dirname(csv_full), exist_ok=True)
    with open(csv_full, "wb") as f:
        f.write(csv_data)
    expected[csv_rel] = csv_data

    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f"Rust program failed when executed:\n{result.stdout}"
    assert not os.path.exists(RECORDS), "Rust program did not delete fresh old_records input."

    assert os.path.isfile(SUMMARY), "Rust program did not create summary.txt."
    with open(SUMMARY, "r") as f:
        summary = f.read().strip()
    assert summary == str(total_to_remove), (
        f"Expected dynamically derived count {total_to_remove}, found {summary!r}."
    )

    archive_files_exact(expected)

    for rel, data in expected.items():
        if rel.endswith((".txt", ".log")):
            assert not any(
                line.startswith(b"[VERBOSE-DUMP]") for line in data.splitlines()
            )

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
