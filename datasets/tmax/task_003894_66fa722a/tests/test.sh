#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import struct
import subprocess

PARSER_C = "/home/user/parser.c"
INPUT = "/home/user/project_data.bin"
OUTPUT = "/home/user/extracted_text.txt"
EXECUTABLE = "/tmp/submitted_parser"
PRELOAD_C = "/tmp/mmap_monitor.c"
PRELOAD_SO = "/tmp/mmap_monitor.so"
MARKER = "/tmp/parser_used_mmap"


def test_parser_c_exists():
    path = PARSER_C
    assert os.path.exists(path), f"File {path} does not exist. You must write your C code to this file."
    assert os.path.isfile(path), f"Path {path} is not a valid file."


def test_extracted_text_exists():
    path = OUTPUT
    assert os.path.exists(path), f"File {path} does not exist. Your C program must create this file."
    assert os.path.isfile(path), f"Path {path} is not a valid file."


def test_extracted_text_content():
    path = OUTPUT
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    expected_content = "Project_Start\nModule_Active\nConfig_Loaded\n"

    assert content == expected_content, (
        f"The content of {path} does not match the expected output.\n"
        f"Expected:\n{repr(expected_content)}\n"
        f"Got:\n{repr(content)}"
    )


def t_record(payload):
    return b"T" + struct.pack("<I", len(payload)) + payload


def l_record(offset):
    return b"L" + struct.pack("<I", offset)


def put(buf, offset, record):
    end = offset + len(record)
    if len(buf) < end:
        buf.extend(b"\x00" * (end - len(buf)))
    buf[offset:end] = record


def reference_parse(data):
    output = bytearray()
    visited = set()
    offset = 0

    while offset < len(data):
        if offset in visited:
            break
        visited.add(offset)

        if offset + 5 > len(data):
            break
        record_type = data[offset:offset + 1]
        value = struct.unpack_from("<I", data, offset + 1)[0]

        if record_type == b"T":
            payload_start = offset + 5
            payload_end = payload_start + value
            if payload_end > len(data):
                break
            output.extend(data[payload_start:payload_end])
            offset = payload_end
        elif record_type == b"L":
            offset = value
        else:
            break

    return bytes(output)


def build_monitor():
    source = r'''#define _GNU_SOURCE
#include <sys/mman.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

static void note_mapping(int fd) {
    const char *input = getenv("MMAP_INPUT_PATH");
    const char *marker = getenv("MMAP_MARKER_PATH");
    struct stat a, b;
    if (!input || !marker || fd < 0) return;
    if (fstat(fd, &a) != 0 || stat(input, &b) != 0) return;
    if (a.st_dev != b.st_dev || a.st_ino != b.st_ino) return;
    int out = open(marker, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (out >= 0) {
        (void)write(out, "1", 1);
        close(out);
    }
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
    if (!real_mmap)
        real_mmap = dlsym(RTLD_NEXT, "mmap");
    void *result = real_mmap(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED)
        note_mapping(fd);
    return result;
}
'''
    with open(PRELOAD_C, "w", encoding="utf-8") as f:
        f.write(source)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", PRELOAD_C, "-o", PRELOAD_SO, "-ldl"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def compile_parser():
    with open(PARSER_C, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r"\bmmap\s*\(", source), "parser.c does not contain a call to mmap()."

    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", PARSER_C, "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"parser.c failed to compile:\n{result.stderr}"


def run_case(data, label):
    expected = reference_parse(data)
    with open(INPUT, "wb") as f:
        f.write(data)

    for path in (OUTPUT, MARKER):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["LD_PRELOAD"] = PRELOAD_SO
    env["MMAP_INPUT_PATH"] = INPUT
    env["MMAP_MARKER_PATH"] = MARKER

    try:
        result = subprocess.run(
            [EXECUTABLE],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"Parser did not terminate for case {label}; cycle detection is missing") from exc

    assert result.returncode == 0, (
        f"Parser exited with status {result.returncode} for case {label}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(OUTPUT), f"Parser did not create {OUTPUT} for case {label}"
    with open(OUTPUT, "rb") as f:
        actual = f.read()
    assert actual == expected, (
        f"Incorrect extracted bytes for case {label}. "
        f"Expected {expected!r}, got {actual!r}"
    )
    assert os.path.isfile(MARKER) and os.path.getsize(MARKER) > 0, (
        f"Parser did not mmap the input file for case {label}"
    )


def make_cases():
    a = ("Sequential_" + secrets.token_hex(6)).encode()
    b = ("_Tail_" + secrets.token_hex(5)).encode()
    yield "sequential records", t_record(a) + t_record(b)

    p1 = ("A" + secrets.token_hex(3)).encode()
    p2 = ("B" + secrets.token_hex(3)).encode()
    p3 = ("C" + secrets.token_hex(3)).encode()
    linked = bytearray()
    put(linked, 0, l_record(64))
    put(linked, 64, t_record(p1))
    put(linked, 69 + len(p1), l_record(128))
    put(linked, 128, t_record(p2))
    put(linked, 133 + len(p2), l_record(192))
    put(linked, 192, t_record(p3))
    put(linked, 197 + len(p3), l_record(64))
    yield "linked records with cycle", bytes(linked)

    payload = ("Again" + secrets.token_hex(2)).encode()
    sequential_cycle = bytearray()
    put(sequential_cycle, 0, l_record(40))
    put(sequential_cycle, 40, l_record(20))
    put(sequential_cycle, 20, t_record(payload))
    put(sequential_cycle, 25 + len(payload), l_record(20))
    yield "cycle reached after text", bytes(sequential_cycle)

    prefix = ("BeforeBeyond_" + secrets.token_hex(4)).encode()
    yield "link beyond EOF", t_record(prefix) + l_record(0x7fffffff)
    yield "self link", l_record(0)


def main():
    test_parser_c_exists()
    test_extracted_text_exists()
    test_extracted_text_content()

    with open(INPUT, "rb") as f:
        original_input = f.read()
    with open(OUTPUT, "rb") as f:
        original_output = f.read()

    succeeded = False
    try:
        compile_parser()
        build_monitor()

        run_case(original_input, "original project_data.bin")
        expected_original = b"Project_Start\nModule_Active\nConfig_Loaded\n"
        with open(OUTPUT, "rb") as f:
            assert f.read() == expected_original

        for label, data in make_cases():
            run_case(data, label)

        run_case(original_input, "final original project_data.bin")
        succeeded = True
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
        if not succeeded:
            with open(OUTPUT, "wb") as f:
                f.write(original_output)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
