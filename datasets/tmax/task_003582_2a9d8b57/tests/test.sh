#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import tempfile


def run(cmd, *, stdin_path=None, timeout=30):
    stdin = open(stdin_path, "r") if stdin_path else None
    try:
        return subprocess.run(
            cmd,
            stdin=stdin,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    finally:
        if stdin is not None:
            stdin.close()


def definitely_lost(stderr):
    match = re.search(r"definitely lost:\s*([0-9,]+) bytes", stderr, re.IGNORECASE)
    assert match, f"Could not find Valgrind's definitely-lost summary:\n{stderr}"
    return int(match.group(1).replace(",", ""))


def compile_c(source, output, extra_sources=()):
    cmd = ["gcc", "-std=gnu11", "-O0", "-g", source, *extra_sources,
           "-o", output, "-pthread", "-lm"]
    result = run(cmd)
    assert result.returncode == 0, (
        f"Failed to compile {source} with the required pthread/math linker flags.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def valgrind(executable, input_path=None, timeout=45):
    return run([
        "valgrind", "--leak-check=full", "--show-leak-kinds=all",
        "--errors-for-leak-kinds=definite", "--error-exitcode=99", executable
    ], stdin_path=input_path, timeout=timeout)


def test_eval_service_orig_exists():
    path = "/home/user/eval_service_orig"
    assert os.path.isfile(path), f"Original compiled service {path} is missing."
    assert os.access(path, os.X_OK), f"{path} is not executable."

    result = run(["valgrind", "--leak-check=full", path],
                 stdin_path="/home/user/fuzz_inputs.txt", timeout=45)
    assert result.returncode == 0, (
        f"Original service did not process the supplied inputs successfully.\n{result.stderr}"
    )
    assert definitely_lost(result.stderr) == 48, (
        "eval_service_orig does not exhibit the original program's expected 48-byte leak."
    )


def test_leak_bytes_correct():
    path = "/home/user/leak_bytes.txt"
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "48", f"Expected 48 leaked bytes, but got '{content}' in {path}."


def test_fixed_eval_c_exists():
    path = "/home/user/fixed_eval.c"
    assert os.path.isfile(path), f"Fixed source file {path} is missing."


def test_fixed_source_compiles_and_evaluates_polynomials():
    source = "/home/user/fixed_eval.c"
    compiled = "/tmp/fixed_eval_from_source"
    compile_c(source, compiled)

    # Include the submitted implementation in a harness so its evaluator's
    # numerical results can be checked directly rather than merely checking
    # the shape or exit status of an unrelated executable.
    harness_source = "/tmp/evaluator_harness.c"
    harness_binary = "/tmp/evaluator_harness"
    with open(harness_source, "w") as f:
        f.write(r'''#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define main submitted_service_main
#include "/home/user/fixed_eval.c"
#undef main

int main(void) {
    struct Case { const char *text; double coeff; double power; } cases[] = {
        {"3.5 x^2.0", 3.5, 2.0},
        {"-1.5 x^0.5", -1.5, 0.5},
        {"0.125 x^7", 0.125, 7.0},
        {"2 x^-3", 2.0, -3.0},
        {"-4.25 x^0", -4.25, 0.0}
    };

    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        Task task;
        task.expression = strdup(cases[i].text);
        task.result = NAN;
        if (!task.expression) return 20;
        evaluate_polynomial(&task);
        double expected = cases[i].coeff * pow(2.0, cases[i].power);
        free(task.expression);
        if (!isfinite(task.result) || fabs(task.result - expected) > 1e-9) {
            fprintf(stderr, "wrong result for case %zu: got %.17g expected %.17g\n",
                    i, task.result, expected);
            return 21;
        }
    }

    const char *bad[] = {"malformed", "broken x^", "x^2", "", "1.2 x^oops"};
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); i++) {
        Task task;
        task.expression = strdup(bad[i]);
        task.result = 12345.0;
        if (!task.expression) return 22;
        evaluate_polynomial(&task);
        free(task.expression);
    }
    return 0;
}
''')
    compile_c(harness_source, harness_binary)

    result = valgrind(harness_binary)
    assert result.returncode == 0, (
        "The submitted polynomial evaluator produced wrong results, crashed, or leaked "
        f"on derived valid/malformed cases.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert definitely_lost(result.stderr) == 0

    # Exercise the main program compiled from the submitted source with a
    # larger mix of valid and malformed lines to cover its threaded lifecycle.
    stress_input = "/tmp/polynomial_stress_inputs.txt"
    with open(stress_input, "w") as f:
        for i in range(250):
            if i % 4 == 0:
                f.write(f"{i / 7.0:.8f} x^{(i % 13) - 6}\n")
            elif i % 4 == 1:
                f.write(f"malformed_case_{i}\n")
            elif i % 4 == 2:
                f.write("broken x^\n")
            else:
                f.write(f"-{i}.25 x^0.5\n")

    stress = valgrind(compiled, stress_input, timeout=60)
    assert stress.returncode == 0, (
        f"Program compiled from fixed_eval.c crashed or leaked under mixed threaded input.\n"
        f"stdout:\n{stress.stdout}\nstderr:\n{stress.stderr}"
    )
    assert definitely_lost(stress.stderr) == 0


def test_eval_service_exists_and_fixed():
    executable = "/home/user/eval_service"
    input_file = "/home/user/fuzz_inputs.txt"

    assert os.path.isfile(executable), f"Fixed compiled service {executable} is missing."
    assert os.access(executable, os.X_OK), f"{executable} is not executable."
    assert os.path.isfile(input_file), f"Input file {input_file} is missing."

    result = run(["valgrind", "--leak-check=full", executable],
                 stdin_path=input_file, timeout=45)

    assert result.returncode == 0, (
        f"eval_service crashed or returned non-zero exit code. Stderr: {result.stderr}"
    )

    stderr_lower = result.stderr.lower()
    assert "definitely lost: 0 bytes" in stderr_lower, (
        "Memory leak is not fully fixed. Valgrind output did not indicate 0 bytes "
        f"definitely lost.\nValgrind output:\n{result.stderr}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
