#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

SANITIZER_BIN = "/home/user/sanitizer"
CLEAN_CORPUS_DIR = "/var/test_corpus/clean"
EVIL_CORPUS_DIR = "/var/test_corpus/evil"


def test_sanitizer_binary_exists():
    assert os.path.exists(SANITIZER_BIN), f"Sanitizer binary not found at {SANITIZER_BIN}"
    assert os.path.isfile(SANITIZER_BIN), f"{SANITIZER_BIN} is not a file"
    assert os.access(SANITIZER_BIN, os.X_OK), f"Sanitizer binary {SANITIZER_BIN} is not executable"


def test_clean_corpus_accepted():
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus missing at {CLEAN_CORPUS_DIR}"
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus"

    failed_files = []
    for fpath in clean_files:
        try:
            result = subprocess.run(
                [SANITIZER_BIN, fpath],
                capture_output=True,
                text=True,
                timeout=2
            )
            stdout = result.stdout.strip()
            if result.returncode != 0 or stdout != "CLEAN":
                failed_files.append((os.path.basename(fpath), result.returncode, stdout))
        except Exception as e:
            failed_files.append((os.path.basename(fpath), "ERROR", str(e)))

    if failed_files:
        details = "\n".join(f"{fname}: exit_code={code}, output={out}" for fname, code, out in failed_files)
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected:\n{details}")


def test_evil_corpus_rejected():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus missing at {EVIL_CORPUS_DIR}"
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil corpus"

    failed_files = []
    for fpath in evil_files:
        try:
            result = subprocess.run(
                [SANITIZER_BIN, fpath],
                capture_output=True,
                text=True,
                timeout=2
            )
            stdout = result.stdout.strip()
            if result.returncode != 1 or stdout != "REJECT":
                failed_files.append((os.path.basename(fpath), result.returncode, stdout))
        except Exception as e:
            failed_files.append((os.path.basename(fpath), "ERROR", str(e)))

    if failed_files:
        details = "\n".join(f"{fname}: exit_code={code}, output={out}" for fname, code, out in failed_files)
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed:\n{details}")


def expected_result(data):
    try:
        data.decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        return 1, "REJECT"
    if any(byte < 0x20 and byte not in (0x09, 0x0A, 0x0D) for byte in data):
        return 1, "REJECT"
    return 0, "CLEAN"


def test_generated_mixed_corpus_at_unlabelled_paths():
    prefix = b"timestamp,sensor_name,value\n2023-10-01T12:00:00Z,"
    suffix = b",25.4\n"

    payloads = [
        b"TempSensor_A",
        b"Temp\tSensor\rName",
        "Temperaturfühler_東京_😀".encode("utf-8"),
        b"boundaries_\xc2\x80_\xdf\xbf_\xe0\xa0\x80_\xed\x9f\xbf_\xee\x80\x80_\xf0\x90\x80\x80_\xf4\x8f\xbf\xbf",
        b"bad_\x80",
        b"bad_\xbf",
        b"bad_\xc0\x80",
        b"bad_\xc1\xbf",
        b"bad_\xc2",
        b"bad_\xc2A",
        b"bad_\xe2\x82",
        b"bad_\xe2(\xa1",
        b"bad_\xe0\x80\x80",
        b"bad_\xed\xa0\x80",
        b"bad_\xed\xbf\xbf",
        b"bad_\xf0\x9f\x92",
        b"bad_\xf0(\x8c\xbc",
        b"bad_\xf0\x80\x80\x80",
        b"bad_\xf4\x90\x80\x80",
        b"bad_\xf5\x80\x80\x80",
        b"bad_\xfe",
        b"bad_\xff",
    ]

    # Exercise every prohibited ASCII control byte, including NUL.
    for byte in range(0x20):
        if byte not in (0x09, 0x0A, 0x0D):
            payloads.append(b"control_" + bytes([byte]) + b"_byte")

    cases = []
    for payload in payloads:
        data = prefix + payload + suffix
        cases.append((secrets.token_hex(12) + ".dat", data, expected_result(data)))

    secrets.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="utf8_gate_") as directory:
        failures = []
        for filename, data, expected in cases:
            path = os.path.join(directory, filename)
            with open(path, "wb") as stream:
                stream.write(data)

            try:
                result = subprocess.run(
                    [SANITIZER_BIN, path],
                    capture_output=True,
                    text=True,
                    timeout=2
                )
                actual = (result.returncode, result.stdout.strip())
                if actual != expected:
                    failures.append((filename, expected, actual))
            except Exception as exc:
                failures.append((filename, expected, ("ERROR", str(exc))))

        if failures:
            details = "\n".join(
                f"{name}: expected={expected}, actual={actual}"
                for name, expected, actual in failures
            )
            pytest.fail(f"Generated encoding checks failed:\n{details}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
