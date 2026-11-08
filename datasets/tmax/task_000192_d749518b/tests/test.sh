#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import stat
import subprocess

SOURCE = "/home/user/regression.cpp"
EXECUTABLE = "/home/user/regression_fixed"
OUTPUT = "/home/user/output.txt"
REFERENCE = "/home/user/reference.txt"
EXPECTED_OUTPUT = b"3.14159,2.71828\n"

ORIGINAL_SOURCE = r'''#include <iostream>
#include <vector>
#include <iomanip>
#include <omp.h>

int main() {
    int N = 20000000;
    std::vector<double> x(N), y(N);

    // Deterministic data generation
    for(int i=0; i<N; ++i) { 
        x[i] = i * 0.0001; 
        y[i] = 3.14159 * x[i] + 2.71828; 
    }

    double sum_x = 0, sum_y = 0, sum_xy = 0, sum_x2 = 0;

    #pragma omp parallel for schedule(dynamic, 1000)
    for(int i=0; i<N; ++i) {
        #pragma omp atomic
        sum_x += x[i];
        #pragma omp atomic
        sum_y += y[i];
        #pragma omp atomic
        sum_xy += x[i] * y[i];
        #pragma omp atomic
        sum_x2 += x[i] * x[i];
    }

    double denom = (N * sum_x2 - sum_x * sum_x);
    double m = (N * sum_xy - sum_x * sum_y) / denom;
    double c = (sum_y - m * sum_x) / N;

    std::cout << std::fixed << std::setprecision(5) << m << "," << c << "\n";
    return 0;
}
'''

def strip_cpp_comments(text):
    pattern = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', re.S)
    def replace(match):
        token = match.group(0)
        if token.startswith('//') or token.startswith('/*'):
            return ''.join('\n' if c == '\n' else ' ' for c in token)
        return token
    return pattern.sub(replace, text)

def core_without_omp_pragmas(text):
    text = strip_cpp_comments(text)
    lines = [line for line in text.splitlines()
             if not re.match(r'^\s*#\s*pragma\s+omp\b', line)]
    return re.sub(r'\s+', '', '\n'.join(lines))

def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def test_regression_cpp_fixed():
    assert os.path.exists(SOURCE), f"File {SOURCE} does not exist."
    with open(SOURCE, 'r') as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "#pragma omp atomic" not in content, f"File {SOURCE} still contains '#pragma omp atomic'."
    assert "schedule(dynamic, 1000)" not in content, f"File {SOURCE} still contains 'schedule(dynamic, 1000)'."
    assert "reduction" in content, f"File {SOURCE} does not contain a 'reduction' clause."
    assert all(name in content for name in ("sum_x", "sum_y", "sum_xy", "sum_x2")), \
        f"File {SOURCE} reduction clause might be missing variables."

    uncommented = strip_cpp_comments(content)
    pragmas = re.findall(r'^\s*#\s*pragma\s+omp\s+parallel\s+for\b([^\n]*)$', uncommented, re.M)
    assert len(pragmas) == 1, "Expected exactly one active OpenMP parallel-for directive."
    clause = pragmas[0]
    assert not re.search(r'\bschedule\s*\(', clause), "The parallel loop must use the default static schedule."
    reduction = re.search(r'\breduction\s*\(\s*\+\s*:\s*([^)]*)\)', clause)
    assert reduction, "The parallel-for directive lacks an active addition reduction clause."
    variables = {v.strip() for v in reduction.group(1).split(',') if v.strip()}
    assert variables == {"sum_x", "sum_y", "sum_xy", "sum_x2"}, \
        "The reduction clause must include all four regression sums."
    assert not re.search(r'^\s*#\s*pragma\s+omp\s+atomic\b', uncommented, re.M), \
        "An active OpenMP atomic directive remains."

    # Only OpenMP directives may change; data generation and regression math must remain intact.
    assert core_without_omp_pragmas(content) == core_without_omp_pragmas(ORIGINAL_SOURCE), \
        "Data generation or core regression logic was changed."

def test_executable_exists_and_runnable():
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a file."
    st = os.stat(EXECUTABLE)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), \
        f"File {EXECUTABLE} is not executable."

    # Rebuild independently with the required compiler flags. A matching deterministic
    # binary confirms that regression_fixed was produced from this source and flags.
    rebuilt = "/tmp/regression_fixed_verified"
    subprocess.run(
        ["g++", "-fopenmp", "-O2", SOURCE, "-o", rebuilt],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    assert sha256(EXECUTABLE) == sha256(rebuilt), \
        "regression_fixed does not match a g++ -fopenmp -O2 build of regression.cpp."

    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "4"
    env["OMP_DYNAMIC"] = "FALSE"
    env["OMP_THREAD_LIMIT"] = "4"

    runs = []
    for _ in range(3):
        result = subprocess.run(
            [EXECUTABLE], env=env, check=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=120)
        assert result.stderr == b"", "The executable produced unexpected standard error."
        runs.append(result.stdout)
    assert runs[0] == runs[1] == runs[2], "Output is not reproducible across 4-thread runs."
    assert runs[0] == EXPECTED_OUTPUT, f"Unexpected executable output: {runs[0]!r}"

def test_output_txt_content():
    assert os.path.exists(OUTPUT), f"File {OUTPUT} does not exist."
    with open(OUTPUT, 'rb') as f:
        content = f.read()

    # Preserve the original exact-value assertion and additionally require exact stdout bytes.
    assert content.strip().decode() == "3.14159,2.71828", \
        f"File {OUTPUT} contains {content!r}, expected '3.14159,2.71828'."
    assert content == EXPECTED_OUTPUT, "output.txt is not the exact standard output line."

    with open(REFERENCE, 'rb') as f:
        reference = f.read()
    assert reference == EXPECTED_OUTPUT, "reference.txt does not contain the supplied reference value."

    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "4"
    env["OMP_DYNAMIC"] = "FALSE"
    env["OMP_THREAD_LIMIT"] = "4"
    actual = subprocess.run(
        [EXECUTABLE], env=env, check=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=120).stdout
    assert content == actual == reference, \
        "output.txt must exactly equal the 4-thread executable output and reference."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
