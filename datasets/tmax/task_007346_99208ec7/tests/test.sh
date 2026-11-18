#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
from decimal import Decimal

SOURCE_PATH = "/home/user/signal_processor.c"
EXEC_PATH = "/home/user/signal_processor"
RESULT_PATH = "/home/user/result.txt"
EXPECTED_VALUE = "4702500.000000"

ORIGINAL_WITH_FIXED_DIRECTIVE = '''#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

int main() {
    size_t n = 10000000;
    double *data = malloc(n * sizeof(double));
    if (!data) return 1;

    // Simulate nanopore signal data
    for(size_t i = 0; i < n; i++) {
        data[i] = (double)(i % 100) / 100.0;
    }

    double total_power = 0.0;

    // BUG: Data race in accumulation
    #pragma omp parallel for
    for(size_t i = 0; i < n; i++) {
        double filtered = data[i] * 0.95; // apply scaling filter
        total_power += filtered;          // race condition here!
    }

    printf("%.6f\\n", total_power);

    free(data);
    return 0;
}
'''


def test_source_code_fixed():
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} is missing."

    with open(SOURCE_PATH, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "reduction" in content, "The source code does not contain the 'reduction' clause in the OpenMP directive."

    lines = content.splitlines(keepends=True)
    pragma_indexes = [
        i for i, line in enumerate(lines)
        if re.match(r"^[ \t]*#[ \t]*pragma[ \t]+omp[ \t]+parallel[ \t]+for(?:[ \t].*)?$", line.rstrip("\r\n"))
    ]
    assert len(pragma_indexes) == 1, "Expected exactly one OpenMP parallel-for directive."

    directive = lines[pragma_indexes[0]].rstrip("\r\n")
    assert re.search(r"\breduction\s*\(\s*\+\s*:\s*total_power\s*\)", directive), \
        "The OpenMP parallel-for must use reduction(+:total_power)."

    # The task permits fixing the directive, not changing the computation or sizes.
    normalized = list(lines)
    normalized[pragma_indexes[0]] = "    #pragma omp parallel for\n"
    assert "".join(normalized) == ORIGINAL_WITH_FIXED_DIRECTIVE, \
        "The mathematical logic or array declarations were changed; only the OpenMP directive should be fixed."


def test_executable_exists():
    assert os.path.isfile(EXEC_PATH), f"Executable {EXEC_PATH} is missing. Did you compile the code?"
    assert os.access(EXEC_PATH, os.X_OK), f"File {EXEC_PATH} is not executable."

    with open(EXEC_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted executable is not an ELF binary."

    # Reproduce the required build and require the submitted artifact to match it.
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "signal_processor")
        build = subprocess.run(
            ["gcc", "-O3", "-fopenmp", SOURCE_PATH, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        assert build.returncode == 0, f"The fixed source does not compile with gcc -O3 -fopenmp: {build.stderr.decode(errors='replace')}"
        with open(EXEC_PATH, "rb") as submitted_file, open(rebuilt, "rb") as rebuilt_file:
            assert submitted_file.read() == rebuilt_file.read(), \
                "The executable does not match the source compiled with gcc -O3 -fopenmp."


def test_result_file():
    assert os.path.isfile(RESULT_PATH), f"Result file {RESULT_PATH} is missing. Did you run the program and save the output?"

    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()

    # Preserve the original exact-result assertion.
    assert content == EXPECTED_VALUE, f"Expected result to be {EXPECTED_VALUE}, but got {content}."

    cycle_sum = sum(Decimal(i) / Decimal(100) for i in range(100))
    derived_value = cycle_sum * Decimal("0.95") * Decimal(10000000 // 100)
    assert EXPECTED_VALUE == format(derived_value, ".6f")

    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "4"
    env["OMP_DYNAMIC"] = "FALSE"

    outputs = []
    for _ in range(3):
        run = subprocess.run(
            [EXEC_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=60,
        )
        assert run.returncode == 0, f"Executable failed with status {run.returncode}: {run.stderr.decode(errors='replace')}"
        assert run.stderr == b"", f"Executable wrote unexpected stderr: {run.stderr.decode(errors='replace')}"
        outputs.append(run.stdout)

    assert all(output == outputs[0] for output in outputs), "Executable output is not reproducible across runs."
    assert outputs[0] == (EXPECTED_VALUE + "\n").encode(), \
        f"Running the executable with four threads produced {outputs[0]!r}, not the expected numeric output."

    with open(RESULT_PATH, "rb") as f:
        result_bytes = f.read()
    assert result_bytes == outputs[0], "result.txt is not the actual standard output of the submitted executable."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
