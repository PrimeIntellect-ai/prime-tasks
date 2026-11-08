#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess

C_FILE = "/home/user/root_finder.c"
SH_FILE = "/home/user/build_and_run.sh"
CSV_FILE = "/home/user/roots.csv"
TARGETS = [i / 10.0 for i in range(1, 9)]


def strip_c_comments_and_strings(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    text = re.sub(r"'(?:\\.|[^'\\])*'", "''", text)
    return text


def read_and_validate_csv():
    assert os.path.isfile(CSV_FILE), f"{CSV_FILE} does not exist. Did you run the bash script?"
    with open(CSV_FILE, "r", newline="") as f:
        raw_lines = f.read().splitlines()

    assert len(raw_lines) == 8, f"Expected 8 rows in {CSV_FILE}, but found {len(raw_lines)}."
    line_re = re.compile(r"^[0-9]+\.[0-9]{6},-?[0-9]+\.[0-9]{6}$")
    for i, line in enumerate(raw_lines):
        assert line_re.fullmatch(line), f"Row {i+1} is not formatted as two numbers with exactly 6 decimal places."

    rows = list(csv.reader(raw_lines))
    for i, row in enumerate(rows):
        assert len(row) == 2, f"Row {i+1} does not have exactly 2 columns."
        c_val, x_val = map(float, row)
        expected_c = TARGETS[i]
        assert math.isclose(c_val, expected_c, abs_tol=1e-5), \
            f"Row {i+1}: Expected C_i ≈ {expected_c}, got {c_val}."
        # The integral has the independent closed-form identity
        # integral_0^x exp(-t^2)dt = sqrt(pi)/2 * erf(x).
        residual = abs((math.sqrt(math.pi) / 2.0) * math.erf(x_val) - expected_c)
        assert residual < 8e-7, \
            f"Row {i+1}: x={x_val} does not solve the stated equation (residual {residual})."


def test_c_source_file():
    """Check that root_finder.c exists and contains the required implementation."""
    assert os.path.exists(C_FILE), f"{C_FILE} does not exist."
    with open(C_FILE, "r") as f:
        content = f.read()

    # Preserve the original OpenMP assertion.
    assert "#pragma omp parallel for" in content, \
        "The C code must contain '#pragma omp parallel for' to parallelize the loop."

    code = strip_c_comments_and_strings(content)
    assert re.search(r"#\s*include\s*<omp\.h>", code), "The C source must include <omp.h>."
    assert re.search(r"#\s*include\s*<math\.h>", code), "The C source must include <math.h>."
    assert re.search(r"\b1000\b", code), "Composite Simpson integration must use N = 1000 intervals."
    assert re.search(r"%\s*2", code), "The Simpson implementation must distinguish odd and even points."
    assert re.search(r"(?:/\s*3(?:\.0*)?\b|1(?:\.0*)?\s*/\s*3(?:\.0*)?)", code), \
        "The Simpson 1/3 scaling is missing."
    assert re.search(r"\bexp\s*\(", code), "The integrand and derivative must use exp()."
    assert re.search(r"\bfabs\s*\(", code), "Newton convergence must test the absolute residual."
    assert re.search(r"(?:1(?:\.0*)?[eE]-7|0\.0*1\b)", code), "The 1e-7 stopping tolerance is missing."
    assert re.search(r"\b100\b", code), "The Newton iteration limit of 100 is missing."
    assert re.search(r"\b[A-Za-z_]\w*\s*=\s*1(?:\.0*)?\s*;", code), \
        "Each Newton solve must start with x = 1.0."
    newton_update = (
        re.search(r"\b([A-Za-z_]\w*)\s*-\s*=\s*[^;]+/[^;]+;", code) or
        re.search(r"\b([A-Za-z_]\w*)\s*=\s*\1\s*-\s*[^;]+/[^;]+;", code)
    )
    assert newton_update, "A Newton-Raphson update of the form x = x - F/F' is missing."


def test_bash_script():
    """Check and actually execute build_and_run.sh."""
    assert os.path.exists(SH_FILE), f"{SH_FILE} does not exist."
    with open(SH_FILE, "r") as f:
        script = f.read()
    uncommented = re.sub(r"(?m)^\s*#.*$", "", script)
    for token in ("gcc", "-fopenmp", "-lm", "-O3", "root_finder.c"):
        assert token in uncommented, f"The build script must use {token}."

    try:
        os.remove(CSV_FILE)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        ["bash", SH_FILE], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, \
        f"build_and_run.sh failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    read_and_validate_csv()


def test_csv_output():
    """Check that roots.csv exists, is ordered, formatted, and mathematically correct."""
    read_and_validate_csv()


def test_source_compiles_runs_and_enters_openmp_region():
    """Independently compile the submitted source and observe an executed GOMP region."""
    binary = "/tmp/root_finder_verified"
    marker = "/tmp/openmp_region_entered"
    hook_c = "/tmp/gomp_hook.c"
    hook_so = "/tmp/gomp_hook.so"

    compile_result = subprocess.run(
        ["gcc", "-O3", "-fopenmp", C_FILE, "-lm", "-o", binary],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, f"Independent compilation failed:\n{compile_result.stderr}"

    symbols = subprocess.run(["nm", "-D", binary], text=True, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, timeout=10)
    assert "GOMP_parallel" in symbols.stdout, \
        "The compiled program contains no OpenMP parallel region."

    hook_source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
typedef void (*gomp_fn)(void (*)(void *), void *, unsigned, unsigned);
void GOMP_parallel(void (*fn)(void *), void *data, unsigned threads, unsigned flags) {
    int fd = open("/tmp/openmp_region_entered", O_WRONLY|O_CREAT|O_APPEND, 0600);
    if (fd >= 0) { write(fd, "1", 1); close(fd); }
    static gomp_fn real_fn;
    if (!real_fn) real_fn = (gomp_fn)dlsym(RTLD_NEXT, "GOMP_parallel");
    real_fn(fn, data, threads, flags);
}
'''
    with open(hook_c, "w") as f:
        f.write(hook_source)
    hook_result = subprocess.run(
        ["gcc", "-shared", "-fPIC", hook_c, "-ldl", "-o", hook_so],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert hook_result.returncode == 0, f"Could not build OpenMP runtime monitor:\n{hook_result.stderr}"

    try:
        os.remove(marker)
    except FileNotFoundError:
        pass
    try:
        os.remove(CSV_FILE)
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env.update({"OMP_NUM_THREADS": "4", "LD_PRELOAD": hook_so})
    run_result = subprocess.run(
        [binary], cwd="/home/user", env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert run_result.returncode == 0, \
        f"Independently compiled program failed:\n{run_result.stderr}"
    assert os.path.exists(marker) and os.path.getsize(marker) > 0, \
        "The program did not execute its OpenMP parallel region."
    read_and_validate_csv()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
