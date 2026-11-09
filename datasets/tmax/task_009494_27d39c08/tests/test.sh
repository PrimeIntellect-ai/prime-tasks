#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile

PROJECT = "/home/user/firmware_decoder"
BINARY = os.path.join(PROJECT, "target/debug/firmware_decoder")
LIBRARY = "/home/user/legacy/libfirmware.so"
OUTPUT = "/home/user/decoded_message.txt"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, timeout=120, **kwargs)


def execute_decoder():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user/legacy" + (
        ":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else ""
    )
    run([BINARY], cwd=PROJECT, env=env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True)
    assert os.path.isfile(OUTPUT), f"The output file {OUTPUT} does not exist."
    with open(OUTPUT, "r", encoding="utf-8") as f:
        return f.read().strip()


def make_bytecode(message):
    code = []
    acc = 0
    for i, value in enumerate(message.encode("utf-8")):
        mode = i % 3
        if mode == 0:
            code.extend((0x10, value))
        elif mode == 1:
            code.extend((0x11, (value - acc) & 0xFF))
        else:
            code.extend((0x12, acc ^ value))
        acc = value
        code.append(0x20)
    code.append(0xFF)
    return code


def build_challenge_library(path, marker, message):
    bytecode = make_bytecode(message)
    blob = [0x01, 0x05, 0x00, 0x91, 0x82, 0x73, 0x64, 0x55]
    blob += [0x02, len(bytecode) & 0xFF, (len(bytecode) >> 8) & 0xFF]
    blob += bytecode
    blob += [0x03, 0x03, 0x00, 0xA1, 0xB2, 0xC3]
    initializer = ", ".join(f"0x{x:02x}" for x in blob)
    source = f'''
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
extern void host_log_msg(const char *msg);
static const uint8_t firmware_data[] = {{ {initializer} }};
size_t get_firmware_blob(unsigned char *out_buffer, size_t max_len) {{
    host_log_msg("challenge firmware retrieval");
    FILE *f = fopen("{marker}", "wb");
    if (f) {{ fputs("called", f); fclose(f); }}
    if (max_len < sizeof(firmware_data)) return 0;
    for (size_t i = 0; i < sizeof(firmware_data); ++i)
        out_buffer[i] = firmware_data[i];
    return sizeof(firmware_data);
}}
'''
    source_path = path + ".c"
    with open(source_path, "w", encoding="utf-8") as f:
        f.write(source)
    try:
        run(["/usr/bin/gcc", "-shared", "-fPIC", "-o", path, source_path],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    finally:
        if os.path.exists(source_path):
            os.remove(source_path)


def test_complete_rust_implementation():
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml"))
    assert os.path.isfile(os.path.join(PROJECT, "src/main.rs"))
    assert os.path.isfile(LIBRARY)

    run(["/usr/bin/cargo", "clean"], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    run(["/usr/bin/cargo", "build"], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), \
        "cargo build did not produce the firmware_decoder executable"

    dynamic = run(["/usr/bin/readelf", "-d", BINARY],
                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                  text=True).stdout
    assert re.search(r"Shared library: \[libfirmware\.so\]", dynamic), \
        "The executable is not dynamically linked to libfirmware.so"

    symbols = run(["/usr/bin/nm", "-D", "--defined-only", BINARY],
                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                  text=True).stdout
    assert re.search(r"\bhost_log_msg$", symbols, re.MULTILINE), \
        "The executable does not export the required host_log_msg callback"

    # Preserve the original output assertion and obtain it by running the artifact.
    assert execute_decoder() == "Hello World!", \
        "The decoder produced the wrong result for the supplied firmware library"

    # Replace the library temporarily with an unpredictable compatible firmware
    # image. This requires the built program to retrieve, parse, and execute the
    # library data rather than merely writing the known fixed answer.
    token = secrets.token_hex(12)
    expected = "FW-" + token
    marker = "/tmp/firmware_called_" + secrets.token_hex(12)

    with tempfile.TemporaryDirectory(prefix="verifier_firmware_") as tempdir:
        backup = os.path.join(tempdir, "libfirmware.original.so")
        challenge = os.path.join(tempdir, "libfirmware.challenge.so")
        shutil.copy2(LIBRARY, backup)
        build_challenge_library(challenge, marker, expected)
        try:
            shutil.copy2(challenge, LIBRARY)
            actual = execute_decoder()
            assert os.path.isfile(marker), \
                "get_firmware_blob was not called through the C library"
            assert actual == expected, (
                "The decoder failed on a verifier-generated TLV/VM payload.\n"
                f"Expected: {expected!r}\nActual:   {actual!r}"
            )
        finally:
            shutil.copy2(backup, LIBRARY)
            if os.path.exists(marker):
                os.remove(marker)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
