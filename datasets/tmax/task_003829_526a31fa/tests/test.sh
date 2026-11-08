#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess


def test_symlink_removed():
    symlink_path = '/home/user/data/subdir/loop'
    assert not os.path.exists(symlink_path) and not os.path.islink(symlink_path), (
        f"The recursive symlink {symlink_path} still exists. It should be removed."
    )

    # Also verify there are no other symlinks pointing to an ancestor in /home/user/data
    for root, dirs, files in os.walk('/home/user/data'):
        for d in dirs:
            p = os.path.join(root, d)
            if os.path.islink(p):
                target = os.path.realpath(p)
                assert not os.path.realpath(root).startswith(target), (
                    f"Found another recursive symlink at {p} pointing to {target}"
                )


def test_rust_program_exists():
    rust_file = '/home/user/parse_backup.rs'
    assert os.path.isfile(rust_file), f"The Rust program {rust_file} is missing."


def test_report_content():
    report_file = '/home/user/report.txt'
    assert os.path.isfile(report_file), f"The report file {report_file} is missing."

    with open(report_file, 'r') as f:
        content = f.read().strip()

    expected_path = '/home/user/data/subdir/loop'
    assert content == expected_path, (
        f"The content of {report_file} is incorrect. "
        f"Expected '{expected_path}', got '{content}'."
    )


def _expected_output_variants(path_bytes):
    return (path_bytes, path_bytes + b'\n')


def test_rust_program_compiles_and_parses_header():
    rust_file = '/home/user/parse_backup.rs'
    archive_file = '/home/user/backups/latest.bak'
    report_file = '/home/user/report.txt'
    binary_file = '/tmp/parse_backup_submission'

    compile_result = subprocess.run(
        ['rustc', rust_file, '-o', binary_file],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "The Rust program did not compile:\n" +
        compile_result.stderr.decode('utf-8', errors='replace')
    )
    assert os.path.isfile(binary_file) and os.access(binary_file, os.X_OK), (
        "Compiling parse_backup.rs did not produce an executable."
    )

    with open(archive_file, 'rb') as f:
        original_archive = f.read()

    assert len(original_archive) >= 8, "The backup archive header is truncated."
    original_length = int.from_bytes(original_archive[4:8], 'little')
    original_path = original_archive[8:8 + original_length]
    assert len(original_path) == original_length, "The backup archive path is truncated."

    original_run = subprocess.run(
        [binary_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert original_run.returncode == 0, (
        "The compiled Rust program failed on the supplied backup archive."
    )
    assert original_run.stdout in _expected_output_variants(original_path), (
        f"The compiled program printed {original_run.stdout!r}; expected only {original_path!r}."
    )

    with open(report_file, 'rb') as f:
        report_bytes = f.read()
    assert report_bytes == original_run.stdout, (
        "report.txt is not exactly the output produced by the compiled Rust program."
    )

    try:
        # Randomized paths ensure the program actually reads the little-endian length
        # and path bytes rather than printing the known path from the original archive.
        for suffix_size in (8, 19):
            path = (
                '/verification/' + secrets.token_hex(suffix_size) +
                '/item-' + secrets.token_hex(5)
            ).encode('ascii')
            test_archive = (
                b'BAK1' + struct.pack('<I', len(path)) + path +
                secrets.token_bytes(37)
            )
            with open(archive_file, 'wb') as f:
                f.write(test_archive)

            run = subprocess.run(
                [binary_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
            )
            assert run.returncode == 0, (
                "The compiled Rust program failed on a valid backup header."
            )
            assert run.stdout in _expected_output_variants(path), (
                f"The compiled program printed {run.stdout!r}; expected only {path!r}."
            )
    finally:
        with open(archive_file, 'wb') as f:
            f.write(original_archive)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
