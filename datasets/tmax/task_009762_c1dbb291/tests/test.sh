#!/bin/bash
set -u
mkdir -p /logs/verifier

if (
    set -e

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_manifest_log_contents():
    manifest_path = "/home/user/release/manifest.log"
    assert os.path.isfile(manifest_path), f"File missing: {manifest_path}"

    with open(manifest_path, "r") as f:
        content = f.read().strip()

    expected = "58 10 213 26"
    assert content == expected, f"Incorrect manifest.log content. Expected '{expected}', got '{content}'"


def test_makefile_fixed():
    makefile_path = "/home/user/release/libemu/Makefile"
    assert os.path.isfile(makefile_path), f"File missing: {makefile_path}"

    with open(makefile_path, "r") as f:
        lines = f.readlines()

    for i, line in enumerate(lines):
        if "ar rcs" in line or "$(CC)" in line:
            assert line.startswith("\t"), f"Makefile line {i+1} does not start with a tab: {repr(line)}"


def test_libemu_compiled():
    libemu_path = "/home/user/release/libemu/libemu.a"
    assert os.path.isfile(libemu_path), f"Compiled library missing: {libemu_path}"


def test_main_go_fixed():
    main_go_path = "/home/user/release/go-emu/main.go"
    assert os.path.isfile(main_go_path), f"File missing: {main_go_path}"

    with open(main_go_path, "r") as f:
        content = f.read()

    lines = content.split('\n')
    found_transition = False
    in_ee_block = False

    for line in lines:
        if "b == 0xEE" in line:
            in_ee_block = True
        elif in_ee_block and "else" in line:
            in_ee_block = False

        if in_ee_block:
            stripped = line.strip()
            if stripped.startswith("state") and "STATE_ESCAPED" in stripped and not stripped.startswith("//"):
                found_transition = True
                break

    assert found_transition, "main.go does not correctly transition to STATE_ESCAPED when b == 0xEE"
    assert "C.process_byte" in content, "main.go does not process data through the C emulator library"
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short

    rm -f /home/user/release/libemu/emu.o /home/user/release/libemu/libemu.a
    make -C /home/user/release/libemu libemu.a

    test -s /home/user/release/libemu/emu.o
    file /home/user/release/libemu/emu.o | grep -q 'relocatable'
    test -s /home/user/release/libemu/libemu.a
    ar t /home/user/release/libemu/libemu.a | grep -qx 'emu.o'
    nm -g --defined-only /home/user/release/libemu/libemu.a | grep -Eq '[[:space:]]process_byte$'

    rm -f /tmp/go-emu-verifier
    cd /home/user/release/go-emu
    go build -o /tmp/go-emu-verifier main.go
    test -x /tmp/go-emu-verifier
    nm /tmp/go-emu-verifier | grep -Eq '[[:space:]]process_byte$'

    original_output="$(timeout 10 /tmp/go-emu-verifier)"
    manifest_output="$(cat /home/user/release/manifest.log)"
    test "$original_output" = "$manifest_output"
    test "$original_output" = "58 10 213 26"

    export TEST_BIN=/tmp/go-emu-verifier
    python3 << 'PY_EOF'
import os
import secrets
import subprocess

payload_path = "/home/user/release/payload.hex"
binary = os.environ["TEST_BIN"]
cwd = "/home/user/release/go-emu"


def expected(data):
    INIT, READING, ESCAPED = range(3)
    state = INIT
    output = []
    for b in data:
        if state == INIT:
            if b == 0xAA:
                state = READING
        elif state == READING:
            if b == 0xFF:
                state = INIT
            elif b == 0xEE:
                state = ESCAPED
            else:
                output.append(str(b ^ 0x2A))
        else:
            output.append(str(b ^ 0x2A))
            state = READING
    return " ".join(output) + "\n"


with open(payload_path, "rb") as f:
    original_payload = f.read()

try:
    cases = [
        [0xAA, 0xEE, 0xFF, 0x10, 0xFF],
        [0xAA, 0xEE, 0xAA, 0x20, 0xFF],
        [0xAA, 0xEE, 0xEE, 0x30, 0xFF],
    ]

    for escaped in (0xFF, 0xAA, 0xEE):
        normal1 = secrets.choice([b for b in range(256) if b not in (0xAA, 0xEE, 0xFF)])
        normal2 = secrets.choice([b for b in range(256) if b not in (0xAA, 0xEE, 0xFF)])
        tail = list(secrets.token_bytes(40))
        cases.append([0xAA, normal1, 0xEE, escaped, normal2, 0xFF] + tail)

    for data in cases:
        with open(payload_path, "w", encoding="ascii") as f:
            f.write(bytes(data).hex().upper() + "\n")
        result = subprocess.run(
            [binary], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=10
        )
        assert result.returncode == 0, result.stderr
        want = expected(data)
        assert result.stdout == want, (
            f"incorrect output for payload {bytes(data).hex().upper()}: "
            f"expected {want!r}, got {result.stdout!r}"
        )
finally:
    with open(payload_path, "wb") as f:
        f.write(original_payload)
PY_EOF
) 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
