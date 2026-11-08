#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import struct
import subprocess

ANALYZE = "/home/user/analyze"
CSV_PATH = "/home/user/measurements.csv"
REPORT_PATH = "/home/user/report.txt"

ORIGINAL_CSV = """machine_id,measurement,flag
1,10.5,VALID
2,20.1,VALID
,15.0,VALID
1,11.2,VALID
1,9.8,INVALID
2,22.4,VALID
1,10.8,VALID
2,19.5,VALID
1,11.5,VALID
2,21.0,VALID
,12.0,VALID
1,10.1,VALID
"""

CI_HELPER_SOURCE = r'''
#include <stdio.h>
#include <stdlib.h>

static int compare_doubles(const void *a, const void *b) {
    double x = *(const double *)a;
    double y = *(const double *)b;
    return (x > y) - (x < y);
}

int main(int argc, char **argv) {
    int n = argc - 1;
    if (n <= 0) return 2;
    double *vals = malloc((size_t)n * sizeof(double));
    double *means = malloc(10000 * sizeof(double));
    if (!vals || !means) return 3;
    for (int i = 0; i < n; i++) vals[i] = strtod(argv[i + 1], NULL);
    srand(42);
    for (int i = 0; i < 10000; i++) {
        double sum = 0.0;
        for (int j = 0; j < n; j++) sum += vals[rand() % n];
        means[i] = sum / n;
    }
    qsort(means, 10000, sizeof(double), compare_doubles);
    printf("%.4f\n%.4f\n", means[250], means[9750]);
    free(vals);
    free(means);
    return 0;
}
'''


def build_ci_helper():
    source = "/tmp/test_calc_ci.c"
    executable = "/tmp/test_calc_ci"
    with open(source, "w") as f:
        f.write(CI_HELPER_SOURCE)
    subprocess.run(["gcc", source, "-O2", "-o", executable], check=True)
    return executable


def get_expected_ci(helper, values):
    result = subprocess.run(
        [helper] + [repr(v) for v in values],
        capture_output=True,
        text=True,
        check=True,
    )
    lines = result.stdout.strip().splitlines()
    assert len(lines) == 2
    return lines[0], lines[1]


def read_original_style_lines():
    assert os.path.isfile(REPORT_PATH), f"Output file {REPORT_PATH} was not created."
    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()
    lines = [line.strip() for line in content.split("\n") if line.strip()]
    assert len(lines) == 4, f"Expected exactly 4 lines in {REPORT_PATH}, found {len(lines)}."
    return lines


def assert_original_report(helper):
    lines = read_original_style_lines()
    assert lines[0] == "Mean 1: 10.8200", f"Expected 'Mean 1: 10.8200', got '{lines[0]}'"
    assert lines[1] == "Mean 2: 20.7500", f"Expected 'Mean 2: 20.7500', got '{lines[1]}'"
    expected_lower, expected_upper = get_expected_ci(helper, [10.5, 11.2, 10.8, 11.5, 10.1])
    assert lines[2] == f"CI 1 Lower: {expected_lower}", f"Expected 'CI 1 Lower: {expected_lower}', got '{lines[2]}'"
    assert lines[3] == f"CI 1 Upper: {expected_upper}", f"Expected 'CI 1 Upper: {expected_upper}', got '{lines[3]}'"


def assert_native_executable():
    assert os.path.isfile(ANALYZE), f"Required executable {ANALYZE} does not exist."
    mode = os.stat(ANALYZE).st_mode
    assert stat.S_ISREG(mode), f"{ANALYZE} is not a regular file."
    assert mode & 0o111 and os.access(ANALYZE, os.X_OK), f"{ANALYZE} is not executable."
    with open(ANALYZE, "rb") as f:
        header = f.read(20)
    assert len(header) >= 18 and header[:4] == b"\x7fELF", f"{ANALYZE} is not an ELF executable."
    endian = "<" if header[5] == 1 else ">" if header[5] == 2 else None
    assert endian is not None, "Invalid ELF byte order."
    elf_type = struct.unpack(endian + "H", header[16:18])[0]
    assert elf_type in (2, 3), f"{ANALYZE} is not an executable ELF image."


def run_and_check(csv_text, values1, values2, helper):
    with open(CSV_PATH, "w") as f:
        f.write(csv_text)
    if os.path.exists(REPORT_PATH):
        os.unlink(REPORT_PATH)

    result = subprocess.run(
        [ANALYZE], cwd="/home/user", capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{ANALYZE} exited with status {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), "Executing analyze did not create report.txt."

    lower, upper = get_expected_ci(helper, values1)
    expected = [
        f"Mean 1: {sum(values1) / len(values1):.4f}",
        f"Mean 2: {sum(values2) / len(values2):.4f}",
        f"CI 1 Lower: {lower}",
        f"CI 1 Upper: {upper}",
    ]
    with open(REPORT_PATH, "r") as f:
        actual = f.read().strip().splitlines()
    assert actual == expected, f"For the supplied CSV, expected {expected}, got {actual}"


def test_complete_c_pipeline():
    helper = build_ci_helper()

    # Preserve the original fixed-fixture assertions on the report produced by the agent.
    assert_original_report(helper)
    assert_native_executable()

    # Remove the report and execute the artifact on the original input, proving it creates it.
    run_and_check(
        ORIGINAL_CSV,
        [10.5, 11.2, 10.8, 11.5, 10.1],
        [20.1, 22.4, 19.5, 21.0],
        helper,
    )
    assert_original_report(helper)

    fixture_one = """machine_id,measurement,flag
1,1.25,VALID
2,100.0,VALID
,1.0,VALID
1,2.75,VALID
1,50.0,INVALID
2,104.0,VALID
1,4.5,VALID
3,900.0,VALID
2,108.0,VALID
1,8.0,VALID
2,-999.0,valid
1,700.0,VALID 
"""
    run_and_check(fixture_one, [1.25, 2.75, 4.5, 8.0], [100.0, 104.0, 108.0], helper)

    fixture_two = """machine_id,measurement,flag
1,-3.5,VALID
2,0.25,VALID
1,12.125,VALID
,5000.0,VALID
2,1.75,VALID
1,6.0,VALID
1,100.0,VALIDX
2,-2.0,VALID
1,0.5,VALID
4,800.0,VALID
1,9.875,VALID
2,5.0,VALID
2,900.0,INVALID
"""
    run_and_check(fixture_two, [-3.5, 12.125, 6.0, 0.5, 9.875], [0.25, 1.75, -2.0, 5.0], helper)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
