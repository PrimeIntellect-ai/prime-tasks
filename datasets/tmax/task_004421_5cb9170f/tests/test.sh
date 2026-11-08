#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import shutil
import struct
import subprocess
import tempfile

import pytest


def test_libsensordata_fixed():
    repo_path = "/app/libsensordata"
    # Preserve the original build and package-test assertions.
    try:
        subprocess.run(["make"], cwd=repo_path, check=True, capture_output=True, text=True)
        subprocess.run(["make", "check"], cwd=repo_path, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Failed to build or pass tests in {repo_path}. 'make check' failed "
            f"with exit code {e.returncode}.\nStdout: {e.stdout}\nStderr: {e.stderr}"
        )


def test_double_serialization_really_preserves_precision():
    repo_path = "/app/libsensordata"
    source = os.path.join(repo_path, "src", "encoder.cpp")
    assert os.path.isfile(source), f"Missing library source: {source}"

    with tempfile.TemporaryDirectory(prefix="serialization-check-") as td:
        obj = os.path.join(td, "encoder.o")
        harness = os.path.join(td, "precision_check.cpp")
        binary = os.path.join(td, "precision_check")

        with open(harness, "w", encoding="utf-8") as f:
            f.write(r'''#include <cstdint>
#include <cstring>
#include <random>

void serialize(double, char*);

static bool check_value(double value) {
    unsigned char actual[24];
    unsigned char expected[sizeof(double)];
    std::memset(actual, 0xA5, sizeof(actual));
    std::memcpy(expected, &value, sizeof(value));
    serialize(value, reinterpret_cast<char*>(actual));
    if (std::memcmp(actual, expected, sizeof(double)) != 0) return false;
    for (std::size_t i = sizeof(double); i < sizeof(actual); ++i) {
        if (actual[i] != 0xA5) return false;
    }
    return true;
}

int main() {
    const double required[] = {
        123456789.123456789,
        -987654321.987654321,
        0x1.0000000000001p+0,
        0x1.fffffffffffffp+500,
        0x1.0000000000001p-500
    };
    for (double value : required) if (!check_value(value)) return 1;

    std::random_device rd;
    std::mt19937_64 rng((static_cast<std::uint64_t>(rd()) << 32) ^ rd());
    int checked = 0;
    while (checked < 256) {
        std::uint64_t bits = rng();
        // Exclude NaNs and infinities, but retain ordinary values whose low
        // mantissa bits cannot survive conversion through float.
        if (((bits >> 52) & 0x7ffu) == 0x7ffu) continue;
        double value;
        std::memcpy(&value, &bits, sizeof(value));
        if (!check_value(value)) return 2;
        ++checked;
    }
    return 0;
}
''')

        compile_obj = subprocess.run(
            ["g++", "-std=c++17", "-Dmain=libsensordata_embedded_main", "-c", source, "-o", obj],
            cwd=repo_path,
            capture_output=True,
            text=True,
        )
        assert compile_obj.returncode == 0, (
            f"Could not compile encoder for precision test.\n"
            f"Stdout: {compile_obj.stdout}\nStderr: {compile_obj.stderr}"
        )

        link = subprocess.run(
            ["g++", "-std=c++17", harness, obj, "-o", binary],
            capture_output=True,
            text=True,
        )
        assert link.returncode == 0, (
            f"Could not link precision test.\nStdout: {link.stdout}\nStderr: {link.stderr}"
        )
        result = subprocess.run([binary], capture_output=True, timeout=10)
        assert result.returncode == 0, (
            "serialize() did not preserve the exact object representation of "
            f"double values (precision test exit {result.returncode})."
        )


def test_detector_exists_and_executable():
    detector_path = "/home/user/detector"
    assert os.path.isfile(detector_path), f"Detector executable not found at {detector_path}."
    assert os.access(detector_path, os.X_OK), f"Detector at {detector_path} is not executable."


def test_detector_adversarial_corpus():
    detector_path = "/home/user/detector"
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, "Clean corpus is empty."
    assert len(evil_files) > 0, "Evil corpus is empty."

    failed_clean = []
    for f in clean_files:
        res = subprocess.run([detector_path, f], capture_output=True)
        if res.returncode != 0:
            failed_clean.append(os.path.basename(f))

    failed_evil = []
    for f in evil_files:
        res = subprocess.run([detector_path, f], capture_output=True)
        if res.returncode != 1:
            failed_evil.append(os.path.basename(f))

    errors = []
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed/accepted: {', '.join(failed_evil)}")

    if errors:
        pytest.fail(" | ".join(errors))


def _run_detector(detector, path):
    try:
        return subprocess.run([detector, path], capture_output=True, timeout=5).returncode
    except subprocess.TimeoutExpired:
        return None


def test_detector_source_and_unlabelled_generated_payloads():
    source = "/home/user/detector.cpp"
    installed = "/home/user/detector"
    assert os.path.isfile(source), f"Detector C++ source not found at {source}."

    with tempfile.TemporaryDirectory(prefix="payload-validation-") as td:
        rebuilt = os.path.join(td, "detector_rebuilt")
        build = subprocess.run(
            ["g++", "-std=c++17", "-O2", source, "-o", rebuilt],
            cwd="/home/user",
            capture_output=True,
            text=True,
        )
        assert build.returncode == 0, (
            f"detector.cpp does not compile.\nStdout: {build.stdout}\nStderr: {build.stderr}"
        )

        cases = []

        # Re-test the supplied payload bytes under neutral, randomized paths so
        # classification cannot depend on the clean/evil directory names.
        for expected, corpus in ((0, "/app/corpora/clean"), (1, "/app/corpora/evil")):
            entries = [p for p in os.listdir(corpus) if os.path.isfile(os.path.join(corpus, p))]
            random.shuffle(entries)
            for entry in entries:
                dst = os.path.join(td, secrets.token_hex(12) + ".bin")
                shutil.copyfile(os.path.join(corpus, entry), dst)
                cases.append((dst, expected))

        token = secrets.token_hex(16)
        finite = 100000000 + secrets.randbelow(900000000)
        generated_clean = [
            f'{{"sensor":"{token}","value":{finite}.123456789,"status":"ok"}}\n'.encode("utf-8"),
            f"sensor={token}\nvalue=-0.000000000123456789\nmessage=telemetry received\n".encode("utf-8"),
            f"id={token};temperature=21.875;sequence={secrets.randbelow(1000000)}\n".encode("utf-8"),
        ]
        generated_bad = [
            f"sensor={token}\nvalue=NaN\n".encode("ascii"),
            f"sensor={token}\nvalue=Infinity\n".encode("ascii"),
            f"sensor={token}\nvalue=1e999999\n".encode("ascii"),
            f"sensor={token}\nvalue=0.".encode("ascii") + b"7" * 4096 + b"\n",
            b"sensor=" + token.encode("ascii") + b"\nmessage=\xf0\x28\x8c\x28\n",
            struct.pack("<Q", 0x7FF8000000000001) + token.encode("ascii"),
        ]

        for expected, payloads in ((0, generated_clean), (1, generated_bad)):
            for payload in payloads:
                path = os.path.join(td, secrets.token_hex(12) + ".dat")
                with open(path, "wb") as f:
                    f.write(payload)
                cases.append((path, expected))

        random.SystemRandom().shuffle(cases)
        failures = []
        for detector in (installed, rebuilt):
            for path, expected in cases:
                actual = _run_detector(detector, path)
                if actual != expected:
                    failures.append((os.path.basename(detector), os.path.basename(path), expected, actual))

        assert not failures, "Detector failed generated/unlabelled payload checks: " + "; ".join(
            f"{detector} on {path}: expected {expected}, got {actual}"
            for detector, path, expected, actual in failures[:20]
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
