#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

import pytest

EXPORT_DIR = "/home/user/export"
MANIFEST_FILE = "/home/user/manifest.csv"
HOME = Path("/home/user")


def test_export_directory_exists():
    assert os.path.exists(EXPORT_DIR), f"Directory {EXPORT_DIR} does not exist."
    assert os.path.isdir(EXPORT_DIR), f"{EXPORT_DIR} is not a directory."


def test_exported_files():
    expected_files = {"alpha.hex", "gamma.hex", "omega.hex"}

    if not os.path.exists(EXPORT_DIR):
        pytest.fail(f"Export directory {EXPORT_DIR} is missing.")

    actual_files = set(os.listdir(EXPORT_DIR))

    missing = expected_files - actual_files
    extra = actual_files - expected_files

    assert not missing, f"Missing expected exported files: {missing}"
    assert not extra, f"Found unexpected files in export directory: {extra}"


@pytest.mark.parametrize("filename, expected_hex", [
    ("alpha.hex", "54657374446174614F6E65"),
    ("gamma.hex", "457861637454696D65"),
    ("omega.hex", "4C61737456616C696444617461"),
])
def test_exported_file_contents(filename, expected_hex):
    file_path = os.path.join(EXPORT_DIR, filename)
    assert os.path.exists(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == expected_hex, f"Content of {filename} is incorrect. Expected {expected_hex}, got {content}"


def test_manifest_file():
    assert os.path.exists(MANIFEST_FILE), f"Manifest file {MANIFEST_FILE} does not exist."
    assert os.path.isfile(MANIFEST_FILE), f"{MANIFEST_FILE} is not a file."

    expected_lines = [
        "alpha.bin,1700000005,11",
        "gamma.bin,1700000000,9",
        "omega.bin,1725000000,13"
    ]

    with open(MANIFEST_FILE, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert lines == expected_lines, f"Manifest contents are incorrect or incorrectly sorted. Expected {expected_lines}, got {lines}"


def _artifact(timestamp, payload, magic=b"ARTF", checksum_delta=0,
              declared_size=None, trailing=b""):
    size = len(payload) if declared_size is None else declared_size
    checksum = (sum(payload) + checksum_delta) & 0xff
    return magic + struct.pack("<II", timestamp, size) + payload + bytes([checksum]) + trailing


def _install_dynamic_repo(repo, token):
    repo.mkdir(parents=True, exist_ok=True)
    payloads = {
        f"kiwi_{token}.bin": os.urandom(19),
        f"apple_{token}.bin": bytes(range(256)),
        f"middle_{token}.bin": b"\x00\xffDynamic\nPayload\x80",
        f"empty_{token}.bin": b"",
    }
    timestamps = {
        f"kiwi_{token}.bin": 1700000123,
        f"apple_{token}.bin": 4294967290,
        f"middle_{token}.bin": 1700000000,
        f"empty_{token}.bin": 1800000000,
    }

    for name, payload in payloads.items():
        (repo / name).write_bytes(_artifact(timestamps[name], payload))

    (repo / f"old_{token}.bin").write_bytes(_artifact(1699999999, os.urandom(8)))
    (repo / f"magic_{token}.bin").write_bytes(_artifact(1900000000, b"bad magic", magic=b"NOPE"))
    (repo / f"checksum_{token}.bin").write_bytes(_artifact(1900000001, b"bad checksum", checksum_delta=1))
    (repo / f"trailing_{token}.bin").write_bytes(_artifact(1900000002, b"trailing", trailing=b"X"))
    (repo / f"declared_{token}.bin").write_bytes(_artifact(1900000003, b"short", declared_size=99))
    truncated = _artifact(1900000004, b"truncate me")[:-2]
    (repo / f"truncated_{token}.bin").write_bytes(truncated)
    (repo / f"plain_{token}.txt").write_bytes(os.urandom(31))
    (repo / f"directory_{token}.bin").mkdir()

    expected_hex = {
        Path(name).stem + ".hex": payload.hex().upper().encode("ascii")
        for name, payload in payloads.items()
    }
    expected_manifest = [
        f"{name},{timestamps[name]},{len(payloads[name])}"
        for name in sorted(payloads)
    ]
    return expected_hex, expected_manifest


def _check_dynamic_result(expected_hex, expected_manifest):
    export = Path(EXPORT_DIR)
    manifest = Path(MANIFEST_FILE)
    if not export.is_dir() or not manifest.is_file():
        return False, "program did not create the export directory and manifest"

    actual_names = {p.name for p in export.iterdir()}
    if actual_names != set(expected_hex):
        return False, f"dynamic export names were {actual_names}, expected {set(expected_hex)}"

    for name, expected in expected_hex.items():
        path = export / name
        if not path.is_file() or path.read_bytes() != expected:
            return False, f"dynamic export {name} has incorrect contents"

    try:
        rows = manifest.read_text(encoding="utf-8").splitlines()
    except Exception as exc:
        return False, f"could not read dynamic manifest: {exc}"
    if rows != expected_manifest:
        return False, f"dynamic manifest was {rows}, expected {expected_manifest}"
    return True, ""


def test_z_c_source_compiles_and_processes_unseen_repository():
    sources = sorted(p for p in HOME.rglob("*.c") if p.is_file())
    assert sources, "No C source program was found under /home/user."

    build_dir = Path(tempfile.mkdtemp(prefix="artifact-build-"))
    candidates = []
    compile_groups = [[source] for source in sources]
    if len(sources) > 1:
        compile_groups.append(sources)

    for index, group in enumerate(compile_groups):
        executable = build_dir / f"candidate-{index}"
        result = subprocess.run(
            ["gcc", "-O2", *map(str, group), "-o", str(executable)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode == 0:
            candidates.append(executable)

    assert candidates, "The submitted C source could not be compiled with gcc."

    backup = Path(tempfile.mkdtemp(prefix="artifact-backup-"))
    repo = HOME / "repo"
    export = Path(EXPORT_DIR)
    manifest = Path(MANIFEST_FILE)
    shutil.copytree(repo, backup / "repo")
    if export.exists():
        shutil.copytree(export, backup / "export")
    if manifest.exists():
        shutil.copy2(manifest, backup / "manifest.csv")

    token = f"{random.SystemRandom().getrandbits(64):016x}"
    last_error = "no compiled candidate ran successfully"
    try:
        for executable in candidates:
            if repo.exists():
                shutil.rmtree(repo)
            if export.exists():
                shutil.rmtree(export)
            if manifest.exists():
                manifest.unlink()

            expected_hex, expected_manifest = _install_dynamic_repo(repo, token)
            try:
                run = subprocess.run(
                    [str(executable)], cwd=str(HOME),
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    timeout=10,
                )
            except subprocess.TimeoutExpired:
                last_error = f"{executable.name} timed out"
                continue
            if run.returncode != 0:
                last_error = f"{executable.name} exited with status {run.returncode}"
                continue

            passed, message = _check_dynamic_result(expected_hex, expected_manifest)
            if passed:
                return
            last_error = message

        pytest.fail("No compiled C program correctly processed the unseen repository: " + last_error)
    finally:
        if repo.exists():
            shutil.rmtree(repo)
        shutil.copytree(backup / "repo", repo)
        if export.exists():
            shutil.rmtree(export)
        if (backup / "export").exists():
            shutil.copytree(backup / "export", export)
        if manifest.exists():
            manifest.unlink()
        if (backup / "manifest.csv").exists():
            shutil.copy2(backup / "manifest.csv", manifest)
        shutil.rmtree(build_dir, ignore_errors=True)
        shutil.rmtree(backup, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
