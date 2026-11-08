#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import struct
import subprocess
import tempfile

SRC_PATH = "/home/user/extractor.c"
EXE_PATH = "/home/user/extractor"
OUT_PATH = "/home/user/recovered_timeline.csv"
MAGIC = struct.pack("<I", 0xDEADBEEF)


def test_extractor_source_exists():
    assert os.path.isfile(SRC_PATH), f"C source file {SRC_PATH} is missing."


def test_extractor_executable_exists():
    assert os.path.isfile(EXE_PATH), f"Compiled executable {EXE_PATH} is missing."
    st = os.stat(EXE_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {EXE_PATH} is not a compiled ELF executable."


def make_magic_free_bytes(rng, length):
    data = bytearray(rng.getrandbits(8) for _ in range(length))
    while MAGIC in data:
        pos = data.find(MAGIC)
        data[pos] ^= 1
    return bytes(data)


def build_behavior_case():
    rng = random.Random(8675309)
    fields = [
        (0, 1, 0),
        (65535, 4294967295, 1),
        (rng.randrange(65536), rng.randrange(2**32), 37),
        (rng.randrange(65536), rng.randrange(2**32), 513),
        (rng.randrange(65536), rng.randrange(2**32), 19),
    ]

    stream = bytearray(make_magic_free_bytes(rng, 23) + MAGIC[:3])
    expected = []
    for sensor_id, timestamp, payload_length in fields:
        stream.extend(make_magic_free_bytes(rng, rng.randrange(1, 31)))
        payload = make_magic_free_bytes(rng, payload_length)
        stream.extend(struct.pack("<IHIH", 0xDEADBEEF, sensor_id, timestamp, payload_length))
        stream.extend(payload)
        expected.append(f"{timestamp},{sensor_id},{payload_length}\n")
    stream.extend(make_magic_free_bytes(rng, 41) + MAGIC[:2])
    return bytes(stream), "".join(expected).encode("ascii")


def assert_scanner_behavior(executable):
    stream, expected = build_behavior_case()
    result = subprocess.run(
        [executable], input=stream, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=5, check=False
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}. stderr: "
        f"{result.stderr.decode(errors='replace')}"
    )
    assert result.stdout == expected, (
        f"{executable} produced incorrect output for a generated binary stream.\n"
        f"Expected: {expected!r}\nActual: {result.stdout!r}"
    )

    empty = subprocess.run(
        [executable], input=b"ordinary bytes without a record", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5, check=False
    )
    assert empty.returncode == 0
    assert empty.stdout == b"", f"{executable} emitted output for a stream with no records."


def test_extractor_behavior_and_source_build():
    assert_scanner_behavior(EXE_PATH)

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "extractor")
        compile_result = subprocess.run(
            ["gcc", SRC_PATH, "-o", rebuilt], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10, check=False
        )
        assert compile_result.returncode == 0, (
            "extractor.c does not compile with gcc: "
            + compile_result.stderr.decode(errors="replace")
        )
        assert_scanner_behavior(rebuilt)


def matching_archive_files():
    paths = []
    base = "/home/user/sensor_archives"
    for root, _, names in os.walk(base):
        for name in names:
            path = os.path.join(root, name)
            if name.endswith(".log") and os.path.getsize(path) > 4096:
                paths.append(path)
    return sorted(paths)


def test_extractor_on_required_archives():
    archive_data = bytearray()
    for path in matching_archive_files():
        with open(path, "rb") as f:
            archive_data.extend(f.read())

    result = subprocess.run(
        [EXE_PATH], input=bytes(archive_data), stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10, check=False
    )
    assert result.returncode == 0, (
        f"Extractor failed on the required archives: {result.stderr.decode(errors='replace')}"
    )

    lines = result.stdout.decode("ascii").splitlines()
    for line in lines:
        parts = line.split(",")
        assert len(parts) == 3
        tuple(int(part) for part in parts)
    lines.sort(key=lambda line: int(line.split(",", 1)[0]))

    with open(OUT_PATH, "r") as f:
        recovered_lines = [line.strip() for line in f if line.strip()]
    assert recovered_lines == lines, (
        "The recovered timeline does not equal the sorted output produced by extractor "
        "from the files matching the required metadata criteria."
    )


def test_recovered_timeline():
    assert os.path.isfile(OUT_PATH), f"Output file {OUT_PATH} is missing."

    expected_lines = [
        "1600000000,10,50",
        "1600000025,15,100",
        "1600000050,12,20",
        "1600000100,10,10"
    ]

    with open(OUT_PATH, "r") as f:
        actual_content = f.read().strip()

    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {OUT_PATH} do not match the expected timeline.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
