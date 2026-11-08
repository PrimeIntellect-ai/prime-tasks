#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import gzip
import hashlib
import pathlib
import shutil
import subprocess
import tempfile
import uuid
import pytest


def test_archiver_cpp_exists():
    assert os.path.isfile("/home/user/archiver.cpp"), "The C++ source file /home/user/archiver.cpp is missing."


def test_archiver_binary_exists():
    assert os.path.isfile("/home/user/archiver"), "The compiled binary /home/user/archiver is missing."
    assert os.access("/home/user/archiver", os.X_OK), "The file /home/user/archiver is not executable."
    with open("/home/user/archiver", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/archiver is not a compiled executable."


def test_curated_archive_content():
    archive_path = "/home/user/curated_archive.gz"
    assert os.path.isfile(archive_path), f"The archive {archive_path} is missing."

    expected_content = b"chunk_A_data_chunk_B_data_chunk_D_datachunk_C_data_"

    try:
        with gzip.open(archive_path, "rb") as f:
            actual_content = f.read()
    except Exception as e:
        pytest.fail(f"Failed to read {archive_path} as a gzip file: {e}")

    assert actual_content == expected_content, "The uncompressed content of the archive does not match the expected combined binary stream."


def test_checksum_txt_content():
    checksum_path = "/home/user/checksum.txt"
    assert os.path.isfile(checksum_path), f"The checksum file {checksum_path} is missing."

    expected_hash = "4e0f269a941da7e3f890c29b9ef96e1a4de110c497330a8459ce798939c1b721"

    with open(checksum_path, "r") as f:
        actual_hash = f.read().strip()

    assert actual_hash == expected_hash, f"The checksum in {checksum_path} is incorrect. Expected {expected_hash}, got {actual_hash}."


def expected_stream(repo):
    paths = sorted(
        str(p) for p in pathlib.Path(repo).rglob("*")
        if p.is_file() and p.name.endswith(".dat") and p.name != "active.dat"
    )
    return b"".join(pathlib.Path(p).read_bytes() for p in paths)


def run_and_check(executable, expected):
    try:
        result = subprocess.run(
            [executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=10, check=False
        )
    except Exception as e:
        pytest.fail(f"Failed to execute {executable}: {e}")
    assert result.returncode == 0, f"{executable} exited with status {result.returncode}: {result.stderr.decode(errors='replace')}"
    assert result.stdout == expected, f"{executable} did not recursively concatenate the sorted eligible .dat files correctly."


def test_source_and_binary_on_dynamic_repository():
    source = "/home/user/archiver.cpp"
    repo = "/home/user/repo"
    token = uuid.uuid4().hex
    backup = f"/home/user/repo.verifier_backup.{token}"

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "archiver_from_source")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", source, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False
        )
        assert compile_result.returncode == 0, "archiver.cpp does not compile as C++17: " + compile_result.stderr.decode(errors="replace")

        os.rename(repo, backup)
        try:
            os.makedirs(os.path.join(repo, "zeta", "deep"))
            os.makedirs(os.path.join(repo, "alpha", "nested"))
            os.makedirs(os.path.join(repo, "middle"))

            files = {
                os.path.join(repo, "zeta", f"{token}_last.dat"): b"Z" + os.urandom(19) + b"\x00",
                os.path.join(repo, "zeta", "deep", "first.dat"): b"D" + os.urandom(23),
                os.path.join(repo, "alpha", "nested", "item.dat"): b"A\x00\xff" + os.urandom(17),
                os.path.join(repo, "middle", "sample.dat"): b"M" + os.urandom(29),
                os.path.join(repo, "active.dat"): b"THIS_MUST_NOT_APPEAR" + os.urandom(13),
                os.path.join(repo, "alpha", "ignored.txt"): b"NON_DAT_CONTENT" + os.urandom(11),
                os.path.join(repo, "middle", "almost.dat.tmp"): b"WRONG_EXTENSION" + os.urandom(7),
            }
            for path, data in files.items():
                with open(path, "wb") as f:
                    f.write(data)

            expected = expected_stream(repo)
            run_and_check("/home/user/archiver", expected)
            run_and_check(rebuilt, expected)
        finally:
            if os.path.lexists(repo):
                if os.path.isdir(repo) and not os.path.islink(repo):
                    shutil.rmtree(repo)
                else:
                    os.unlink(repo)
            os.rename(backup, repo)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
