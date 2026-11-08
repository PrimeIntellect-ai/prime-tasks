#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import subprocess
import tempfile
import uuid

import pytest

LIBDIR = "/app/vendored/libstatscsv-1.0"
LIB = os.path.join(LIBDIR, "libstatscsv.a")
SOURCE = "/home/user/detector.c"
DETECTOR = "/home/user/detector"


def command(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, timeout=20, **kwargs)


def detector_exit(executable, csv_path):
    try:
        return subprocess.run(
            [executable, csv_path], capture_output=True, timeout=8
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on {csv_path}")


def write_csv(path, scores):
    with open(path, "w", encoding="utf-8", newline="") as stream:
        stream.write("id,score\n")
        for index, score in enumerate(scores):
            stream.write(f"{index},{score}\n")


def test_vendored_library_built_and_valid():
    """Verify that the repaired vendored library can be rebuilt and used."""
    assert os.path.isfile(LIB), (
        f"Vendored library {LIB} was not built. Did you fix the compilation errors and run make?"
    )

    rebuilt = command(["make", "clean"], cwd=LIBDIR)
    assert rebuilt.returncode == 0, rebuilt.stdout + rebuilt.stderr
    rebuilt = command(["make"], cwd=LIBDIR)
    assert rebuilt.returncode == 0, rebuilt.stdout + rebuilt.stderr
    assert os.path.isfile(LIB), "make did not produce libstatscsv.a"

    archive = command(["ar", "t", LIB])
    assert archive.returncode == 0 and archive.stdout.strip(), "libstatscsv.a is not a valid nonempty archive"
    symbols = command(["nm", "-g", LIB])
    assert symbols.returncode == 0, symbols.stdout + symbols.stderr
    assert re.search(r"\bparse_csv_row$", symbols.stdout, re.MULTILINE), "Library lacks parse_csv_row"
    assert re.search(r"\bfree_csv_row$", symbols.stdout, re.MULTILINE), "Library lacks free_csv_row"

    with tempfile.TemporaryDirectory(prefix="libcheck-") as directory:
        probe_source = os.path.join(directory, "probe.c")
        probe_binary = os.path.join(directory, "probe")
        with open(probe_source, "w", encoding="utf-8") as stream:
            stream.write(r'''#include "statscsv.h"
#include <string.h>
int main(void) {
    CSVRow *r = parse_csv_row("alpha,beta,gamma");
    if (!r || r->count != 3 || strcmp(r->tokens[1], "beta") != 0) return 2;
    free_csv_row(r);
    return 0;
}
''')
        built = command([
            "gcc", "-std=c11", "-I", LIBDIR, probe_source, LIB, "-o", probe_binary
        ])
        assert built.returncode == 0, built.stdout + built.stderr
        result = command([probe_binary])
        assert result.returncode == 0, "The rebuilt tokenization library does not work"


def test_detector_executable_exists_and_is_c_linked_to_library():
    """Verify the requested C source and executable, including library use."""
    assert os.path.isfile(SOURCE), f"Detector C source {SOURCE} is missing."
    assert os.path.isfile(DETECTOR), f"Detector executable {DETECTOR} is missing."
    assert os.access(DETECTOR, os.X_OK), f"Detector {DETECTOR} is not executable."
    with open(DETECTOR, "rb") as stream:
        assert stream.read(4) == b"\x7fELF", "detector is not a compiled ELF executable"

    with open(SOURCE, "r", encoding="utf-8", errors="replace") as stream:
        source_text = stream.read()
    assert re.search(r"\bparse_csv_row\s*\(", source_text), (
        "detector.c does not use the vendored tokenization primitive parse_csv_row"
    )
    assert re.search(r"\b1000\b", source_text), (
        "detector.c does not contain the required 1000-resample bootstrap implementation"
    )

    symbols = command(["nm", DETECTOR])
    assert symbols.returncode == 0, symbols.stdout + symbols.stderr
    assert re.search(r"\bparse_csv_row$", symbols.stdout, re.MULTILINE), (
        "detector is not linked with the vendored parse_csv_row implementation"
    )


def test_adversarial_corpus():
    """Preserve the original corpus assertions, with exact required exit codes."""
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".csv")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".csv")]

    assert clean_files, f"No clean files found in {clean_dir}."
    assert evil_files, f"No evil files found in {evil_dir}."

    clean_modified = [os.path.basename(p) for p in clean_files if detector_exit(DETECTOR, p) != 0]
    evil_bypassed = [os.path.basename(p) for p in evil_files if detector_exit(DETECTOR, p) != 1]
    errors = []
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil files did not return exactly 1: "
            + ", ".join(evil_bypassed)
        )
    if clean_modified:
        errors.append(
            f"{len(clean_modified)} of {len(clean_files)} clean files did not return 0: "
            + ", ".join(clean_modified)
        )
    if errors:
        pytest.fail(" | ".join(errors))


def test_hidden_randomized_inputs_and_fresh_source_build():
    """Exercise content-based behavior at paths unavailable to the submission."""
    with tempfile.TemporaryDirectory(prefix="csv-evaluation-") as directory:
        fresh_detector = os.path.join(directory, "program-" + uuid.uuid4().hex)
        built = command([
            "gcc", "-std=c11", "-O2", "-I", LIBDIR, SOURCE, LIB, "-lm", "-o", fresh_detector
        ])
        assert built.returncode == 0, "detector.c cannot be freshly compiled:\n" + built.stdout + built.stderr

        symbols = command(["nm", fresh_detector])
        assert symbols.returncode == 0
        assert re.search(r"\bparse_csv_row$", symbols.stdout, re.MULTILINE), (
            "A fresh build of detector.c does not link/use parse_csv_row"
        )

        cases = [
            (0, [50] * 100),
            (0, [45] * 100),
            (0, [55] * 100),
            (0, [50] * 99 + [100]),
            (1, [44] * 100),
            (1, [56] * 100),
            (1, [10] * 100),
            (1, [90] * 100),
            (1, [0] * 50 + [100] * 50),
            (1, [50] * 49 + ["NaN"] + [50] * 50),
            (1, [50] * 49 + ["N/A"] + [50] * 50),
            (1, [50] * 49 + [""] + [50] * 50),
        ]

        # Include the supplied corpus too, but only after copying it to random,
        # unlabeled paths so classification cannot depend on clean/evil names.
        for subdir, expected in (("clean", 0), ("evil", 1)):
            source_dir = os.path.join("/app/corpus", subdir)
            for filename in os.listdir(source_dir):
                if filename.endswith(".csv"):
                    data = open(os.path.join(source_dir, filename), "r", encoding="utf-8").read()
                    cases.append((expected, data))

        random.SystemRandom().shuffle(cases)
        failures = []
        for expected, payload in cases:
            hidden_dir = os.path.join(directory, uuid.uuid4().hex)
            os.mkdir(hidden_dir)
            path = os.path.join(hidden_dir, uuid.uuid4().hex + ".dat")
            if isinstance(payload, str):
                with open(path, "w", encoding="utf-8", newline="") as stream:
                    stream.write(payload)
            else:
                write_csv(path, payload)

            for executable in (DETECTOR, fresh_detector):
                actual = detector_exit(executable, path)
                if actual != expected:
                    failures.append(
                        f"{os.path.basename(executable)} returned {actual}, expected {expected}, "
                        f"for hidden case {os.path.basename(path)}"
                    )
        assert not failures, "\n".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
