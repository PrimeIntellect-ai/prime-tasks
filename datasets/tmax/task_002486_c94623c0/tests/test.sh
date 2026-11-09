#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tarfile
import tempfile
import time
import pytest

DATA_DIR = "/home/user/data"
EXPECTED_MEMBERS = ["file1.arc", "file2.arc"]
EXPECTED_HEADERS = {
    "file1.arc": bytes.fromhex("DE AD BE EF 00 00 00 01"),
    "file2.arc": bytes.fromhex("CA FE BA BE 00 00 00 02"),
}
EXPECTED_SIZES = {
    "file1.arc": 15360,
    "file2.arc": 12288,
}


def expected_blob(name):
    return EXPECTED_HEADERS[name] + b"\x00" * (EXPECTED_SIZES[name] - 8)


def expected_hex(data):
    return " ".join(f"{byte:02X}" for byte in data[:8]) + "\n"


def run_header(program, path):
    result = subprocess.run(
        [program, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=5, check=False
    )
    assert result.returncode == 0, (
        f"{program} failed for {path} with status {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def test_metadata_selection_and_input_fixtures():
    now = time.time()
    selected = []
    for name in os.listdir(DATA_DIR):
        path = os.path.join(DATA_DIR, name)
        if not os.path.isfile(path) or not name.endswith(".arc"):
            continue
        stat = os.stat(path)
        age = now - stat.st_mtime
        if stat.st_size > 10 * 1024 and 0 <= age <= 7 * 24 * 60 * 60:
            selected.append(name)

    assert sorted(selected) == EXPECTED_MEMBERS, (
        f"The files matching the required size, extension, and age criteria are incorrect: {sorted(selected)}"
    )

    for name in EXPECTED_MEMBERS:
        with open(os.path.join(DATA_DIR, name), "rb") as f:
            assert f.read() == expected_blob(name), f"Input fixture {name} was modified."


def test_get_header_c_exists():
    path = "/home/user/get_header.c"
    assert os.path.isfile(path), f"Source file {path} is missing. You must write the C program here."


def test_get_header_executable():
    path = "/home/user/get_header"
    assert os.path.isfile(path), f"Executable {path} is missing. Did you compile the C program?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled ELF executable."


def test_get_header_program_and_source_behavior():
    source = "/home/user/get_header.c"
    installed = "/home/user/get_header"

    with tempfile.TemporaryDirectory() as tmp:
        rebuilt = os.path.join(tmp, "get_header_rebuilt")
        compile_result = subprocess.run(
            ["gcc", source, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=False
        )
        assert compile_result.returncode == 0, (
            "get_header.c does not compile successfully:\n" +
            compile_result.stderr.decode(errors="replace")
        )

        samples = [
            bytes.fromhex("00 01 7F 80 A5 FE FF 10") + b"trailing data",
            os.urandom(32),
        ]
        for index, data in enumerate(samples):
            sample_path = os.path.join(tmp, f"sample_{index}_{os.urandom(6).hex()}.bin")
            with open(sample_path, "wb") as f:
                f.write(data)
            wanted = expected_hex(data).encode("ascii")
            assert run_header(installed, sample_path) == wanted, (
                "The installed get_header executable did not emit the exact uppercase 8-byte header."
            )
            assert run_header(rebuilt, sample_path) == wanted, (
                "The program built from get_header.c did not emit the exact uppercase 8-byte header."
            )

    for name in EXPECTED_MEMBERS:
        path = os.path.join(DATA_DIR, name)
        assert run_header(installed, path) == expected_hex(EXPECTED_HEADERS[name]).encode("ascii")


def test_manifest_content():
    path = "/home/user/manifest.txt"
    assert os.path.isfile(path), f"Manifest file {path} is missing."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "DE AD BE EF 00 00 00 01 /vault/archive/file1.arc",
        "CA FE BA BE 00 00 00 02 /vault/archive/file2.arc"
    ]

    assert lines == expected_lines, (
        f"Manifest content is incorrect.\n"
        f"Expected:\n{expected_lines}\n"
        f"Got:\n{lines}\n"
        "Ensure you matched the right files, formatted the hex headers properly, "
        "transformed the paths, and sorted alphabetically."
    )


def test_tar_content():
    path = "/home/user/inc_backup.tar"
    assert os.path.isfile(path), f"Tar archive {path} is missing."

    try:
        with tarfile.open(path, "r") as tar:
            members = sorted(tar.getnames())
            expected_members = ["file1.arc", "file2.arc"]
            assert members == expected_members, (
                f"Tar archive contents are incorrect.\n"
                f"Expected exactly these relative paths: {expected_members}\n"
                f"Got: {members}"
            )

            for name in expected_members:
                member = tar.getmember(name)
                assert member.isfile(), f"Tar member {name} is not a regular file."
                archived = tar.extractfile(member)
                assert archived is not None, f"Could not read tar member {name}."
                archived_data = archived.read()
                source_path = os.path.join(DATA_DIR, name)
                with open(source_path, "rb") as source:
                    source_data = source.read()
                assert archived_data == source_data, f"Tar member {name} does not match the source file."
                assert archived_data == expected_blob(name), f"Tar member {name} does not contain the original data."
    except tarfile.ReadError:
        pytest.fail(f"File {path} is not a valid tar archive.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
