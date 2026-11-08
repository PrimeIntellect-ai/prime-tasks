#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import struct
import subprocess
import tempfile

BASE_DIR = "/home/user/project_logs"
SUMMARY_PATH = "/home/user/error_summary.log"
SOURCE_PATH = "/home/user/log_parser.c"
BINARY_PATH = "/tmp/log_parser_verifier"


def rle_decompress(data):
    decompressed = bytearray()
    for i in range(0, len(data), 2):
        if i + 1 >= len(data):
            break
        count, char = struct.unpack('BB', data[i:i + 2])
        decompressed.extend(bytes([char]) * count)
    return decompressed.decode('utf-8')


def rle_compress(data):
    compressed = bytearray()
    i = 0
    while i < len(data):
        value = data[i]
        count = 1
        while i + count < len(data) and data[i + count] == value and count < 255:
            count += 1
        compressed.extend((count, value))
        i += count
    return bytes(compressed)


def compute_expected(base_dir):
    errors = []

    for root, _, files in os.walk(base_dir):
        for file in files:
            if file.endswith(".clog"):
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, base_dir)

                with open(full_path, "rb") as f:
                    data = f.read()

                text = rle_decompress(data)
                records = []
                current_record = []
                for line in text.splitlines(keepends=True):
                    if line.startswith('['):
                        if current_record:
                            records.append("".join(current_record))
                        current_record = [line]
                    else:
                        current_record.append(line)
                if current_record:
                    records.append("".join(current_record))

                for record in records:
                    if "] ERROR:" in record:
                        errors.append((rel_path, record))

    errors.sort(key=lambda item: item[0])

    expected_output = ""
    for rel_path, record in errors:
        expected_output += "---\n"
        expected_output += f"File: {rel_path}\n"
        expected_output += record
    return expected_output


def test_error_summary_log_exists_and_correct():
    assert os.path.exists(SUMMARY_PATH), f"File {SUMMARY_PATH} does not exist."
    assert os.path.isfile(SUMMARY_PATH), f"Path {SUMMARY_PATH} is not a file."

    expected_output = compute_expected(BASE_DIR)
    with open(SUMMARY_PATH, "r", encoding="utf-8") as f:
        actual_output = f.read()

    assert actual_output == expected_output, (
        f"Contents of {SUMMARY_PATH} do not match the expected output.\n"
        f"Expected:\n{expected_output}\n\nActual:\n{actual_output}"
    )


def test_c_program_compiles_and_generates_summary_for_fresh_recursive_input():
    assert os.path.exists(SOURCE_PATH), f"File {SOURCE_PATH} does not exist."
    source_stat = os.lstat(SOURCE_PATH)
    assert stat.S_ISREG(source_stat.st_mode), f"Path {SOURCE_PATH} is not a regular file."

    compile_result = subprocess.run(
        ["gcc", "-std=gnu11", "-O2", SOURCE_PATH, "-o", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "log_parser.c failed to compile:\n" + compile_result.stdout + compile_result.stderr
    )
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK)

    nonce = secrets.token_hex(16)
    fixtures = {
        "zeta/server.clog": (
            f"[2026-01-02 03:04:05] INFO: startup {nonce}\n"
            f"[2026-01-02 03:04:06] ERROR: zeta failure {nonce}\n"
            "first continuation line\n"
            "  detail: [bracket not at line start]\n"
            f"[2026-01-02 03:04:07] ERROR: second zeta error {nonce}\n"
            "tail line\n"
        ).encode(),
        "alpha/deep/nested/worker.clog": (
            f"[2025-12-31 23:59:57] ERROR: alpha failure {nonce}\n"
            + ("A" * 620)
            + "\nstack frame one\nstack frame two\n"
            f"[2025-12-31 23:59:58] WARN: recovered {nonce}\n"
        ).encode(),
        "alpha/no_errors.clog": (
            f"[2025-01-01 00:00:00] DEBUG: debug {nonce}\n"
            f"[2025-01-01 00:00:01] INFO: okay {nonce}\n"
        ).encode(),
    }

    parent = os.path.dirname(BASE_DIR)
    backup_dir = tempfile.mkdtemp(prefix="project_logs_backup_", dir=parent)
    os.rmdir(backup_dir)
    summary_backup = tempfile.mktemp(prefix="error_summary_backup_", dir=parent)
    had_summary = os.path.exists(SUMMARY_PATH)

    try:
        os.rename(BASE_DIR, backup_dir)
        if had_summary:
            os.rename(SUMMARY_PATH, summary_backup)

        os.makedirs(BASE_DIR)
        for relative_path, content in fixtures.items():
            full_path = os.path.join(BASE_DIR, relative_path)
            os.makedirs(os.path.dirname(full_path), exist_ok=True)
            with open(full_path, "wb") as f:
                f.write(rle_compress(content))

        # A similarly named file must not be parsed.
        with open(os.path.join(BASE_DIR, "alpha", "ignored.clog.bak"), "wb") as f:
            f.write(rle_compress(
                f"[2026-01-01 00:00:00] ERROR: ignored {nonce}\n".encode()
            ))

        expected_output = compute_expected(BASE_DIR)
        run_result = subprocess.run(
            [BINARY_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run_result.returncode == 0, (
            "Compiled log parser exited unsuccessfully:\n"
            + run_result.stdout + run_result.stderr
        )
        assert os.path.exists(SUMMARY_PATH), (
            "Compiled log parser did not create /home/user/error_summary.log"
        )
        assert os.path.isfile(SUMMARY_PATH)

        with open(SUMMARY_PATH, "r", encoding="utf-8") as f:
            actual_output = f.read()
        assert actual_output == expected_output, (
            "Compiled C program produced an incorrect summary for fresh recursive input.\n"
            f"Expected:\n{expected_output}\n\nActual:\n{actual_output}"
        )
    finally:
        if os.path.isdir(BASE_DIR):
            shutil.rmtree(BASE_DIR)
        if os.path.exists(SUMMARY_PATH):
            os.remove(SUMMARY_PATH)
        if os.path.exists(backup_dir):
            os.rename(backup_dir, BASE_DIR)
        if had_summary and os.path.exists(summary_backup):
            os.rename(summary_backup, SUMMARY_PATH)
        elif os.path.exists(summary_backup):
            os.remove(summary_backup)
        if os.path.exists(BINARY_PATH):
            os.remove(BINARY_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
