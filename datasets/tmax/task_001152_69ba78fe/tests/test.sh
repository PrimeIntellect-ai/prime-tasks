#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import uuid

import numpy as np
import pytest

VENDOR_DIR = '/app/vendor/telemetry-parser'
PROJECT_DIR = '/home/user/prof_classifier'
EXECUTABLE = os.path.join(PROJECT_DIR, 'trace_filter')


def run_classifier(path):
    result = subprocess.run([EXECUTABLE, path], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (
        f"Classifier failed for {path} with exit code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    return result.stdout.strip()


def test_telemetry_parser_builds():
    """Verify that the telemetry-parser Makefile has been fixed and builds successfully."""
    assert os.path.isdir(VENDOR_DIR), f"Directory {VENDOR_DIR} is missing"

    result = subprocess.run(
        ['make', 'build'],
        cwd=VENDOR_DIR,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, (
        f"make build failed in {VENDOR_DIR}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    assert os.path.isfile(os.path.join(VENDOR_DIR, 'bin', 'telemetry')), \
        "Binary bin/telemetry was not created by make build"


def test_classifier_executable_exists():
    """Verify the compiled Go executable and source exist."""
    assert os.path.isfile(EXECUTABLE), \
        f"Executable {EXECUTABLE} not found. Did you compile the Go code?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "trace_filter must be a compiled executable"

    main_go = os.path.join(PROJECT_DIR, 'main.go')
    assert os.path.isfile(main_go), f"Source file {main_go} is missing"
    with open(main_go, encoding='utf-8') as f:
        source = f.read()
    assert 'gonum.org/v1/gonum' in source, \
        "main.go must use the gonum.org/v1/gonum library"
    assert 'gonum.org/v1/gonum/dsp/fourier' in source, \
        "main.go must use Gonum's Fourier transform package"


def test_classifier_accuracy():
    """Verify the classifier correctly identifies the supplied EVIL and CLEAN traces."""
    assert os.path.isfile(EXECUTABLE), "Executable missing, cannot run accuracy tests."

    evil_dir = '/home/user/corpora/evil'
    clean_dir = '/home/user/corpora/clean'
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.csv')]
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.csv')]

    assert len(evil_files) > 0, "No evil traces found to test."
    assert len(clean_files) > 0, "No clean traces found to test."

    evil_bypassed = []
    clean_rejected = []

    for name in evil_files:
        output = run_classifier(os.path.join(evil_dir, name))
        if output != 'EVIL':
            evil_bypassed.append((name, output))

    for name in clean_files:
        output = run_classifier(os.path.join(clean_dir, name))
        if output != 'CLEAN':
            clean_rejected.append((name, output))

    errors = []
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: " +
            ', '.join(name for name, _ in evil_bypassed)
        )
    if clean_rejected:
        errors.append(
            f"{len(clean_rejected)} of {len(clean_files)} clean modified (rejected): " +
            ', '.join(name for name, _ in clean_rejected)
        )
    if errors:
        pytest.fail("Classifier errors:\n" + "\n".join(errors))


def write_trace(path, values):
    with open(path, 'w', encoding='utf-8') as f:
        f.write('timestamp_ms,latency_ms\n')
        for timestamp, latency in enumerate(values):
            f.write(f'{timestamp},{latency:.4f}\n')


def test_classifier_on_unseen_neutral_paths():
    """Exercise unseen traces whose paths do not disclose their expected labels."""
    rng = np.random.default_rng(8675309)
    sample_count = 1024
    timestamps = np.arange(sample_count)

    with tempfile.TemporaryDirectory(prefix='trace_inputs_') as trace_dir:
        cases = []
        for _ in range(16):
            clean = rng.lognormal(mean=2.0, sigma=0.5, size=sample_count)
            clean_path = os.path.join(trace_dir, f'{uuid.uuid4().hex}.csv')
            write_trace(clean_path, clean)
            cases.append((clean_path, 'CLEAN'))

            noise = rng.lognormal(mean=2.0, sigma=0.5, size=sample_count)
            phase = rng.uniform(0.0, 2.0 * np.pi)
            artifact = 15.0 * np.sin(2.0 * np.pi * 50 * timestamps / sample_count + phase)
            synthetic = noise + artifact + 20.0
            synthetic_path = os.path.join(trace_dir, f'{uuid.uuid4().hex}.csv')
            write_trace(synthetic_path, synthetic)
            cases.append((synthetic_path, 'EVIL'))

        rng.shuffle(cases)
        failures = []
        for path, expected in cases:
            actual = run_classifier(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))

        assert not failures, 'Unseen trace classification failures: ' + repr(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
