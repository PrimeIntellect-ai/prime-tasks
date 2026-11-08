#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import struct
import subprocess
import tempfile
import uuid
import secrets
import pytest

EXECUTABLE = "/home/user/audio_sanitizer"
SOURCE = "/home/user/audio_sanitizer.c"
THRESHOLD = 0.0075


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def expected_returncode(values):
    float_sum = f32(0.0)
    double_sum = 0.0
    for value in values:
        value = f32(value)
        float_sum = f32(float_sum + value)
        double_sum += value
        if abs(float(float_sum) - double_sum) > THRESHOLD:
            return 1
    return 0


def read_values(path):
    with open(path, "rb") as handle:
        data = handle.read()
    assert len(data) % 4 == 0
    return [item[0] for item in struct.iter_unpack("<f", data)]


def write_values(path, values):
    normalized = [f32(value) for value in values]
    with open(path, "wb") as handle:
        for value in normalized:
            handle.write(struct.pack("<f", value))
    return normalized


def run_checked(executable, path, expected):
    result = subprocess.run([executable, path], capture_output=True, timeout=5)
    assert result.returncode == expected, (
        f"{executable} returned {result.returncode} for {path}; expected {expected}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_sanitizer_exists_and_executable():
    executable_path = "/home/user/audio_sanitizer"
    assert os.path.isfile(executable_path), f"Executable {executable_path} does not exist."
    assert os.access(executable_path, os.X_OK), f"Executable {executable_path} is not executable."
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    with open(executable_path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "The sanitizer executable is not a compiled ELF executable."


def test_adversarial_corpus():
    executable_path = "/home/user/audio_sanitizer"
    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"

    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    evil_bypassed = []
    for evil_file in evil_files:
        result = subprocess.run([executable_path, evil_file], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_files:
        result = subprocess.run([executable_path, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not errors, " | ".join(errors)


def test_source_and_executable_on_unlabeled_dynamic_inputs():
    rng = secrets.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="telemetry-check-") as temp_dir:
        rebuilt = os.path.join(temp_dir, uuid.uuid4().hex)
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", SOURCE, "-lm", "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            f"The submitted C source did not compile: {compile_result.stderr}"
        )

        executables = [EXECUTABLE, rebuilt]
        for executable in executables:
            no_arg = subprocess.run([executable], capture_output=True, timeout=5)
            extra_arg = subprocess.run(
                [executable, os.path.join(temp_dir, "a"), os.path.join(temp_dir, "b")],
                capture_output=True,
                timeout=5,
            )
            assert no_arg.returncode != 0, "Sanitizer accepted zero arguments."
            assert extra_arg.returncode != 0, "Sanitizer accepted more than one argument."

        cases = []

        # Re-test corpus contents through unpredictable, unlabeled paths. Expected
        # answers are independently calculated from the file data.
        corpus_files = []
        for directory in ("/app/corpora/clean", "/app/corpora/evil"):
            corpus_files.extend(
                os.path.join(directory, name) for name in os.listdir(directory)
                if os.path.isfile(os.path.join(directory, name))
            )
        for original in corpus_files:
            alias = os.path.join(temp_dir, uuid.uuid4().hex)
            shutil.copyfile(original, alias)
            values = read_values(alias)
            cases.append((alias, expected_returncode(values)))

        # Create paired inputs immediately before and at a runtime-derived
        # threshold crossing, exercising float rounding and strict comparison.
        for _ in range(10):
            increment = f32(rng.uniform(0.0004, 0.0045))
            values = [f32(rng.choice([262144.0, 524288.0, 1048576.0]))]
            crossing = None
            for _step in range(1, 100):
                values.append(increment)
                if expected_returncode(values) == 1:
                    crossing = len(values)
                    break
            assert crossing is not None
            for sequence in (values[:-1], values):
                path = os.path.join(temp_dir, uuid.uuid4().hex)
                normalized = write_values(path, sequence)
                cases.append((path, expected_returncode(normalized)))

        # Same-sized randomized files at varied magnitudes prevent decisions
        # based on names, fixed corpus bytes, or file length alone.
        for _ in range(8):
            count = rng.randint(700, 1300)
            low_values = [rng.uniform(-0.01, 0.01) for _ in range(count)]
            high_values = [rng.uniform(-1000000.0, 1000000.0) for _ in range(count)]
            for values in (low_values, high_values):
                path = os.path.join(temp_dir, uuid.uuid4().hex)
                normalized = write_values(path, values)
                cases.append((path, expected_returncode(normalized)))

        assert any(expected == 0 for _, expected in cases)
        assert any(expected == 1 for _, expected in cases)

        for executable in executables:
            for path, expected in cases:
                run_checked(executable, path, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
