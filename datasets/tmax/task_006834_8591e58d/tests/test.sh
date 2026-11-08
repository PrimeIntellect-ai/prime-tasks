#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess
import tarfile
import tempfile

ARTIFACTS = "/home/user/artifacts"
EXTRACTED = os.path.join(ARTIFACTS, "extracted")
METADATA = os.path.join(EXTRACTED, "metadata.json")
VERIFY_GO = os.path.join(ARTIFACTS, "verify.go")
REPORT = os.path.join(ARTIFACTS, "report.csv")
ARCHIVE = os.path.join(ARTIFACTS, "raw_binaries.tar.gz")

EXPECTED_METADATA = [
    {
        "id": "bin_1.dat",
        "target_name": "release_v1.0.0-linux-amd64.bin",
        "expected_sha256": "c9158fb7ff6645db7d264f3c75ebbd7806f1d9bd5c2f82684821a71af2747120",
    },
    {
        "id": "bin_2.dat",
        "target_name": "release_v1.0.0-darwin-arm64.bin",
        "expected_sha256": "00b0f20d6fcc4cd15494d4a51eec77e23117dd1081a29ffbf7c5035f586a117b",
    },
    {
        "id": "bin_3.dat",
        "target_name": "release_v1.0.0-windows-amd64.exe",
        "expected_sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    },
]


def run_program():
    result = subprocess.run(
        ["go", "run", VERIFY_GO],
        cwd=ARTIFACTS,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Go verifier failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT), "Running verify.go did not create report.csv."


def read_report():
    with open(REPORT, "r", newline="") as f:
        return list(csv.reader(f))


def assert_exact_report(expected):
    rows = read_report()
    assert rows, "The CSV file is empty."
    assert rows[0] == ["TargetName", "Match"], (
        f"CSV header is incorrect. Expected ['TargetName', 'Match'], got {rows[0]}"
    )
    assert len(rows) == len(expected) + 1, "CSV contains missing or unexpected rows."
    for row in rows[1:]:
        assert len(row) == 2, f"Invalid CSV row length: {row}"
    actual = [(row[0], row[1].lower()) for row in rows[1:]]
    assert actual == expected, f"Incorrect CSV rows: expected {expected}, got {actual}"


def test_extracted_and_renamed_files():
    assert os.path.isdir(EXTRACTED), f"Directory {EXTRACTED} does not exist."
    assert os.path.isfile(METADATA), f"File {METADATA} does not exist."
    assert os.path.isfile(ARCHIVE), f"Input archive {ARCHIVE} does not exist."

    with open(METADATA, "r") as f:
        metadata = json.load(f)
    assert metadata == EXPECTED_METADATA, "Extracted metadata.json does not match the supplied repository metadata."

    with tarfile.open(ARCHIVE, "r:gz") as archive:
        members = {m.name.lstrip("./"): m for m in archive.getmembers() if m.isfile()}
        assert set(members) == {"metadata.json", *(entry["id"] for entry in metadata)}, (
            "The supplied archive has unexpected or missing files."
        )
        archived_metadata = json.loads(archive.extractfile(members["metadata.json"]).read())
        assert archived_metadata == metadata, "Extracted metadata differs from metadata in the archive."

        for entry in metadata:
            old_id = entry["id"]
            target_name = entry["target_name"]
            old_path = os.path.join(EXTRACTED, old_id)
            new_path = os.path.join(EXTRACTED, target_name)

            assert not os.path.exists(old_path), f"File {old_path} was not renamed."
            assert os.path.isfile(new_path), f"File {new_path} does not exist. Renaming failed."
            archived_bytes = archive.extractfile(members[old_id]).read()
            with open(new_path, "rb") as f:
                assert f.read() == archived_bytes, f"Renamed file {new_path} differs from the archived binary."


def test_verify_go_exists_and_runs():
    assert os.path.isfile(VERIFY_GO), f"Go program {VERIFY_GO} does not exist."
    assert not os.path.islink(VERIFY_GO), "verify.go must be a source file, not a symbolic link."
    with open(VERIFY_GO, "r", encoding="utf-8") as f:
        source = f.read()
    assert re.search(r"//|/\\*", source), "verify.go is not commented as required."

    if os.path.exists(REPORT):
        os.remove(REPORT)
    run_program()


def test_report_csv_content():
    assert os.path.isfile(REPORT), f"Report file {REPORT} does not exist."

    expected_rows = {
        "release_v1.0.0-linux-amd64.bin": "true",
        "release_v1.0.0-darwin-arm64.bin": "true",
        "release_v1.0.0-windows-amd64.exe": "false",
    }

    rows = read_report()
    assert len(rows) > 0, "The CSV file is empty."
    header = rows[0]
    assert header == ["TargetName", "Match"], f"CSV header is incorrect. Expected ['TargetName', 'Match'], got {header}"

    actual_rows = {}
    for row in rows[1:]:
        assert len(row) == 2, f"Invalid CSV row length: {row}"
        assert row[0] not in actual_rows, f"Duplicate CSV row for {row[0]}."
        actual_rows[row[0]] = row[1].lower()

    for target_name, expected_match in expected_rows.items():
        assert target_name in actual_rows, f"Missing target name {target_name} in CSV report."
        assert actual_rows[target_name] == expected_match, f"Expected match value '{expected_match}' for {target_name}, got '{actual_rows[target_name]}'."

    assert len(actual_rows) == len(expected_rows), "CSV contains unexpected extra rows."


def test_program_computes_sha256_from_runtime_inputs():
    backup_root = tempfile.mkdtemp(prefix="artifact-verifier-backup-")
    backup_extracted = os.path.join(backup_root, "extracted")
    shutil.copytree(EXTRACTED, backup_extracted)

    try:
        shutil.rmtree(EXTRACTED)
        os.mkdir(EXTRACTED)

        metadata = []
        expected = []
        contents = []
        for i in range(4):
            target = f"runtime-{secrets.token_hex(8)}-{i}.bin"
            content = secrets.token_bytes(37 + i * 19)
            contents.append(content)
            digest = hashlib.sha256(content).hexdigest()
            claimed = digest if i % 2 == 0 else hashlib.sha256(secrets.token_bytes(51)).hexdigest()
            metadata.append({
                "id": f"input_{secrets.token_hex(5)}.dat",
                "target_name": target,
                "expected_sha256": claimed,
            })
            with open(os.path.join(EXTRACTED, target), "wb") as f:
                f.write(content)
            expected.append((target, str(digest == claimed).lower()))

        with open(METADATA, "w") as f:
            json.dump(metadata, f)

        if os.path.exists(REPORT):
            os.remove(REPORT)
        run_program()
        assert_exact_report(expected)

        # Change a file after the first run and require a freshly computed result.
        first_path = os.path.join(EXTRACTED, metadata[0]["target_name"])
        with open(first_path, "ab") as f:
            f.write(secrets.token_bytes(23))
        expected[0] = (metadata[0]["target_name"], "false")

        os.remove(REPORT)
        run_program()
        assert_exact_report(expected)
    finally:
        if os.path.exists(EXTRACTED):
            shutil.rmtree(EXTRACTED)
        shutil.copytree(backup_extracted, EXTRACTED)
        shutil.rmtree(backup_root)
        if os.path.isfile(VERIFY_GO):
            if os.path.exists(REPORT):
                os.remove(REPORT)
            subprocess.run(
                ["go", "run", VERIFY_GO], cwd=ARTIFACTS,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
            )


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
