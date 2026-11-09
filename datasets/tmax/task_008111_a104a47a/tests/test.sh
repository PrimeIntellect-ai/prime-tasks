#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile

import numpy as np

HOME = "/home/user"
SEQ_PATH = HOME + "/sequence.txt"
LOG_PATH = HOME + "/results.log"
SRC_PATH = HOME + "/analyze.c"
BIN_PATH = HOME + "/analyze"
PREFIX = HOME + "/fftw_install"


def run(cmd, **kwargs):
    kwargs.setdefault("check", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("stdout", subprocess.PIPE)
    kwargs.setdefault("stderr", subprocess.PIPE)
    kwargs.setdefault("timeout", 120)
    return subprocess.run(cmd, **kwargs)


def compute_truth(seq):
    assert len(seq) == 1024
    mapping = {'A': 1.0, 'C': 2.0, 'G': 3.0, 'T': 4.0}
    assert all(c in mapping for c in seq)
    arr = np.array([mapping[c] for c in seq], dtype=np.float64)

    def get_max_mag(data):
        transformed = np.fft.rfft(data)
        return float(np.max(np.abs(transformed[1:513])))

    m_orig = get_max_mag(arr)
    seed = 42
    k = 0
    for _ in range(1000):
        for i in range(1023, 0, -1):
            seed = (seed * 1103515245 + 12345) & 0x7fffffff
            j = seed % (i + 1)
            arr[i], arr[j] = arr[j], arr[i]
        if get_max_mag(arr) >= m_orig - 1e-9:
            k += 1
    return m_orig, k / 1000.0


def parse_and_check_log(seq):
    assert os.path.isfile(LOG_PATH), f"Results log {LOG_PATH} is missing."
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()

    # Preserve the original format assertion, then enforce that it is the entire output.
    match = re.search(r"Max_Mag:\s*([0-9.]+),\s*P-value:\s*([0-9.]+)", content)
    assert match is not None, f"results.log format is incorrect. Found: '{content}'"
    exact = re.fullmatch(r"Max_Mag:\s*([0-9]+(?:\.[0-9]+)?),\s*P-value:\s*([0-9]+(?:\.[0-9]+)?)", content)
    assert exact is not None, f"results.log contains extra or malformed content: '{content}'"

    expected_m, expected_p = compute_truth(seq)
    actual_m, actual_p = map(float, exact.groups())
    expected_m = round(expected_m, 2)
    expected_p = round(expected_p, 3)
    assert math.isclose(actual_m, expected_m, abs_tol=0.011), \
        f"Expected Max_Mag ~{expected_m}, but got {actual_m}"
    assert math.isclose(actual_p, expected_p, abs_tol=0.0011), \
        f"Expected P-value ~{expected_p}, but got {actual_p}"


def test_fftw_installation():
    lib_dir = PREFIX + "/lib"
    assert os.path.isdir(lib_dir), f"FFTW3 library directory not found at {lib_dir}"
    lib_a = lib_dir + "/libfftw3.a"
    lib_so = lib_dir + "/libfftw3.so"
    assert os.path.isfile(lib_a) or os.path.isfile(lib_so), \
        f"Neither libfftw3.a nor libfftw3.so found in {lib_dir}"
    assert os.path.isfile(PREFIX + "/include/fftw3.h"), "Installed fftw3.h is missing"

    # Prove that the installed files are a usable FFTW implementation, not placeholders.
    probe_c = "/tmp/fftw_probe.c"
    probe_bin = "/tmp/fftw_probe"
    with open(probe_c, "w") as f:
        f.write(r'''#include <math.h>
#include <stdio.h>
#include <string.h>
#include <fftw3.h>
int main(void) {
    double in[8] = {1,2,3,4,5,6,7,8};
    fftw_complex out[5];
    fftw_plan p = fftw_plan_r2c_1d(8, in, out, FFTW_ESTIMATE);
    if (!p) return 2;
    fftw_execute(p);
    fftw_destroy_plan(p);
    if (fabs(out[0][0] - 36.0) > 1e-8 || fabs(out[0][1]) > 1e-8) return 3;
    if (!fftw_version || strstr(fftw_version, "fftw-3.3.10") == NULL) return 4;
    return 0;
}''')
    run(["gcc", probe_c, "-I" + PREFIX + "/include", "-L" + PREFIX + "/lib",
         "-lfftw3", "-lm", "-o", probe_bin])
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = PREFIX + "/lib:" + env.get("LD_LIBRARY_PATH", "")
    run([probe_bin], env=env)


def compile_submission_with_trace():
    assert os.path.isfile(SRC_PATH), f"Source file {SRC_PATH} is missing."
    with open(SRC_PATH, "r", errors="replace") as f:
        source = f.read()
    for token in ("fftw_plan_r2c_1d", "FFTW_ESTIMATE", "1103515245", "12345", "0x7fffffff"):
        assert token in source, f"analyze.c is missing required construct: {token}"

    obj = "/tmp/analyze_submission.o"
    run(["gcc", "-c", SRC_PATH, "-I" + PREFIX + "/include", "-o", obj])
    symbols = run(["nm", obj]).stdout
    assert re.search(r"\bU\s+fftw_plan_r2c_1d\b", symbols), \
        "analyze.c does not actually reference the installed fftw_plan_r2c_1d"
    assert re.search(r"\bU\s+fftw_execute\b", symbols), \
        "analyze.c does not actually reference fftw_execute"

    wrapper = "/tmp/fftw_trace.c"
    with open(wrapper, "w") as f:
        f.write(r'''#include <stdio.h>
#include <stdlib.h>
#include <fftw3.h>
static long plans, executions, bad_plans;
fftw_plan __real_fftw_plan_r2c_1d(int, double *, fftw_complex *, unsigned);
void __real_fftw_execute(const fftw_plan);
fftw_plan __wrap_fftw_plan_r2c_1d(int n, double *in, fftw_complex *out, unsigned flags) {
    plans++;
    if (n != 1024 || !(flags & FFTW_ESTIMATE)) bad_plans++;
    return __real_fftw_plan_r2c_1d(n, in, out, flags);
}
void __wrap_fftw_execute(const fftw_plan p) {
    executions++;
    __real_fftw_execute(p);
}
__attribute__((destructor)) static void save_trace(void) {
    const char *path = getenv("FFTW_TRACE_FILE");
    if (path) {
        FILE *f = fopen(path, "w");
        if (f) { fprintf(f, "%ld %ld %ld\n", plans, executions, bad_plans); fclose(f); }
    }
}
''')
    traced = "/tmp/analyze_verified"
    run(["gcc", SRC_PATH, wrapper, "-I" + PREFIX + "/include", "-L" + PREFIX + "/lib",
         "-Wl,--wrap=fftw_plan_r2c_1d", "-Wl,--wrap=fftw_execute",
         "-lfftw3", "-lm", "-o", traced])
    return traced


def random_sequence():
    return ''.join(secrets.choice("ACGT") for _ in range(1024))


def execute_and_check(binary, seq, trace=False):
    with open(SEQ_PATH, "w") as f:
        f.write(seq)
    if os.path.exists(LOG_PATH):
        os.unlink(LOG_PATH)
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = PREFIX + "/lib:" + env.get("LD_LIBRARY_PATH", "")
    trace_path = "/tmp/fftw_trace.log"
    if trace:
        try:
            os.unlink(trace_path)
        except FileNotFoundError:
            pass
        env["FFTW_TRACE_FILE"] = trace_path
    run([binary], cwd=HOME, env=env)
    parse_and_check_log(seq)
    if trace:
        assert os.path.isfile(trace_path), "No FFTW execution trace was produced"
        with open(trace_path) as f:
            plans, executions, bad_plans = map(int, f.read().split())
        assert plans >= 1, "The analysis did not create an FFTW r2c plan"
        assert bad_plans == 0, "FFTW plans must be length 1024 and use FFTW_ESTIMATE"
        assert executions >= 1001, \
            f"Expected FFTW execution for the original and 1000 simulations, saw {executions}"


def main():
    test_fftw_installation()
    assert os.path.isfile(SRC_PATH), f"Source file {SRC_PATH} is missing."
    assert os.path.isfile(BIN_PATH), f"Compiled program {BIN_PATH} is missing."
    assert os.access(BIN_PATH, os.X_OK), f"{BIN_PATH} is not executable"
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BIN_PATH} is not a compiled ELF executable"

    assert os.path.isfile(SEQ_PATH), f"Sequence file {SEQ_PATH} is missing"
    with open(SEQ_PATH) as f:
        initial_seq = f.read().strip()
    assert initial_seq == "ACGTAACG" * 128, "The supplied sequence.txt was altered"
    parse_and_check_log(initial_seq)

    saved_sequence = open(SEQ_PATH, "rb").read()
    saved_log = open(LOG_PATH, "rb").read() if os.path.exists(LOG_PATH) else None
    try:
        # Execute the submitted artifact itself on an unpredictable input.
        execute_and_check(BIN_PATH, random_sequence(), trace=False)

        # Rebuild analyze.c with the required local installation and instrument real FFTW calls.
        traced_binary = compile_submission_with_trace()
        execute_and_check(traced_binary, random_sequence(), trace=True)
    finally:
        with open(SEQ_PATH, "wb") as f:
            f.write(saved_sequence)
        if saved_log is None:
            try:
                os.unlink(LOG_PATH)
            except FileNotFoundError:
                pass
        else:
            with open(LOG_PATH, "wb") as f:
                f.write(saved_log)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
