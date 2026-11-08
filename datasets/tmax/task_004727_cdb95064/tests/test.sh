#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import shutil
import stat
import struct
import subprocess
import pytest

ARCHIVE_DIR = "/home/user/archives"
EXTRACTED_DIR = "/home/user/extracted"
LOG_PATH = "/home/user/extraction_log.txt"


def test_extracted_files_exist():
    expected_files = [
        "/home/user/extracted/test1.txt",
        "/home/user/extracted/test2.txt",
        "/home/user/extracted/test3.txt"
    ]
    for file_path in expected_files:
        assert os.path.exists(file_path), f"Extracted file {file_path} is missing."
        assert os.path.isfile(file_path), f"{file_path} is not a file."


def test_extracted_file_contents():
    with open("/home/user/extracted/test1.txt", "rb") as f:
        content = f.read()
    assert content == b"AAAAABBBBBCCCCCDDDDD", "test1.txt content is incorrect."

    expected_text2 = "Café au lait and piña coladas are müy bien! " * 5
    with open("/home/user/extracted/test2.txt", "rb") as f:
        content = f.read()
    assert content == expected_text2.encode("utf-8"), "test2.txt content or encoding is incorrect."

    expected_text3 = "ñ" * 100 + "A" * 50 + "é" * 100
    with open("/home/user/extracted/test3.txt", "rb") as f:
        content = f.read()
    assert content == expected_text3.encode("utf-8"), "test3.txt content or encoding is incorrect."


def test_extraction_log():
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} is missing."
    assert os.path.isfile(LOG_PATH), f"{LOG_PATH} is not a file."

    with open(LOG_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "test1.txt successfully extracted. Final UTF-8 size: 20 bytes",
        "test2.txt successfully extracted. Final UTF-8 size: 235 bytes",
        "test3.txt successfully extracted. Final UTF-8 size: 450 bytes"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in log file, but found {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Log file line {i+1} mismatch. Expected: '{expected}', Actual: '{actual}'"


def parse_archive(path):
    data = open(path, "rb").read()
    assert len(data) >= 14 and data[:4] == b"BKP1", f"Invalid test archive: {path}"
    name_len = data[4]
    pos = 5
    assert len(data) >= pos + name_len + 9
    name = data[pos:pos + name_len].decode("ascii")
    pos += name_len
    original_size, compressed_size = struct.unpack_from("<II", data, pos)
    pos += 8
    encoding_flag = data[pos]
    pos += 1
    payload = data[pos:pos + compressed_size]
    assert encoding_flag == 2 and len(payload) == compressed_size and len(payload) % 2 == 0
    raw = bytearray()
    for i in range(0, len(payload), 2):
        raw.extend([payload[i + 1]] * payload[i])
    assert len(raw) == original_size
    return name, bytes(raw).decode("iso-8859-1").encode("utf-8")


def test_compiled_extractor_processes_runtime_archive():
    source_files = []
    for path in glob.glob("/home/user/**/*.c", recursive=True):
        try:
            mode = os.stat(path).st_mode
        except OSError:
            continue
        if stat.S_ISREG(mode):
            source_files.append(path)
    source_files.sort()
    assert source_files, "No C source file for the extractor was found under /home/user."

    executable = "/tmp/submitted_extractor"
    compile_result = subprocess.run(
        ["/usr/bin/gcc", "-std=c11", "-O2", "-Wall", "-Wextra", *source_files, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, "The submitted C extractor could not be compiled with gcc:\n" + compile_result.stderr
    assert os.path.isfile(executable) and os.access(executable, os.X_OK)

    token = secrets.token_hex(6)
    output_name = f"probe_{token}.txt"
    archive_path = os.path.join(ARCHIVE_DIR, f"runtime_{token}.bkp")
    blocks = [
        (1, ord("Q")),
        (17, 0xE9),
        (3, ord("Z")),
        (255, 0xF1),
        (9, 0xA3),
        (2, ord("!")),
    ]
    raw = b"".join(bytes([value]) * count for count, value in blocks)
    compressed = b"".join(bytes([count, value]) for count, value in blocks)
    name_bytes = output_name.encode("ascii")
    with open(archive_path, "wb") as f:
        f.write(b"BKP1")
        f.write(bytes([len(name_bytes)]))
        f.write(name_bytes)
        f.write(struct.pack("<I", len(raw)))
        f.write(struct.pack("<I", len(compressed)))
        f.write(b"\x02")
        f.write(compressed)

    expected = {}
    for path in sorted(glob.glob(os.path.join(ARCHIVE_DIR, "*.bkp"))):
        filename, utf8_data = parse_archive(path)
        expected[filename] = utf8_data

    os.makedirs(EXTRACTED_DIR, exist_ok=True)
    for entry in os.listdir(EXTRACTED_DIR):
        path = os.path.join(EXTRACTED_DIR, entry)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    if os.path.lexists(LOG_PATH):
        if os.path.isdir(LOG_PATH) and not os.path.islink(LOG_PATH):
            shutil.rmtree(LOG_PATH)
        else:
            os.unlink(LOG_PATH)

    run_result = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert run_result.returncode == 0, "The compiled extractor failed when executed:\n" + run_result.stderr

    for filename, expected_content in expected.items():
        output_path = os.path.join(EXTRACTED_DIR, filename)
        assert os.path.isfile(output_path), f"Compiled extractor did not create {filename}."
        with open(output_path, "rb") as f:
            assert f.read() == expected_content, f"Compiled extractor produced incorrect content for {filename}."

    assert os.path.isfile(LOG_PATH), "Compiled extractor did not create the extraction log."
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    expected_lines = [
        f"{filename} successfully extracted. Final UTF-8 size: {len(expected[filename])} bytes"
        for filename in sorted(expected)
    ]
    assert actual_lines == expected_lines, "The extraction log from the compiled extractor is incorrect or not alphabetically sorted."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
