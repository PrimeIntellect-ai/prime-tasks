#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_config_tracker.py
import csv
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tarfile
import tempfile
import uuid

CONFIG_DIR = "/home/user/config_data"
OUTPUT_DIR = "/home/user/output"
MANIFEST_PATH = os.path.join(OUTPUT_DIR, "manifest.csv")
TARBALL_PATH = os.path.join(OUTPUT_DIR, "active_configs.tar.gz")
SOURCE_PATH = "/home/user/config_tracker.cpp"
BINARY_PATH = "/home/user/config_tracker"
COMPILED_PATH = "/tmp/config_tracker_from_source"


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(4096), b""):
            h.update(block)
    return h.hexdigest()


def clear_outputs():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for path in (MANIFEST_PATH, TARBALL_PATH):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)


def run_program(path):
    clear_outputs()
    result = subprocess.run(
        [path], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def derive_expected():
    last_operation = {}
    wal_path = os.path.join(CONFIG_DIR, "history.wal")
    with open(wal_path, "r", encoding="utf-8") as f:
        for line in f:
            fields = line.split()
            assert len(fields) == 3, f"Malformed verifier fixture WAL line: {line!r}"
            _, operation, filename = fields
            assert operation in {"ADD", "UPDATE", "DELETE"}
            last_operation[filename] = operation

    expected = []
    for filename in sorted(
        name for name, operation in last_operation.items()
        if operation in {"ADD", "UPDATE"}
    ):
        path = os.path.join(CONFIG_DIR, filename)
        with open(path, "r", encoding="utf-8") as f:
            version = str(json.load(f)["version"])
        expected.append([filename, version, sha256_file(path)])
    return expected


def validate_outputs(expected):
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"
    with open(MANIFEST_PATH, "r", newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))

    assert rows, "Manifest is empty"
    assert rows[0] == ["filename", "version", "sha256"], f"Incorrect header in manifest: {rows[0]}"
    assert len(rows) == len(expected) + 1, (
        f"Manifest should have exactly {len(expected) + 1} rows, but found {len(rows)}"
    )
    assert rows[1:] == expected, f"Incorrect manifest rows: {rows[1:]}; expected {expected}"
    for row in rows[1:]:
        assert len(row[2]) == 64 and all(c in "0123456789abcdef" for c in row[2]), (
            f"Invalid SHA256 field: {row[2]}"
        )

    assert os.path.isfile(TARBALL_PATH), f"Tarball missing at {TARBALL_PATH}"
    assert tarfile.is_tarfile(TARBALL_PATH), f"File {TARBALL_PATH} is not a valid tar archive"
    expected_names = [row[0] for row in expected]
    with tarfile.open(TARBALL_PATH, "r:gz") as tar:
        members = tar.getmembers()
        names = [member.name for member in members]
        assert sorted(names) == expected_names, (
            f"Tarball must contain exactly {expected_names} at the root, but found {names}"
        )
        assert len(names) == len(set(names)), "Tarball contains duplicate members"
        for member in members:
            assert member.isfile(), f"Archive member is not a regular file: {member.name}"
            assert "/" not in member.name and member.name not in {".", ".."}, (
                f"Archive member is not at the archive root: {member.name}"
            )
            archived = tar.extractfile(member)
            assert archived is not None
            archived_data = archived.read()
            with open(os.path.join(CONFIG_DIR, member.name), "rb") as f:
                source_data = f.read()
            assert archived_data == source_data, (
                f"Archived contents differ from {member.name}"
            )
            assert sha256_bytes(archived_data) == next(
                row[2] for row in expected if row[0] == member.name
            )


def install_random_fixture():
    token = uuid.uuid4().hex
    names = [f"cfg_{token}_{suffix}.json" for suffix in ("alpha", "beta", "gamma", "delta")]
    versions = [
        f"{int(token[0:2], 16)}.{int(token[2:4], 16)}.{int(token[4:6], 16)}",
        f"{int(token[6:8], 16)}.{int(token[8:10], 16)}.{int(token[10:12], 16)}",
        f"{int(token[12:14], 16)}.{int(token[14:16], 16)}.{int(token[16:18], 16)}",
        f"{int(token[18:20], 16)}.{int(token[20:22], 16)}.{int(token[22:24], 16)}",
    ]

    if os.path.exists(CONFIG_DIR):
        shutil.rmtree(CONFIG_DIR)
    os.makedirs(CONFIG_DIR)
    for index, (name, version) in enumerate(zip(names, versions)):
        with open(os.path.join(CONFIG_DIR, name), "w", encoding="utf-8") as f:
            json.dump({"name": token + str(index), "version": version, "enabled": index % 2 == 0}, f)
            f.write("\n")

    operations = [
        ("ADD", names[1]),
        ("ADD", names[0]),
        ("UPDATE", names[1]),
        ("ADD", names[2]),
        ("DELETE", names[0]),
        ("ADD", names[3]),
        ("UPDATE", names[2]),
        ("DELETE", names[3]),
    ]
    with open(os.path.join(CONFIG_DIR, "history.wal"), "w", encoding="utf-8") as f:
        for sequence, (operation, name) in enumerate(operations, 1):
            f.write(f"{sequence:03d} {operation} {name}\n")


def main():
    for path, description in ((SOURCE_PATH, "C++ source"), (BINARY_PATH, "compiled program")):
        assert os.path.exists(path), f"Missing {description}: {path}"
        assert not os.path.islink(path), f"{description} must not be a symbolic link: {path}"
        assert stat.S_ISREG(os.stat(path).st_mode), f"{description} is not a regular file: {path}"

    assert os.access(BINARY_PATH, os.X_OK), f"Compiled program is not executable: {BINARY_PATH}"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled program is not an ELF binary"

    compile_result = subprocess.run(
        ["g++", "-std=c++17", SOURCE_PATH, "-o", COMPILED_PATH],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert compile_result.returncode == 0, f"Source failed to compile:\n{compile_result.stderr}"

    backup_root = tempfile.mkdtemp(prefix="config_tracker_backup_")
    backup_config = os.path.join(backup_root, "config_data")
    shutil.copytree(CONFIG_DIR, backup_config)
    try:
        # Execute the submitted binary on the original data, then retain the
        # original verifier's concrete assertions.
        run_program(BINARY_PATH)
        expected_app1_sha = sha256_file(os.path.join(CONFIG_DIR, "app1.json"))
        expected_app3_sha = sha256_file(os.path.join(CONFIG_DIR, "app3.json"))
        with open(MANIFEST_PATH, "r", newline="", encoding="utf-8") as f:
            original_rows = list(csv.reader(f))
        assert len(original_rows) == 3, (
            f"Manifest should have exactly 3 rows (header + 2 active files), but found {len(original_rows)}."
        )
        assert original_rows[0] == ["filename", "version", "sha256"], (
            f"Incorrect header in manifest: {original_rows[0]}"
        )
        assert original_rows[1] == ["app1.json", "1.4.2", expected_app1_sha], (
            f"Incorrect row for app1.json: {original_rows[1]}"
        )
        assert original_rows[2] == ["app3.json", "9.4.1", expected_app3_sha], (
            f"Incorrect row for app3.json: {original_rows[2]}"
        )
        validate_outputs(derive_expected())

        # Exercise the submitted binary on unpredictable WAL and JSON data.
        install_random_fixture()
        expected = derive_expected()
        run_program(BINARY_PATH)
        validate_outputs(expected)

        # Independently ensure the submitted source implements the same work.
        install_random_fixture()
        expected = derive_expected()
        run_program(COMPILED_PATH)
        validate_outputs(expected)
    finally:
        if os.path.exists(CONFIG_DIR):
            shutil.rmtree(CONFIG_DIR)
        shutil.copytree(backup_config, CONFIG_DIR)
        shutil.rmtree(backup_root, ignore_errors=True)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_config_tracker.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
