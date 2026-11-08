#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
import pytest

BINARY = "/home/user/filter"
SOURCE = "/home/user/filter.go"
CUTOFF = 485


def run_filter(binary, args):
    return subprocess.run(
        [binary] + args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def test_filter_binary_exists():
    """Ensure the Go program has been compiled and is executable."""
    assert os.path.isfile(BINARY), f"Compiled Go binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Compiled Go binary {BINARY} is not executable."


def test_go_source_exists_and_binary_is_go():
    """Require the requested Go source and verify it builds successfully."""
    assert os.path.isfile(SOURCE), f"Go source {SOURCE} does not exist."
    with tempfile.TemporaryDirectory(prefix="verify_go_") as tmp:
        rebuilt = os.path.join(tmp, "filter-rebuilt")
        build = subprocess.run(
            ["go", "build", "-o", rebuilt, SOURCE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert build.returncode == 0, (
            "filter.go does not compile: " + build.stderr.decode(errors="replace")
        )

    info = subprocess.run(
        ["go", "version", "-m", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert info.returncode == 0, "Installed filter is not a recognizable Go binary."


def test_clean_corpus():
    """Ensure all clean FASTA files are accepted (exit code 0)."""
    clean_dir = "/app/clean"
    assert os.path.isdir(clean_dir), f"Clean directory {clean_dir} is missing."

    failed_files = []
    total_files = 0
    for filename in sorted(os.listdir(clean_dir)):
        filepath = os.path.join(clean_dir, filename)
        if os.path.isfile(filepath):
            total_files += 1
            result = run_filter(BINARY, [filepath])
            if result.returncode != 0:
                failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} of {total_files} clean files rejected (modified/failed). Offending files: {', '.join(failed_files)}"


def test_evil_corpus():
    """Ensure all evil FASTA files are rejected (exit code 1)."""
    evil_dir = "/app/evil"
    assert os.path.isdir(evil_dir), f"Evil directory {evil_dir} is missing."

    failed_files = []
    total_files = 0
    for filename in sorted(os.listdir(evil_dir)):
        filepath = os.path.join(evil_dir, filename)
        if os.path.isfile(filepath):
            total_files += 1
            result = run_filter(BINARY, [filepath])
            if result.returncode != 1:
                failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} of {total_files} evil files bypassed (accepted). Offending files: {', '.join(failed_files)}"


def test_exactly_one_argument():
    """The command must reject invocations with zero or multiple arguments."""
    assert run_filter(BINARY, []).returncode == 1
    assert run_filter(
        BINARY,
        ["/app/clean/file1.fasta", "/app/clean/file2.fasta"],
    ).returncode == 1


def test_generated_fasta_inputs_against_installed_and_source_build():
    """Exercise both artifacts on fresh paths and independently derived answers."""
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="fasta_frequency_verifier_") as tmp:
        rebuilt = os.path.join(tmp, "rebuilt-filter")
        build = subprocess.run(
            ["go", "build", "-o", rebuilt, SOURCE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert build.returncode == 0, build.stderr.decode(errors="replace")

        cases = []
        for index in range(12):
            count = rng.randint(1, 5)
            frequencies = [rng.randint(1, CUTOFF + 140) for _ in range(count)]
            expected = 0 if all(value <= CUTOFF for value in frequencies) else 1
            text = "".join(
                f">Generated_{index}_{j} | Freq: {value} Hz\nACGTACGT\n"
                for j, value in enumerate(frequencies)
            )
            cases.append((text, expected))

        cases.extend([
            (">AtCutoff | Freq: 485 Hz\nACGT\n", 0),
            (">OverCutoff | Freq: 486 Hz\nACGT\n", 1),
            (">First | Freq: 100 Hz\nAAAA\n>Second | Freq: 700 Hz\nCCCC\n", 1),
            (">MissingFrequency\nACGT\n", 1),
            (">BadNumber | Freq: NaN Hz\nACGT\n", 1),
            (">BadUnit | Freq: 300 kHz\nACGT\n", 1),
            (">One | Freq: 200 Hz\nAAAA\n>Missing\nCCCC\n", 1),
        ])

        rng.shuffle(cases)
        misleading_dir = os.path.join(tmp, "not_app", "clean", "evil")
        os.makedirs(misleading_dir)
        for index, (contents, expected) in enumerate(cases):
            path = os.path.join(misleading_dir, f"generated_{rng.randrange(10**9)}_{index}.fasta")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(contents)
            for candidate in (BINARY, rebuilt):
                result = run_filter(candidate, [path])
                assert result.returncode == expected, (
                    f"{candidate} returned {result.returncode}, expected {expected}, "
                    f"for generated FASTA {contents!r}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
