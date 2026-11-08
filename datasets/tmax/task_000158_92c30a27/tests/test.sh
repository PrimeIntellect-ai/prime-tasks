#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import struct
import subprocess


def parse_archive(path):
    with open(path, "rb") as f:
        data = f.read()

    assert len(data) >= 4, "File is too short to contain the header."
    assert data[:4] == b'BKP1', f"Invalid header in archive.bin. Expected b'BKP1', got {data[:4]}"

    offset = 4
    records = []
    while offset < len(data):
        assert offset + 11 <= len(data), "Truncated record found in archive.bin (not enough bytes for header)."

        ts = struct.unpack("<Q", data[offset:offset+8])[0]
        sev = struct.unpack("<B", data[offset+8:offset+9])[0]
        length = struct.unpack("<H", data[offset+9:offset+11])[0]
        offset += 11

        assert offset + length <= len(data), f"Truncated record found in archive.bin (message length {length} exceeds remaining bytes)."
        try:
            msg = data[offset:offset+length].decode("utf-8")
        except UnicodeDecodeError as exc:
            raise AssertionError("Message bytes could not be decoded as UTF-8.") from exc

        offset += length
        records.append((ts, sev, msg))

    return records


def test_archiver_source_and_behavior():
    source = "/home/user/archiver.c"
    archive = "/home/user/archive.bin"

    assert os.path.isfile(source), "The required C source file /home/user/archiver.c does not exist."
    assert os.path.isfile(archive), "The output file /home/user/archive.bin was not created."

    original_records = parse_archive(archive)
    expected_original = [
        (1700000000, 0, "Service started successfully."),
        (1700000005, 1, "High memory usage\ndetected on node A."),
        (1700000010, 2, "Database connection lost!\nRetrying...\nFailed.")
    ]

    assert len(original_records) == len(expected_original), f"Expected {len(expected_original)} records, but found {len(original_records)} in archive.bin."
    for i, (actual, expected) in enumerate(zip(original_records, expected_original)):
        assert actual[0] == expected[0], f"Record {i+1}: Expected timestamp {expected[0]}, got {actual[0]}."
        assert actual[1] == expected[1], f"Record {i+1}: Expected severity {expected[1]}, got {actual[1]}."
        assert actual[2] == expected[2], f"Record {i+1}: Expected message {expected[2]!r}, got {actual[2]!r}."

    executable = "/tmp/archiver_under_test"
    compile_result = subprocess.run(
        ["gcc", source, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"/home/user/archiver.c did not compile:\n{compile_result.stderr}"
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), "Compilation did not produce an executable."

    token = secrets.token_hex(8)
    base = 5_000_000_000 + secrets.randbelow(100_000_000)
    backup_dir = "/home/user/log_backups"
    shutil.rmtree(backup_dir)
    os.makedirs(os.path.join(backup_dir, "level1", "level2"))

    low_msg = f"Root critical {token}."
    equal_first_msg = f"First equal-time record {token}."
    equal_second_msg = f"Second equal-time record {token}."
    high_msg = f"Deep multiline {token}\ncontinued on another line."

    with open(os.path.join(backup_dir, "root.txt"), "w", encoding="utf-8") as f:
        f.write(f"ignored prefix\n---START---\nTime: {base}\nSeverity: CRIT\nMessage:   {low_msg}   \n---END---\n")

    with open(os.path.join(backup_dir, "level1", "level2", "nested.txt"), "w", encoding="utf-8") as f:
        f.write(
            f"---START---\nTime: {base + 40}\nSeverity: INFO\nMessage: {high_msg}   \n---END---\n"
            f"garbage between records\n"
            f"---START---\nTime: {base + 20}\nSeverity: WARN\nMessage: {equal_first_msg}\n---END---\n"
            f"---START---\nTime: {base + 20}\nSeverity: INFO\nMessage: {equal_second_msg}\n---END---\n"
        )

    with open(os.path.join(backup_dir, "level1", "decoy.log"), "w", encoding="utf-8") as f:
        f.write(f"---START---\nTime: {base - 1}\nSeverity: INFO\nMessage: must not be archived {token}\n---END---\n")

    os.remove(archive)
    run_result = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert run_result.returncode == 0, f"Compiled archiver exited with status {run_result.returncode}:\n{run_result.stderr}"
    assert os.path.isfile(archive), "Running the compiled archiver did not create /home/user/archive.bin."

    expected_dynamic = [
        (base, 2, low_msg),
        (base + 20, 1, equal_first_msg),
        (base + 20, 0, equal_second_msg),
        (base + 40, 0, high_msg),
    ]
    actual_dynamic = parse_archive(archive)
    assert actual_dynamic == expected_dynamic, f"Archive generated from dynamic recursive fixtures was incorrect. Expected {expected_dynamic!r}, got {actual_dynamic!r}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
