#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import re
import secrets
import subprocess
import pytest

CLEAN_DIR = "/home/user/data/clean"
EVIL_DIR = "/home/user/data/evil"
EXECUTABLE = "/home/user/sequence_sanitizer"
SOURCE = "/home/user/sequence_sanitizer.c"
LIB_PATH = "/app/libfasta-parser/libfasta.so"


def run_sanitizer(data):
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/app/libfasta-parser:" + env.get("LD_LIBRARY_PATH", "")
    return subprocess.run(
        [EXECUTABLE], input=data, env=env, capture_output=True, timeout=3
    )


def reference_sanitize(data):
    lines = data.splitlines(keepends=True)
    records = []
    current = []
    for line in lines:
        if line.startswith(b">"):
            if current:
                records.append(current)
            current = [line]
        elif current:
            current.append(line)
    if current:
        records.append(current)

    output = bytearray()
    for record in records:
        seq = b"".join(line.rstrip(b"\r\n") for line in record[1:]).upper()
        if not seq or any(base not in b"ACGTN" for base in seq):
            continue
        if b"GTCGAC" in seq:
            continue
        gc = seq.count(b"G") + seq.count(b"C")
        pct = 100.0 * gc / len(seq)
        if 35.0 <= pct <= 65.0:
            output.extend(b"".join(record))
    return bytes(output)


def test_libfasta_compiled_and_loadable():
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} was not compiled."
    with open(LIB_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{LIB_PATH} is not an ELF shared library."
    lib = ctypes.CDLL(LIB_PATH)
    assert getattr(lib, "parse_fasta", None) is not None, "parse_fasta is not exported by libfasta.so"


def test_executable_exists_and_uses_library():
    assert os.path.isfile(SOURCE), f"C source {SOURCE} not found."
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} not found."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF program."

    dynamic = subprocess.run(
        ["readelf", "-d", EXECUTABLE], capture_output=True, text=True, timeout=2
    )
    assert dynamic.returncode == 0, "Could not inspect executable dynamic dependencies."
    needed = re.findall(r"Shared library: \[(.*?)\]", dynamic.stdout)
    assert any(os.path.basename(item) == "libfasta.so" for item in needed), \
        "sequence_sanitizer is not linked against libfasta.so"


def test_shipped_corpora_according_to_specification():
    clean_files = sorted(
        os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if f.endswith(".fasta")
    )
    evil_files = sorted(
        os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if f.endswith(".fasta")
    )
    assert clean_files, f"No clean files found in {CLEAN_DIR}"
    assert evil_files, f"No evil files found in {EVIL_DIR}"

    for path in clean_files + evil_files:
        with open(path, "rb") as f:
            data = f.read()
        result = run_sanitizer(data)
        assert result.returncode == 0, f"Sanitizer failed on {os.path.basename(path)}"
        assert result.stdout == reference_sanitize(data), \
            f"Incorrect output for {os.path.basename(path)}"


def make_record(header, sequence, rng):
    chunks = []
    pos = 0
    while pos < len(sequence):
        width = rng.randint(1, min(17, len(sequence) - pos))
        chunks.append(sequence[pos:pos + width])
        pos += width
    return (">" + header + "\n" + "\n".join(chunks) + "\n").encode()


def test_unseen_randomized_records():
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    token = secrets.token_hex(12)
    records = []

    # Inclusive threshold cases and mixed-case valid records.
    records.append(make_record(token + "_boundary35", "GCGCGCAAAAAAAAAAAAA", rng))
    records.append(make_record(token + "_boundary65", "GCGCGCGCGCGCGAAAAAAAA", rng))
    records.append(make_record(token + "_mixed", "acgTnACgtNacGT", rng))

    # Random valid records covering passing, low-GC, and high-GC decisions.
    groups = {"pass": [], "low": [], "high": []}
    while min(len(v) for v in groups.values()) < 18:
        length = rng.randint(7, 90)
        seq = "".join(rng.choice("ACGTN") for _ in range(length))
        upper = seq.upper()
        if "GTCGAC" in upper:
            continue
        pct = 100.0 * (upper.count("G") + upper.count("C")) / len(upper)
        category = "pass" if 35.0 <= pct <= 65.0 else ("low" if pct < 35.0 else "high")
        if len(groups[category]) < 18:
            groups[category].append(seq)

    index = 0
    for category in ("pass", "low", "high"):
        for seq in groups[category]:
            if rng.choice([True, False]):
                seq = "".join(ch.lower() if rng.choice([True, False]) else ch for ch in seq)
            records.append(make_record(f"{token}_{index}_{secrets.token_hex(4)}", seq, rng))
            index += 1

    # Invalid alphabet and adapter cases, including adapters split across lines.
    for bad in "ZJRX-1":
        seq = "ACGTNACGTACGT"
        at = rng.randrange(len(seq) + 1)
        seq = seq[:at] + bad + seq[at:]
        records.append(make_record(f"{token}_invalid_{secrets.token_hex(4)}", seq, rng))

    for adapter in ("GTCGAC", "gtcgac", "GtCgAc"):
        seq = "ACGTACGT" + adapter + "TGCATGCA"
        # Force a line boundary inside the adapter for some implementations.
        cut = 8 + rng.randint(1, 5)
        raw = f">{token}_adapter_{secrets.token_hex(4)}\n{seq[:cut]}\n{seq[cut:]}\n"
        records.append(raw.encode())

    rng.shuffle(records)

    # Exercise several fresh combinations so recognizing a fixed complete input is insufficient.
    for start in range(0, len(records), 11):
        data = b"".join(records[start:start + 11])
        expected = reference_sanitize(data)
        result = run_sanitizer(data)
        assert result.returncode == 0, "Sanitizer exited unsuccessfully on randomized FASTA input."
        assert result.stdout == expected, "Incorrect sanitization of unseen randomized FASTA records."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
