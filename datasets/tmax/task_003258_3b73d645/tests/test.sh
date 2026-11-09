#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import secrets
import shutil
import subprocess
import tempfile
import uuid

import pytest

EXECUTABLE = "/home/user/log_filter"
CLEAN_CORPUS = "/app/corpora/clean"
EVIL_CORPUS = "/app/corpora/evil"


def run_filter(input_dir, output_dir, timeout=20):
    return subprocess.run(
        [EXECUTABLE, input_dir, output_dir],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def test_executable_exists():
    """Test that the compiled executable exists and is executable."""
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Final artifact is not a compiled ELF executable"


def test_clean_corpus_preserved():
    """Test that all clean corpus files are preserved and unchanged."""
    out_dir = tempfile.mkdtemp()
    try:
        result = run_filter(CLEAN_CORPUS, out_dir)
        assert result.returncode == 0, (
            f"Executable failed on clean corpus with return code {result.returncode}\n"
            f"Stderr: {result.stderr}"
        )

        clean_files = [
            f for f in os.listdir(CLEAN_CORPUS)
            if os.path.isfile(os.path.join(CLEAN_CORPUS, f))
        ]
        missing = []
        modified = []

        for f in clean_files:
            src = os.path.join(CLEAN_CORPUS, f)
            dst = os.path.join(out_dir, f)
            if not os.path.isfile(dst):
                missing.append(f)
            elif not filecmp.cmp(src, dst, shallow=False):
                modified.append(f)

        errors = []
        if missing:
            errors.append(f"{len(missing)} of {len(clean_files)} clean files missing: {missing}")
        if modified:
            errors.append(f"{len(modified)} of {len(clean_files)} clean files modified: {modified}")

        assert not errors, "\n".join(errors)
    finally:
        shutil.rmtree(out_dir)


def test_evil_corpus_rejected():
    """Test that all evil corpus files are rejected."""
    out_dir = tempfile.mkdtemp()
    try:
        result = run_filter(EVIL_CORPUS, out_dir)
        assert result.returncode == 0, (
            f"Executable failed on evil corpus with return code {result.returncode}\n"
            f"Stderr: {result.stderr}"
        )

        evil_files = [
            f for f in os.listdir(EVIL_CORPUS)
            if os.path.isfile(os.path.join(EVIL_CORPUS, f))
        ]
        bypassed = []

        for f in evil_files:
            dst = os.path.join(out_dir, f)
            if os.path.isfile(dst):
                bypassed.append(f)

        if bypassed:
            pytest.fail(
                f"{len(bypassed)} of {len(evil_files)} evil files bypassed "
                f"(copied to output): {bypassed}"
            )
    finally:
        shutil.rmtree(out_dir)


def test_generated_mixed_corpus_and_worker_stress():
    """Exercise parsing and the worker queue on an unpredictable, large corpus."""
    with tempfile.TemporaryDirectory(prefix="log_filter_dynamic_") as root:
        input_dir = os.path.join(root, "incoming_" + uuid.uuid4().hex)
        os.mkdir(input_dir)

        expected_valid = {}
        expected_invalid = {}

        # A large number of independently named valid files stresses concurrent
        # dequeue operations and makes dropped files observable.
        for i in range(1200):
            name = f"valid_{uuid.uuid4().hex}_{i}.log"
            token = secrets.token_hex(16).encode("ascii")
            if i % 4 == 0:
                data = b"entry " + token + b"\nnext\tfield\r\n"
            elif i % 4 == 1:
                data = b"[INFO] " + token + b" printable text\n"
            elif i % 4 == 2:
                data = b"X" * (700 + (i % 300)) + b"\n"
            else:
                data = b"final line " + token
            expected_valid[name] = data

        # Include additional valid edge cases for permitted whitespace.
        expected_valid[f"empty_{uuid.uuid4().hex}.log"] = b""
        expected_valid[f"whitespace_{uuid.uuid4().hex}.log"] = b"one\ttwo\r\nthree\n"
        expected_valid[f"near_limit_{uuid.uuid4().hex}.log"] = b"P" * 1000 + b"\n"

        # Long logical lines, with and without a trailing newline.
        for i in range(40):
            name = f"long_{uuid.uuid4().hex}_{i}.log"
            expected_invalid[name] = b"header\n" + (b"L" * (1025 + i)) + (b"\n" if i % 2 else b"")

        # Embedded NULs at varying positions, including before otherwise benign text.
        for i in range(40):
            name = f"nul_{uuid.uuid4().hex}_{i}.log"
            expected_invalid[name] = b"A" * (i % 17) + b"\x00" + secrets.token_bytes(12) + b"\n"

        # ASCII control characters other than permitted tab, CR, and LF.
        controls = [1, 2, 7, 8, 11, 12, 14, 27, 31, 127]
        for i in range(50):
            name = f"control_{uuid.uuid4().hex}_{i}.log"
            control = bytes([controls[i % len(controls)]])
            expected_invalid[name] = b"normal prefix" + control + b"normal suffix\n"

        all_inputs = dict(expected_valid)
        all_inputs.update(expected_invalid)
        for name, data in all_inputs.items():
            with open(os.path.join(input_dir, name), "wb") as f:
                f.write(data)

        expected_names = set(expected_valid)

        # Repeated fresh runs increase coverage of intermittent queue races.
        for run_number in range(3):
            output_dir = os.path.join(root, f"output_{uuid.uuid4().hex}_{run_number}")
            os.mkdir(output_dir)
            result = run_filter(input_dir, output_dir)
            assert result.returncode == 0, (
                f"Generated corpus run {run_number} failed with {result.returncode}\n"
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
            )

            actual_names = {
                name for name in os.listdir(output_dir)
                if os.path.isfile(os.path.join(output_dir, name))
            }
            missing = expected_names - actual_names
            unexpected = actual_names - expected_names
            assert not missing, (
                f"Generated run {run_number} dropped {len(missing)} valid files; "
                f"examples: {sorted(missing)[:10]}"
            )
            assert not unexpected, (
                f"Generated run {run_number} copied {len(unexpected)} invalid files; "
                f"examples: {sorted(unexpected)[:10]}"
            )

            for name, expected_data in expected_valid.items():
                with open(os.path.join(output_dir, name), "rb") as f:
                    assert f.read() == expected_data, f"Valid file was modified: {name}"

        # Processing must not alter or remove the source corpus.
        assert set(os.listdir(input_dir)) == set(all_inputs)
        for name, expected_data in all_inputs.items():
            with open(os.path.join(input_dir, name), "rb") as f:
                assert f.read() == expected_data, f"Input file was altered: {name}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
