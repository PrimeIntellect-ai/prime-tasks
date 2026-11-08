#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile
import pytest

SOURCE_PATH = "/home/user/extractor.c"
EXECUTABLE_PATH = "/home/user/extractor"
OUTPUT_PATH = "/home/user/extracted_logs.bin"
EXPECTED_ORIGINAL = b"SYSTEM LOG DATA 10101010\nAUTH LOG DATA 20202020\nIMPORTANT NOTES\n"


def create_entry(filename, data):
    encoded = filename.encode("ascii")
    return b"BKUP" + struct.pack("<H", len(encoded)) + encoded + struct.pack("<I", len(data)) + data


def run_extractor(executable, archive, config):
    return subprocess.run(
        [executable, archive, config],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )


def test_extractor_c_exists_and_uses_mmap():
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} is missing."
    with open(SOURCE_PATH, "r") as f:
        content = f.read()
    assert "mmap" in content, f"The C source code in {SOURCE_PATH} does not appear to use 'mmap'."


def test_extractor_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable file {EXECUTABLE_PATH} is missing."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File {EXECUTABLE_PATH} is not executable."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE_PATH} is not a compiled ELF executable."


def test_extracted_logs_bin_content():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    with open(OUTPUT_PATH, "rb") as f:
        actual_content = f.read()
    assert actual_content == EXPECTED_ORIGINAL, (
        f"Content of {OUTPUT_PATH} does not match the expected extracted data. "
        f"Expected {len(EXPECTED_ORIGINAL)} bytes, got {len(actual_content)} bytes."
    )


def test_submitted_executable_on_original_inputs():
    result = run_extractor(EXECUTABLE_PATH, "/home/user/raw_data.bin", "/home/user/backup.conf")
    assert result.returncode == 0, f"Extractor failed on the supplied inputs: {result.stderr!r}"
    assert result.stdout == EXPECTED_ORIGINAL


@pytest.fixture(scope="session")
def rebuilt_executable(tmp_path_factory):
    output = tmp_path_factory.mktemp("build") / "extractor"
    result = subprocess.run(
        ["gcc", "-O2", SOURCE_PATH, "-o", str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, f"extractor.c does not compile: {result.stderr.decode(errors='replace')}"
    return str(output)


def exercise_dynamic_archive(executable):
    with tempfile.TemporaryDirectory() as td:
        archive = os.path.join(td, "random_archive.bin")
        config = os.path.join(td, "random.conf")
        suffix = "." + secrets.token_hex(3)
        selected_a = secrets.token_bytes(37) + b"\x00\xffA"
        selected_b = secrets.token_bytes(19) + b"\n"
        ignored = secrets.token_bytes(29)

        entries = [
            ("first" + suffix, selected_a),
            ("almost" + suffix + ".bak", ignored),
            ("other.dat", ignored[::-1]),
            ("second" + suffix, selected_b),
        ]
        with open(archive, "wb") as f:
            for name, data in entries:
                f.write(create_entry(name, data))
        with open(config, "w", encoding="ascii") as f:
            f.write(suffix + "\n")

        result = run_extractor(executable, archive, config)
        assert result.returncode == 0, f"Extractor failed on generated input: {result.stderr!r}"
        assert result.stdout == selected_a + selected_b, "Extractor did not parse/filter the generated archive correctly."


def exercise_bad_magic(executable):
    with tempfile.TemporaryDirectory() as td:
        archive = os.path.join(td, "corrupt.bin")
        config = os.path.join(td, "corrupt.conf")
        first = secrets.token_bytes(23)
        forbidden = secrets.token_bytes(31)
        with open(config, "w", encoding="ascii") as f:
            f.write(".log\n")
        with open(archive, "wb") as f:
            f.write(create_entry("before.log", first))
            f.write(b"NOPE")
            f.write(create_entry("after.log", forbidden))

        result = run_extractor(executable, archive, config)
        assert result.returncode >= 0, "Extractor crashed when it encountered an invalid magic number."
        assert result.stdout == first, "Extractor did not stop at the first invalid magic number."


def test_submitted_executable_parses_generated_inputs():
    exercise_dynamic_archive(EXECUTABLE_PATH)
    exercise_bad_magic(EXECUTABLE_PATH)


def test_source_build_parses_generated_inputs(rebuilt_executable):
    exercise_dynamic_archive(rebuilt_executable)
    exercise_bad_magic(rebuilt_executable)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
