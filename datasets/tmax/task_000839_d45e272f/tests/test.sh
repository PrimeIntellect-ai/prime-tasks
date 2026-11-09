#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

import numpy as np

PROGRAM = "/home/user/filter.go"
FS = 2000.0
FC = 500.0
LINE_RE = re.compile(r"^(ACCEPT|REJECT) ([^\s]+\.csv)$")


def run_filter(directory):
    result = subprocess.run(
        ["go", "run", PROGRAM, directory],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Go program failed for {directory}. Stderr: {result.stderr}"
    )
    return result


def assert_exact_output(result, expected):
    lines = result.stdout.splitlines()
    assert len(lines) == len(expected), (
        f"Expected exactly {len(expected)} output lines, got {len(lines)}. "
        f"Stdout: {result.stdout!r}"
    )

    actual = {}
    for line in lines:
        match = LINE_RE.fullmatch(line)
        assert match is not None, f"Invalid or unrelated output line: {line!r}"
        status, filename = match.groups()
        assert filename not in actual, f"Duplicate output for {filename}"
        actual[filename] = status

    assert set(actual) == set(expected), (
        f"Output filenames differ. Expected {sorted(expected)}, got {sorted(actual)}"
    )
    assert actual == expected, f"Wrong classifications: expected {expected}, got {actual}"


def test_filter_go_exists():
    assert os.path.isfile(PROGRAM), "The Go program /home/user/filter.go does not exist."


def test_clean_corpus_accepted():
    clean_dir = "/app/corpus/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} not found."
    csv_files = sorted(f for f in os.listdir(clean_dir) if f.endswith(".csv"))
    assert csv_files, f"No CSV files found in {clean_dir}."

    result = run_filter(clean_dir)
    expected = {filename: "ACCEPT" for filename in csv_files}
    assert_exact_output(result, expected)

    rejected_files = [f for f, status in expected.items() if status == "REJECT"]
    missing_accepted = [f for f in csv_files if expected.get(f) != "ACCEPT"]
    assert not rejected_files and not missing_accepted


def test_evil_corpus_rejected():
    evil_dir = "/app/corpus/evil/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} not found."
    csv_files = sorted(f for f in os.listdir(evil_dir) if f.endswith(".csv"))
    assert csv_files, f"No CSV files found in {evil_dir}."

    result = run_filter(evil_dir)
    expected = {filename: "REJECT" for filename in csv_files}
    assert_exact_output(result, expected)

    accepted_files = [f for f, status in expected.items() if status == "ACCEPT"]
    missing_rejected = [f for f in csv_files if expected.get(f) != "REJECT"]
    assert not accepted_files and not missing_rejected


def spectral_label(values):
    spectrum = np.fft.fft(values)
    frequencies = np.fft.fftfreq(len(values), d=1.0 / FS)
    energy = np.abs(spectrum) ** 2
    total = float(np.sum(energy))
    high = float(np.sum(energy[np.abs(frequencies) > 1.2 * FC]))
    return "REJECT" if high / total > 0.15 else "ACCEPT"


def test_content_driven_randomized_corpus_and_exact_output():
    # N=400 gives exact 5 Hz DFT bins, including bins immediately around the
    # strict 600 Hz cutoff. Random names and phases prevent path/name labeling.
    n = 400
    times = np.arange(n, dtype=float) / FS
    rng = np.random.default_rng(secrets.randbits(64))
    cases = [
        [(100.0, 1.0)],
        [(500.0, 1.0)],
        [(595.0, 1.0)],
        [(600.0, 1.0)],
        [(605.0, 1.0)],
        [(900.0, 1.0)],
        [(500.0, 1.0), (800.0, 0.38)],
        [(500.0, 1.0), (800.0, 0.48)],
        [(250.0, 0.7), (550.0, 0.5), (750.0, 0.2)],
        [(250.0, 0.7), (550.0, 0.3), (750.0, 0.7)],
    ]

    with tempfile.TemporaryDirectory(prefix=secrets.token_hex(8) + "_") as directory:
        expected = {}
        for components in cases:
            values = np.zeros(n, dtype=float)
            for frequency, amplitude in components:
                phase = rng.uniform(0.0, 2.0 * np.pi)
                values += amplitude * np.sin(2.0 * np.pi * frequency * times + phase)

            filename = secrets.token_hex(10) + ".csv"
            path = os.path.join(directory, filename)
            np.savetxt(path, np.column_stack((times, values)), delimiter=",", fmt="%.12f")

            # Derive the answer from the actual serialized input rather than a
            # directory name or a preassigned clean/evil label.
            serialized_values = np.loadtxt(path, delimiter=",", usecols=1)
            expected[filename] = spectral_label(serialized_values)

        assert "ACCEPT" in expected.values() and "REJECT" in expected.values()
        with open(os.path.join(directory, "unrelated.txt"), "w", encoding="utf-8") as handle:
            handle.write("This file must not produce an output line.\n")

        result = run_filter(directory)
        assert_exact_output(result, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
