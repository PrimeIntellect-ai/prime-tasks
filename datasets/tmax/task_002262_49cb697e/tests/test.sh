#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import struct
import subprocess
import tempfile
import time
import urllib.request

import pytest

SANITIZER_BIN = "/home/user/sanitizer"
SANITIZER_SRC = "/home/user/sanitizer.cpp"
VERIFY_SH = "/home/user/verify.sh"
CLEAN_CORPUS = "/home/user/corpus/clean"
EVIL_CORPUS = "/home/user/corpus/evil"
ARCHIVER = "/app/archiver.sh"


def compress_rle(payload: bytes) -> bytes:
    s = payload.decode("utf-8")
    result = []
    i = 0
    while i < len(s):
        count = 1
        while i + count < len(s) and s[i + count] == s[i]:
            count += 1
        if count >= 3:
            result.append("~" + s[i] + str(count))
        else:
            result.append(s[i] * count)
        i += count
    return "".join(result).encode("utf-8")


def is_malicious(payload: bytes) -> bool:
    lines = payload.split(b"\n")
    return b"[CORRUPT]" in payload or (
        len(lines) >= 2 and b"STATUS: FATAL_BLOAT" in lines[1]
    )


def make_bin(records):
    data = bytearray()
    for payload in records:
        data += struct.pack("<II", 0xDEADBEEF, len(payload))
        data += payload
    return bytes(data)


def expected_zarc(records):
    output = bytearray(b"ZARC001\n")
    for payload in records:
        if is_malicious(payload):
            continue
        compressed = compress_rle(payload)
        output += struct.pack("<II", len(payload), len(compressed))
        output += compressed
    return bytes(output)


def parse_bin(filepath):
    with open(filepath, "rb") as f:
        data = f.read()
    records = []
    idx = 0
    while idx < len(data):
        magic = data[idx:idx + 4]
        if magic != b"\xef\xbe\xad\xde":
            break
        size = struct.unpack("<I", data[idx + 4:idx + 8])[0]
        payload = data[idx + 8:idx + 8 + size]
        records.append(payload)
        idx += 8 + size
    return records


def run_sanitizer(executable, records, directory, stem):
    input_path = os.path.join(directory, stem + ".bin")
    output_path = os.path.join(directory, stem + ".zarc")
    with open(input_path, "wb") as f:
        f.write(make_bin(records))
    # Ensure implementations replace, rather than append to, an existing output.
    with open(output_path, "wb") as f:
        f.write(b"preexisting-junk")
    completed = subprocess.run(
        [executable, input_path, output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=4,
    )
    assert completed.returncode == 0, (
        f"{executable} failed with {completed.returncode}: "
        f"{completed.stderr.decode(errors='replace')}"
    )
    with open(output_path, "rb") as f:
        return f.read()


@pytest.fixture(scope="session")
def rebuilt_sanitizer(tmp_path_factory):
    build_dir = tmp_path_factory.mktemp("source-build")
    rebuilt = build_dir / "sanitizer-from-source"
    completed = subprocess.run(
        ["g++", "-O3", "-std=c++17", SANITIZER_SRC, "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        "sanitizer.cpp does not compile with the required command:\n" +
        completed.stderr.decode(errors="replace")
    )
    return str(rebuilt)


def test_sanitizer_exists():
    assert os.path.isfile(SANITIZER_SRC), f"Source not found at {SANITIZER_SRC}"
    assert os.path.isfile(SANITIZER_BIN), f"Sanitizer binary not found at {SANITIZER_BIN}"
    assert os.access(SANITIZER_BIN, os.X_OK), f"Sanitizer binary at {SANITIZER_BIN} is not executable"
    with open(SANITIZER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sanitizer must be a compiled executable"


def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_CORPUS) if f.endswith(".bin")]
    assert evil_files, "No evil corpus files found."

    bypassed = []
    for fname in evil_files:
        in_path = os.path.join(EVIL_CORPUS, fname)
        with tempfile.NamedTemporaryFile(suffix=".zarc", delete=False) as out_f:
            out_path = out_f.name
        try:
            subprocess.run(
                [SANITIZER_BIN, in_path, out_path],
                capture_output=True,
                timeout=2,
                check=True,
            )
            with open(out_path, "rb") as f:
                out_data = f.read()
            if out_data != b"ZARC001\n":
                bypassed.append(fname)
        except subprocess.CalledProcessError:
            bypassed.append(fname + " (crashed/error)")
        except subprocess.TimeoutExpired:
            bypassed.append(fname + " (timeout)")
        finally:
            if os.path.exists(out_path):
                os.remove(out_path)

    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil files bypassed sanitization: {', '.join(bypassed[:5])}"


def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if f.endswith(".bin")]
    assert clean_files, "No clean corpus files found."

    modified_or_failed = []
    for fname in clean_files:
        in_path = os.path.join(CLEAN_CORPUS, fname)
        with tempfile.NamedTemporaryFile(suffix=".zarc", delete=False) as out_f:
            out_path = out_f.name
        try:
            subprocess.run(
                [SANITIZER_BIN, in_path, out_path],
                capture_output=True,
                timeout=2,
                check=True,
            )
            with open(out_path, "rb") as f:
                out_data = f.read()

            if not out_data.startswith(b"ZARC001\n"):
                modified_or_failed.append(fname + " (missing global header)")
                continue

            records = parse_bin(in_path)
            expected_data = b"ZARC001\n"
            for rec in records:
                comp = compress_rle(rec)
                expected_data += struct.pack("<I", len(rec)) + struct.pack("<I", len(comp)) + comp

            if out_data != expected_data:
                modified_or_failed.append(fname + " (RLE mismatch)")
        except Exception as exc:
            modified_or_failed.append(fname + f" (error: {exc})")
        finally:
            if os.path.exists(out_path):
                os.remove(out_path)

    assert not modified_or_failed, f"{len(modified_or_failed)} of {len(clean_files)} clean files modified/failed: {', '.join(modified_or_failed[:5])}"


def test_generated_parsing_filtering_and_rle(rebuilt_sanitizer):
    token = secrets.token_hex(12).encode("ascii")
    generated = []
    for _ in range(8):
        char = secrets.choice(b"ABCDEFGHJKLMNPQRSTUVWXYZ")
        count = 3 + secrets.randbelow(40)
        generated.append(
            b"id=" + secrets.token_hex(6).encode("ascii") + b"\n"
            b"ordinary second line\nrun=" + bytes([char]) * count + b";end"
        )

    # FATAL_BLOAT only causes rejection on line two. CORRUPT causes rejection anywhere.
    valid_fatal_first = b"STATUS: FATAL_BLOAT\nsecond line is safe\n" + token + b"AAAAA"
    valid_fatal_third = b"first\nsecond line is safe\nSTATUS: FATAL_BLOAT " + token
    evil_fatal = b"first " + token + b"\nprefix STATUS: FATAL_BLOAT suffix\nthird"
    evil_corrupt = b"first\nsecond safe\nrandom=" + token + b" [CORRUPT] trailing"

    cases = [
        [generated[0]],
        [evil_fatal],
        [evil_corrupt],
        [valid_fatal_first, evil_fatal, generated[1], evil_corrupt, valid_fatal_third],
        generated,
    ]

    with tempfile.TemporaryDirectory(prefix="dynamic-sanitizer-") as directory:
        for executable in (SANITIZER_BIN, rebuilt_sanitizer):
            for index, records in enumerate(cases):
                stem = secrets.token_hex(8) + "-" + str(index)
                actual = run_sanitizer(executable, records, directory, stem)
                assert actual == expected_zarc(records), (
                    f"incorrect parsing, filtering, or RLE from {executable} on generated case {index}"
                )


def test_verify_script_exists_and_runs():
    assert os.path.isfile(VERIFY_SH), f"Batch verification script not found at {VERIFY_SH}"
    assert os.path.getsize(VERIFY_SH) > 0, "verify.sh is empty"
    syntax = subprocess.run(["bash", "-n", VERIFY_SH], capture_output=True, timeout=3)
    assert syntax.returncode == 0, syntax.stderr.decode(errors="replace")
    completed = subprocess.run(
        ["bash", "-x", VERIFY_SH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert completed.returncode == 0, "verify.sh failed when run over the supplied corpus"
    trace = completed.stdout + completed.stderr
    assert b"/home/user/sanitizer" in trace, "verify.sh did not invoke the sanitizer"
    assert b"clean_" in trace and b"evil_" in trace, "verify.sh did not process both corpus directories"


def test_end_to_end_integration():
    assert os.path.isfile(ARCHIVER), "archiver.sh is missing"
    assert os.access(ARCHIVER, os.X_OK), "archiver.sh is not executable"

    # Stop any stale archiver, clear all artifacts and start the submitted script itself.
    subprocess.run(["pkill", "-f", "/app/archiver.sh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)
    subprocess.run(["redis-cli", "DEL", "log_queue"], check=True, stdout=subprocess.DEVNULL)

    raw_dir = "/home/user/logs/raw"
    archive_dir = "/home/user/logs/archive"
    os.makedirs(raw_dir, exist_ok=True)
    os.makedirs(archive_dir, exist_ok=True)
    for directory in (raw_dir, archive_dir):
        for name in os.listdir(directory):
            path = os.path.join(directory, name)
            if os.path.isfile(path) or os.path.islink(path):
                os.unlink(path)

    archiver = subprocess.Popen(
        [ARCHIVER],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        token = secrets.token_hex(16).encode("ascii")
        test_payload = b"integration=" + token + b"\nnormal second line\nQQQQQQQ" + token
        malicious = b"integration bad\nSTATUS: FATAL_BLOAT " + token + b"\nignored"
        bin_data = make_bin([malicious, test_payload])

        req = urllib.request.Request("http://127.0.0.1:8080/", data=bin_data, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=3) as response:
                assert response.status == 200
        except Exception as exc:
            pytest.fail(f"Failed to post to frontend: {exc}")

        expected = expected_zarc([malicious, test_payload])
        expected_comp = compress_rle(test_payload)
        expected_chunk = struct.pack("<I", len(test_payload)) + struct.pack("<I", len(expected_comp)) + expected_comp

        deadline = time.time() + 10
        zarc_files = []
        while time.time() < deadline:
            zarc_files = [f for f in os.listdir(archive_dir) if f.endswith(".zarc")]
            raw_files = os.listdir(raw_dir)
            queue_len = subprocess.check_output(["redis-cli", "LLEN", "log_queue"]).strip()
            if zarc_files and not raw_files and queue_len == b"0":
                break
            time.sleep(0.2)

        found_expected = False
        exact_matches = []
        for zf in zarc_files:
            with open(os.path.join(archive_dir, zf), "rb") as f:
                content = f.read()
            if expected_chunk in content:
                found_expected = True
            if content == expected:
                exact_matches.append(zf)

        assert found_expected, "End-to-End integration failed: Could not find the processed payload in /home/user/logs/archive/*.zarc"
        assert len(exact_matches) == 1, "integration did not create exactly one correctly formatted archive"
        assert not os.listdir(raw_dir), "archiver did not delete the raw dump"
        assert subprocess.check_output(["redis-cli", "LLEN", "log_queue"]).strip() == b"0", "log queue was not consumed"
    finally:
        try:
            os.killpg(archiver.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            archiver.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(archiver.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
