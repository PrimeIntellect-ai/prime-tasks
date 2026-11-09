#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tarfile
import tempfile

SOURCE_ARCHIVE = "/home/user/configs.tar.gz"
CONFIGS_DIR = "/home/user/configs"
SOURCE_FILE = "/home/user/process_configs.c"
EXECUTABLE = "/home/user/process_configs"
UPDATED_ARCHIVE = "/home/user/updated_configs.tar.gz"

EXPECTED_FILES = {
    "plugin_alpha.elf",
    "plugin_beta.elf",
    "db_tx_1.wal",
    "db_tx_2.wal",
}


def classified_original_files():
    result = {}
    with tarfile.open(SOURCE_ARCHIVE, "r:gz") as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            extracted = tar.extractfile(member)
            assert extracted is not None
            data = extracted.read()
            name = member.name
            if data.startswith(b"\x7fELF"):
                result[name + ".elf"] = data
            elif data.startswith((b"\x37\x7f\x06\x82", b"\x37\x7f\x06\x83")):
                result[name + ".wal"] = data
    return result


def assert_dynamic_processing(program):
    token = secrets.token_hex(10)
    inputs = {
        f"elf_{token}": b"\x7fELF" + os.urandom(19),
        f"wal82_{token}": b"\x37\x7f\x06\x82" + os.urandom(17),
        f"wal83_{token}": b"\x37\x7f\x06\x83" + os.urandom(21),
        f"junk_{token}": b"\x00\x11\x22\x33" + os.urandom(13),
        f"short_{token}": b"\x7fEL",
    }
    expected = {
        f"elf_{token}.elf": inputs[f"elf_{token}"],
        f"wal82_{token}.wal": inputs[f"wal82_{token}"],
        f"wal83_{token}.wal": inputs[f"wal83_{token}"],
    }

    backup = tempfile.mkdtemp(prefix="configs-backup-")
    os.rmdir(backup)
    os.rename(CONFIGS_DIR, backup)
    try:
        os.mkdir(CONFIGS_DIR)
        for name, data in inputs.items():
            with open(os.path.join(CONFIGS_DIR, name), "wb") as f:
                f.write(data)

        completed = subprocess.run(
            [program], cwd="/home/user", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10
        )
        assert completed.returncode == 0, (
            f"{program} failed when processing dynamically named files: "
            f"{completed.stderr.decode(errors='replace')}"
        )
        assert os.path.isdir(CONFIGS_DIR), "Program removed the configs directory"
        assert set(os.listdir(CONFIGS_DIR)) == set(expected), (
            "Program did not correctly rename and delete dynamically named inputs"
        )
        for name, data in expected.items():
            path = os.path.join(CONFIGS_DIR, name)
            assert os.path.isfile(path), f"Expected regular file missing: {name}"
            with open(path, "rb") as f:
                assert f.read() == data, f"Program changed the bytes of {name}"
    finally:
        if os.path.lexists(CONFIGS_DIR):
            if os.path.isdir(CONFIGS_DIR) and not os.path.islink(CONFIGS_DIR):
                shutil.rmtree(CONFIGS_DIR)
            else:
                os.unlink(CONFIGS_DIR)
        os.rename(backup, CONFIGS_DIR)


def test_c_program_exists_and_contains_functions():
    assert os.path.exists(SOURCE_FILE), f"C program source file not found at {SOURCE_FILE}"
    assert os.path.isfile(SOURCE_FILE), f"{SOURCE_FILE} is not a file"

    with open(SOURCE_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    for func in ["fread", "rename", "remove"]:
        assert func in content, f"C program must use the '{func}' function."
    assert "fopen" in content, "C program must directly open files with fopen."

    assert os.path.isfile(EXECUTABLE), f"Compiled executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable"


def test_updated_configs_archive_contents():
    assert os.path.exists(UPDATED_ARCHIVE), f"Final archive not found at {UPDATED_ARCHIVE}"
    assert os.path.isfile(UPDATED_ARCHIVE), f"{UPDATED_ARCHIVE} is not a file"
    assert tarfile.is_tarfile(UPDATED_ARCHIVE), f"{UPDATED_ARCHIVE} is not a valid tar archive"

    expected_data = classified_original_files()
    assert set(expected_data) == EXPECTED_FILES

    with tarfile.open(UPDATED_ARCHIVE, "r:gz") as tar:
        members = tar.getmembers()
        names = tar.getnames()

        for name in names:
            assert "/" not in name, f"File '{name}' should be at the root of the archive, not in a directory."

        actual_files = set(names)
        missing = EXPECTED_FILES - actual_files
        extra = actual_files - EXPECTED_FILES
        assert not missing, f"Missing expected files in archive: {missing}"
        assert not extra, f"Unexpected files found in archive: {extra}"
        assert len(names) == len(EXPECTED_FILES), "Archive contains duplicate members"

        for member in members:
            assert member.isfile(), f"Archive member '{member.name}' is not a regular file"
            extracted = tar.extractfile(member)
            assert extracted is not None
            assert extracted.read() == expected_data[member.name], (
                f"Archive member '{member.name}' does not match the original blob bytes"
            )


def test_configs_directory_state():
    assert os.path.isdir(CONFIGS_DIR), f"Configs directory not found at {CONFIGS_DIR}"
    files = os.listdir(CONFIGS_DIR)
    assert "unknown_blob" not in files, "The file 'unknown_blob' was not deleted from the configs directory."

    expected_data = classified_original_files()
    assert set(files) == set(expected_data), "Configs directory does not contain exactly the renamed files"
    for name, data in expected_data.items():
        path = os.path.join(CONFIGS_DIR, name)
        assert os.path.isfile(path), f"Expected regular file missing: {path}"
        with open(path, "rb") as f:
            assert f.read() == data, f"File '{name}' no longer matches its original blob bytes"


def test_compiled_program_and_source_process_unseen_inputs():
    assert_dynamic_processing(EXECUTABLE)

    with tempfile.TemporaryDirectory(prefix="build-process-configs-") as build_dir:
        rebuilt = os.path.join(build_dir, "process_configs")
        compiled = subprocess.run(
            ["gcc", SOURCE_FILE, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert compiled.returncode == 0, (
            "process_configs.c does not compile: " + compiled.stderr.decode(errors="replace")
        )

        symbols = subprocess.run(
            ["nm", "-D", rebuilt], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=10
        )
        assert symbols.returncode == 0, f"Could not inspect rebuilt executable: {symbols.stderr}"
        for func in ["fopen", "fread", "rename", "remove"]:
            assert re.search(r"\bU\s+" + re.escape(func) + r"(?:@|\s*$)", symbols.stdout, re.MULTILINE), (
                f"Rebuilt C program does not directly reference {func}"
            )

        assert_dynamic_processing(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
