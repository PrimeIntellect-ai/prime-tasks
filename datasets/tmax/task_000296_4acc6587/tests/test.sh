#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_trade_aggregator.py
import os
import secrets
import string
import struct
import subprocess

HOME = "/home/user"
SOURCE = os.path.join(HOME, "trade_aggregator.cpp")
BINARY = os.path.join(HOME, "trade_aggregator")
CAPTURE = os.path.join(HOME, "capture.pcap")
QUERIES = os.path.join(HOME, "queries.txt")
CORRUPTED_LOG = os.path.join(HOME, "corrupted_seq.log")
RESULTS_LOG = os.path.join(HOME, "results.log")
REBUILT = "/tmp/trade_aggregator_rebuilt"


def clear_logs():
    for path in (CORRUPTED_LOG, RESULTS_LOG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def run_program(path):
    clear_logs()
    try:
        completed = subprocess.run(
            [path], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=15
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"{path} timed out") from exc
    assert completed.returncode == 0, (
        f"{path} exited with {completed.returncode}. stderr: {completed.stderr}"
    )
    assert os.path.isfile(CORRUPTED_LOG), (
        f"Expected file {CORRUPTED_LOG} is missing. Did you handle corrupted inputs and write to the log?"
    )
    assert os.path.isfile(RESULTS_LOG), (
        f"Expected file {RESULTS_LOG} is missing. Did you write the results to this file?"
    )


def read_corrupted():
    with open(CORRUPTED_LOG, "r") as f:
        return [line.strip() for line in f if line.strip()]


def read_results_permissive():
    actual = {}
    with open(RESULTS_LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    for line in lines:
        if ":" in line:
            sym, value = line.split(":", 1)
            try:
                actual[sym.strip()] = float(value.strip())
            except ValueError:
                pass
    return actual


def read_results_strict():
    actual = {}
    with open(RESULTS_LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    for line in lines:
        assert ":" in line, f"Malformed results line: {line!r}"
        sym, value = line.split(":", 1)
        sym = sym.strip()
        assert sym not in actual, f"Duplicate result for {sym}"
        try:
            actual[sym] = float(value.strip())
        except ValueError as exc:
            raise AssertionError(f"Invalid amount in results line: {line!r}") from exc
    return actual


def write_pcap(packets):
    with open(CAPTURE, "wb") as f:
        f.write(struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for payload in packets:
            eth = b"\x00" * 12 + b"\x08\x00"
            ip = (b"\x45\x00" + struct.pack(">H", 20 + 8 + len(payload)) +
                  b"\x00" * 5 + b"\x11" + b"\x00" * 10)
            udp = b"\x04\xd2\x23\x28" + struct.pack(">H", 8 + len(payload)) + b"\x00\x00"
            data = eth + ip + udp + payload
            f.write(struct.pack("<IIII", 1700000000, 0, len(data), len(data)))
            f.write(data)


def payload(symbol, seq, amount=None):
    data = symbol.encode("ascii")[:4].ljust(4, b"\0") + struct.pack("<I", seq)
    if amount is not None:
        data += struct.pack("<d", amount)
    return data


def random_symbols(count):
    result = []
    while len(result) < count:
        symbol = "".join(secrets.choice(string.ascii_uppercase) for _ in range(4))
        if symbol not in result:
            result.append(symbol)
    return result


def check_dynamic(program, expected_results, expected_corrupt):
    run_program(program)
    assert read_corrupted() == [str(x) for x in expected_corrupt], (
        f"Incorrect corrupted sequence log: {read_corrupted()}"
    )
    actual = read_results_strict()
    assert set(actual) == set(expected_results), (
        f"Results must contain exactly the requested symbols. Expected {set(expected_results)}, got {set(actual)}"
    )
    for symbol, expected in expected_results.items():
        assert actual[symbol] == expected, (
            f"Incorrect sum for {symbol}: expected {expected}, got {actual[symbol]}"
        )


# Preserve the original binary existence and executable assertions, and ensure it
# is an actual compiled executable rather than an arbitrary executable text file.
assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing. Did you compile the program?"
assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable."
with open(BINARY, "rb") as f:
    assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable produced by compilation."
assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."

# Execute the submitted binary on the supplied capture and retain all original
# fixed-data assertions.
run_program(BINARY)
expected_seqs = ["4", "7"]
assert read_corrupted() == expected_seqs, (
    f"Content of {CORRUPTED_LOG} is incorrect. Expected {expected_seqs}, got {read_corrupted()}."
)
expected_original = {"AAPL": 10000000.5, "MSFT": 500.0, "TSLA": 120.5}
actual_original = read_results_permissive()
for sym, expected_val in expected_original.items():
    assert sym in actual_original, f"Symbol {sym} missing from {RESULTS_LOG}."
    assert actual_original[sym] == expected_val, (
        f"Precision loss or incorrect sum for {sym}. Expected {expected_val}, got {actual_original[sym]}."
    )

# Compile the submitted source independently so the source and delivered binary
# must both implement the requested behavior.
compiled = subprocess.run(
    ["g++", "-o", REBUILT, SOURCE, "-lpcap"],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
)
assert compiled.returncode == 0, f"trade_aggregator.cpp does not compile: {compiled.stderr}"

# Generate an unpredictable capture after the agent has finished. It includes an
# unrequested valid ticker, precision-sensitive sums, and two truncated payloads.
s1, s2, s3, unused = random_symbols(4)
base = secrets.randbelow(2000000) + 10000000
seq0 = secrets.randbelow(1000000000) + 1000
corrupt1 = seq0 + 2
corrupt2 = seq0 + 7
packets = [
    payload(s1, seq0, float(base)),
    payload(s1, seq0 + 1, 0.25),
    payload(s2, corrupt1),
    payload(s1, seq0 + 3, 0.25),
    payload(s2, seq0 + 4, 321.125),
    payload(s2, seq0 + 5, 0.375),
    payload(unused, seq0 + 6, 999.75),
    payload(s3, corrupt2),
    payload(s3, seq0 + 8, 42.5),
]
write_pcap(packets)
with open(QUERIES, "w") as f:
    f.write(s2 + "\n" + s1 + "\n" + s3 + "\n")

expected_dynamic = {s1: float(base) + 0.5, s2: 321.5, s3: 42.5}
expected_corrupt = [corrupt1, corrupt2]

# Exercise both the submitted executable and a fresh build of the submitted source.
check_dynamic(BINARY, expected_dynamic, expected_corrupt)
check_dynamic(REBUILT, expected_dynamic, expected_corrupt)
PY_EOF

if python3 /tmp/verify_trade_aggregator.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
