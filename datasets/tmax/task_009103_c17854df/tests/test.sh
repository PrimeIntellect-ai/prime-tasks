#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import secrets
import stat
import subprocess
import tempfile

APP_RLE = b"\x0aA\x0aB\x0aC"
DB_RLE = b"\x051\x052\x053\x054"
VALID_ORIGINAL_OUTPUTS = [APP_RLE + DB_RLE, DB_RLE + APP_RLE]


def rle(data):
    result = bytearray()
    if not data:
        return bytes(result)
    previous = data[0]
    count = 1
    for value in data[1:]:
        if value == previous and count < 255:
            count += 1
        else:
            result.extend((count, previous))
            previous = value
            count = 1
    result.extend((count, previous))
    return bytes(result)


def run_archiver(binary, source_dir, output_path):
    completed = subprocess.run(
        [binary, source_dir, output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=4,
        check=False,
    )
    assert completed.returncode == 0, (
        f"{binary} exited with {completed.returncode}. "
        f"stderr={completed.stderr!r}"
    )
    assert os.path.isfile(output_path), f"{binary} did not create its output archive."


def exercise_archiver(binary):
    # Each case has exactly one genuine regular input file, making the expected
    # archive independent of readdir ordering. Symlinks point to files,
    # directories, and the input root itself and must all be skipped.
    for nested in (False, True):
        with tempfile.TemporaryDirectory(prefix="archiver-check-") as work:
            root = os.path.join(work, "input-" + secrets.token_hex(6))
            outside = os.path.join(work, "outside-" + secrets.token_hex(6))
            os.mkdir(root)
            os.mkdir(outside)

            random_part = secrets.token_bytes(97)
            payload = b"Q" * 300 + random_part + b"\x00" * 260 + b"Z" * 19

            if nested:
                real_dir = os.path.join(root, "real-" + secrets.token_hex(4))
                os.mkdir(real_dir)
                data_path = os.path.join(real_dir, "settings.wal")
                os.symlink(real_dir, os.path.join(root, "linked-directory"))
            else:
                data_path = os.path.join(root, "settings.conf")

            with open(data_path, "wb") as handle:
                handle.write(payload)

            outside_file = os.path.join(outside, "must-not-be-archived.conf")
            with open(outside_file, "wb") as handle:
                handle.write(secrets.token_bytes(41))

            cycle_path = os.path.join(root, "cycle")
            file_link = os.path.join(root, "linked-file")
            outside_link = os.path.join(root, "outside-file")
            dangling_link = os.path.join(root, "dangling")
            os.symlink(root, cycle_path)
            os.symlink(data_path, file_link)
            os.symlink(outside_file, outside_link)
            os.symlink(os.path.join(work, "missing"), dangling_link)

            output_path = os.path.join(work, "result.rle")
            run_archiver(binary, root, output_path)

            with open(output_path, "rb") as handle:
                actual = handle.read()
            assert actual == rle(payload), (
                f"{binary} did not correctly archive only the regular file; "
                f"expected {rle(payload)!r}, got {actual!r}"
            )
            assert os.path.islink(cycle_path) and os.readlink(cycle_path) == root
            assert os.path.islink(file_link) and os.readlink(file_link) == data_path
            assert os.path.islink(outside_link) and os.readlink(outside_link) == outside_file
            assert os.path.islink(dangling_link)


def test_symlink_untouched():
    cycle_path = "/home/user/configs/cycle"
    assert os.path.islink(cycle_path), f"Symlink {cycle_path} was modified or deleted. It must remain a symlink."
    assert os.readlink(cycle_path) == "/home/user/configs", f"Symlink {cycle_path} target changed."


def test_c_code_modified():
    c_path = "/home/user/config_archiver.c"
    assert os.path.isfile(c_path), f"Source file {c_path} is missing."
    with open(c_path, "r") as f:
        content = f.read()
    assert "lstat" in content, "The C code does not appear to use lstat() as required to detect symlinks."


def test_archive_created_and_correct():
    archive_path = "/home/user/backup.rle"
    assert os.path.isfile(archive_path), f"Archive file {archive_path} was not created."

    with open(archive_path, "rb") as f:
        content = f.read()

    app_rle = b"\x0aA\x0aB\x0aC"
    db_rle = b"\x051\x052\x053\x054"

    valid_outputs = [
        app_rle + db_rle,
        db_rle + app_rle
    ]

    assert content in valid_outputs, (
        f"Archive content is incorrect. Expected one of the valid RLE combinations, but got: {content!r}"
    )


def test_compiled_artifact_and_required_run():
    binary = "/home/user/archiver"
    assert os.path.isfile(binary), f"Compiled program {binary} is missing."
    assert not os.path.islink(binary), f"{binary} must be a compiled program, not a symlink."
    mode = os.stat(binary).st_mode
    assert stat.S_ISREG(mode) and os.access(binary, os.X_OK), f"{binary} is not an executable regular file."
    with open(binary, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"{binary} is not an ELF executable produced by compilation."

    # Execute the exact invocation required by the instruction and verify that
    # it reproduces the expected archive without disturbing the cycle.
    run_archiver(binary, "/home/user/configs", "/home/user/backup.rle")
    with open("/home/user/backup.rle", "rb") as handle:
        assert handle.read() in VALID_ORIGINAL_OUTPUTS
    assert os.path.islink("/home/user/configs/cycle")
    assert os.readlink("/home/user/configs/cycle") == "/home/user/configs"

    exercise_archiver(binary)


def test_modified_source_compiles_and_handles_unseen_symlinks():
    with tempfile.TemporaryDirectory(prefix="source-build-") as build_dir:
        rebuilt = os.path.join(build_dir, "archiver-from-source")
        completed = subprocess.run(
            ["gcc", "/home/user/config_archiver.c", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
        assert completed.returncode == 0, (
            f"Modified source does not compile with gcc: {completed.stderr!r}"
        )
        exercise_archiver(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
