#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import string
import struct
import subprocess
import zlib
import pytest

ORACLE = "/app/bin/legacy_parser"
AGENT = "/home/user/new_parser"
SOURCE = "/home/user/new_parser.c"
BUILD = "/tmp/verified_new_parser"
JAIL = "/tmp/parser_jail"
SCHEMA_FILE = "/tmp/fuzz_schema.conf"
ARF_FILE = "/tmp/fuzz_input.arf"


def generate_schema():
    with open(SCHEMA_FILE, "w") as f:
        for i in range(256):
            if random.random() < 0.3:
                name = "".join(random.choices(string.ascii_uppercase + "_", k=random.randint(3, 15)))
                f.write(f"{i:02X}:{name}\n")
            elif random.random() < 0.05:
                f.write("INVALID_LINE_FORMAT\n")


def generate_arf():
    magic = b"ARF1"
    if random.random() < 0.1:
        magic = b"BADM"

    tlv_data = b""
    if random.random() < 0.8:
        for _ in range(random.randint(1, 20)):
            t = random.randint(0, 255)
            length = random.randint(0, 50)
            val = os.urandom(length)
            tlv_data += struct.pack("<BH", t, length)
            if random.random() < 0.05:
                tlv_data += val[:length // 2]
                break
            else:
                tlv_data += val

    uncompressed_size = len(tlv_data)
    if random.random() < 0.1:
        uncompressed_size += random.choice([-1, 1, 5])

    compressed = zlib.compress(tlv_data)
    if random.random() < 0.1:
        compressed = compressed[:-5] + b"JUNK"

    with open(ARF_FILE, "wb") as f:
        f.write(magic)
        f.write(struct.pack("<I", uncompressed_size & 0xFFFFFFFF))
        f.write(compressed)
        if random.random() < 0.05:
            f.truncate(random.randint(0, max(0, f.tell() - 2)))


def enter_jail():
    os.chroot(JAIL)
    os.chdir("/")
    os.setgroups([])
    os.setgid(65534)
    os.setuid(65534)


def run_isolated(args):
    try:
        return subprocess.run(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
            preexec_fn=enter_jail,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Verifier-built parser timed out in the isolated environment")


def write_case(schema, arf):
    with open(os.path.join(JAIL, "schema.conf"), "wb") as f:
        f.write(schema)
    with open(os.path.join(JAIL, "input.arf"), "wb") as f:
        f.write(arf)
    os.chmod(os.path.join(JAIL, "schema.conf"), 0o644)
    os.chmod(os.path.join(JAIL, "input.arf"), 0o644)


def encode_valid(tlvs, declared_delta=0):
    payload = b"".join(struct.pack("<BH", t, len(value)) + value for t, value in tlvs)
    return b"ARF1" + struct.pack("<I", len(payload) + declared_delta) + zlib.compress(payload)


def expected_valid(schema_names, tlvs):
    output = bytearray()
    for t, value in tlvs:
        name = schema_names.get(t)
        if name is None:
            label = f"UNKNOWN_{t:02X}"
        else:
            label = name
        output.extend(f"[{label}] {value.hex().upper()}\n".encode())
    return bytes(output)


def assert_isolated_case(schema, arf, expected_code, expected_stdout):
    write_case(schema, arf)
    proc = run_isolated(["/new_parser", "/schema.conf", "/input.arf"])
    assert proc.returncode == expected_code, (
        f"Verifier-built source returned {proc.returncode}, expected {expected_code}; "
        f"stderr={proc.stderr!r}, input={arf.hex()}"
    )
    assert proc.stdout == expected_stdout, (
        f"Verifier-built source output {proc.stdout!r}, expected {expected_stdout!r}; "
        f"input={arf.hex()}"
    )


def test_source_exists_compiles_and_runs_without_legacy_artifacts():
    assert os.path.isfile(SOURCE), f"Required C source missing at {SOURCE}"
    assert not os.path.islink(SOURCE), "new_parser.c must be a real source file, not a symlink"
    assert os.path.isfile(AGENT), f"Agent binary missing at {AGENT}"
    assert os.access(AGENT, os.X_OK), f"Agent binary at {AGENT} is not executable"
    assert os.path.isfile(ORACLE), f"Oracle binary missing at {ORACLE}"

    with open(AGENT, "rb") as f:
        agent_bytes = f.read()
    with open(ORACLE, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Submitted executable is byte-identical to the legacy parser"

    compile_proc = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-static", SOURCE, "-o", BUILD, "-lz"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_proc.returncode == 0, (
        "new_parser.c did not compile as a standalone C implementation:\n" +
        compile_proc.stderr.decode(errors="replace")
    )

    shutil.rmtree(JAIL, ignore_errors=True)
    os.mkdir(JAIL, 0o755)
    shutil.copyfile(BUILD, os.path.join(JAIL, "new_parser"))
    os.chmod(os.path.join(JAIL, "new_parser"), 0o755)

    usage = run_isolated(["/new_parser"])
    assert usage.returncode == 1
    assert usage.stdout == b"Usage: /app/bin/legacy_parser <path_to_schema_conf> <path_to_arf_file>\n"

    schema_names = {1: "FILE_NAME", 2: "BUILD_DATE", 255: "SIGNATURE"}
    schema = b"01:FILE_NAME\n02:BUILD_DATE\nFF:SIGNATURE\nINVALID_LINE_FORMAT\n"

    fixed = [
        (b"", 1, b"ERR: Bad Magic\n"),
        (b"BADM" + b"\x00" * 8, 1, b"ERR: Bad Magic\n"),
        (b"ARF1", 2, b"ERR: Zlib fail\n"),
        (b"ARF1" + struct.pack("<I", 10) + b"not-zlib", 2, b"ERR: Zlib fail\n"),
        (encode_valid([(1, b"abc")], 1), 2, b"ERR: Zlib fail\n"),
        (b"ARF1" + struct.pack("<I", 2) + zlib.compress(b"\x01\x03"), 3, b"ERR: Truncated TLV\n"),
        (b"ARF1" + struct.pack("<I", 5) + zlib.compress(b"\x01\x05\x00AB"), 3, b"ERR: Truncated TLV\n"),
    ]
    for arf, code, stdout in fixed:
        assert_isolated_case(schema, arf, code, stdout)

    rng = random.Random(928451)
    for _ in range(300):
        tlvs = []
        for _ in range(rng.randint(1, 25)):
            t = rng.randrange(256)
            value = bytes(rng.randrange(256) for _ in range(rng.randint(0, 80)))
            tlvs.append((t, value))
        arf = encode_valid(tlvs)
        assert_isolated_case(schema, arf, 0, expected_valid(schema_names, tlvs))


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE), f"Oracle binary missing at {ORACLE}"
    assert os.path.isfile(AGENT), f"Agent binary missing at {AGENT}"
    assert os.access(AGENT, os.X_OK), f"Agent binary at {AGENT} is not executable"

    random.seed(1337)
    generate_schema()

    for i in range(5000):
        generate_arf()

        oracle_proc = subprocess.run([ORACLE, SCHEMA_FILE, ARF_FILE], capture_output=True)
        agent_proc = subprocess.run([AGENT, SCHEMA_FILE, ARF_FILE], capture_output=True)

        if oracle_proc.returncode != agent_proc.returncode or oracle_proc.stdout != agent_proc.stdout:
            with open(ARF_FILE, "rb") as f:
                input_data = f.read()
            pytest.fail(
                f"Mismatch on iteration {i}!\n\n"
                f"Input ARF (hex): {input_data.hex()}\n\n"
                f"Oracle exit code: {oracle_proc.returncode}\n"
                f"Agent exit code: {agent_proc.returncode}\n\n"
                f"Oracle stdout: {oracle_proc.stdout!r}\n"
                f"Agent stdout: {agent_proc.stdout!r}\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
