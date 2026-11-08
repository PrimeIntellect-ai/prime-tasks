#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest

PROFILER = "/home/user/seq_profiler"
FILTER = "/home/user/filter.sh"

REFERENCE_SOURCE = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[256];
    double sum = 0.0;
    int count = 0;

    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '>') continue; // Skip FASTA header
        for (int i = 0; i < strlen(line); i++) {
            if (line[i] == 'A') { sum += 10.5; count++; }
            if (line[i] == 'C') { sum += 20.2; count++; }
            if (line[i] == 'G') { sum += 30.1; count++; }
            if (line[i] == 'T') { sum += 5.5; count++; }
            if (line[i] == 'X') { sum += INFINITY; count++; } // Triggers INF
            if (line[i] == 'Z') { sum += NAN; count++; } // Triggers NAN
        }
    }
    fclose(f);

    if (count == 0) {
        printf("Variance: NaN\n");
        return 0;
    }

    double mean = sum / count;
    // Dummy variance calculation that easily scales with sequence length
    double variance = mean * count * 1.5;

    printf("Variance: %f\n", variance);
    return 0;
}
'''


@pytest.fixture(scope="session")
def trusted_profiler(tmp_path_factory):
    build_dir = tmp_path_factory.mktemp("trusted_build")
    source = build_dir / "seq_profiler.c"
    executable = build_dir / "seq_profiler"
    source.write_text(REFERENCE_SOURCE)
    subprocess.run(
        ["gcc", "-O2", str(source), "-o", str(executable), "-lm"],
        check=True,
        capture_output=True,
    )
    return str(executable)


def run_filter(path):
    return subprocess.run(
        ["bash", FILTER, path], capture_output=True, text=True, timeout=10
    )


def expected_from_reference(reference, path):
    result = subprocess.run(
        [reference, path], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0
    fields = result.stdout.strip().split()
    assert len(fields) == 2 and fields[0] == "Variance:"
    value = float(fields[1])
    return 0 if math.isfinite(value) and value <= 450.0 else 1


def test_compiled_profiler_exists():
    assert os.path.isfile(PROFILER), f"Compiled profiler not found at {PROFILER}."
    assert os.access(PROFILER, os.X_OK), f"Compiled profiler at {PROFILER} is not executable."


def test_profiler_is_requested_gcc_build(trusted_profiler):
    with open(PROFILER, "rb") as submitted, open(trusted_profiler, "rb") as trusted:
        assert submitted.read() == trusted.read(), (
            "seq_profiler is not the GCC -O2, -lm build of the supplied source"
        )


def test_filter_script_exists():
    assert os.path.isfile(FILTER), f"Filter script not found at {FILTER}."
    assert os.access(FILTER, os.X_OK) or os.access(FILTER, os.R_OK), (
        f"Filter script at {FILTER} is not readable/executable."
    )


def test_clean_corpus_accepted():
    clean_dir = "/app/corpus/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}."

    failed_files = []
    for filepath in clean_files:
        result = run_filter(filepath)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected "
            f"(modified/failed): {', '.join(failed_files)}"
        )


def test_evil_corpus_rejected():
    evil_dir = "/app/corpus/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*"))
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}."

    failed_files = []
    for filepath in evil_files:
        result = run_filter(filepath)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(evil_files)} evil files bypassed the filter "
            f"(accepted when they should be rejected): {', '.join(failed_files)}"
        )


def test_randomized_hidden_fasta_inputs(trusted_profiler, tmp_path):
    sequences = [
        "A", "C", "G", "T", "ACGT", "G" * 9, "G" * 10,
        "A" * 28, "A" * 29, "ACGT" * 7, "ACGT" * 8,
        "X", "ACGTX", "Z", "ACGTZ", "", "NNNN",
        "TGCA" * 3, "C" * 14, "C" * 15,
    ]

    for sequence in sequences:
        path = tmp_path / f"sample_{uuid.uuid4().hex}.fa"
        path.write_text(f">random_{uuid.uuid4().hex}\n{sequence}\n")
        expected = expected_from_reference(trusted_profiler, str(path))
        result = run_filter(str(path))
        assert result.returncode == expected, (
            f"Incorrect result for randomized FASTA; expected exit {expected}, "
            f"got {result.returncode}. stdout={result.stdout!r} stderr={result.stderr!r}"
        )


def test_filter_invokes_profiler_and_parses_its_metric(tmp_path):
    backup = tmp_path / "submitted_profiler.backup"
    shutil.copy2(PROFILER, backup)

    cases = [
        ("0", 0),
        ("449.999999", 0),
        ("450.0", 0),
        ("450.000001", 1),
        ("900.5", 1),
        ("NaN", 1),
        ("Inf", 1),
        ("-Inf", 1),
    ]

    try:
        for metric, expected in cases:
            marker = tmp_path / f"called_{uuid.uuid4().hex}"
            fasta = tmp_path / f"input_{uuid.uuid4().hex}.fasta"
            fasta.write_text(f">neutral_{uuid.uuid4().hex}\nA\n")

            wrapper = (
                "#!/bin/bash\n"
                f"printf '%s\\n' \"$#\" \"$1\" > {str(marker)!r}\n"
                f"printf 'Variance: %s\\n' {metric!r}\n"
            )
            with open(PROFILER, "w") as handle:
                handle.write(wrapper)
            os.chmod(PROFILER, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                              stat.S_IRGRP | stat.S_IXGRP |
                              stat.S_IROTH | stat.S_IXOTH)

            result = run_filter(str(fasta))
            assert marker.is_file(), "filter.sh did not execute /home/user/seq_profiler"
            marker_lines = marker.read_text().splitlines()
            assert marker_lines == ["1", str(fasta)], (
                "filter.sh did not pass exactly the supplied FASTA path to seq_profiler"
            )
            assert result.returncode == expected, (
                f"Profiler metric {metric!r} should produce exit {expected}, "
                f"but filter returned {result.returncode}"
            )
    finally:
        shutil.copy2(backup, PROFILER)
        os.chmod(PROFILER, os.stat(backup).st_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
