#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import shutil
import subprocess
import tempfile

PIPELINE = "/home/user/pipeline"
EVALUATE_C = os.path.join(PIPELINE, "evaluate.c")
LIBRARY = os.path.join(PIPELINE, "libevaluate.so")
SOLVER = os.path.join(PIPELINE, "solver.py")
SOLUTION = os.path.join(PIPELINE, "solution.txt")


def expected(v1, v2, v3, v4):
    return int(
        3 * v1 + 5 * v2 + v3 - 2 * v4 == 99
        and v1 * v1 + v2 * v3 - v4 == 283
        and v1 + v2 + v3 + v4 == 48
    )


def test_evaluate_c_exists():
    assert os.path.isfile(EVALUATE_C), f"File {EVALUATE_C} does not exist."


def test_libevaluate_so_exists():
    assert os.path.isfile(LIBRARY), f"File {LIBRARY} does not exist."


def test_solver_py_exists_and_uses_ctypes():
    assert os.path.isfile(SOLVER), f"File {SOLVER} does not exist."
    with open(SOLVER, "r", encoding="utf-8") as f:
        content = f.read()
    assert "ctypes" in content, "solver.py does not appear to import or use ctypes."


def test_solution_txt_content():
    assert os.path.isfile(SOLUTION), f"File {SOLUTION} does not exist."
    with open(SOLUTION, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content == "12,15,10,11", f"solution.txt contains '{content}', expected '12,15,10,11'."


def build_checker(path):
    source = r'''
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

typedef int (*eval_fn)(int, int, int, int);

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!handle) { fprintf(stderr, "%s\n", dlerror()); return 3; }
    dlerror();
    eval_fn fn = (eval_fn)dlsym(handle, "evaluate_constraints");
    const char *err = dlerror();
    if (err || !fn) { fprintf(stderr, "%s\n", err ? err : "missing symbol"); return 4; }
    for (int a = 1; a <= 50; ++a)
      for (int b = 1; b <= 50; ++b)
        for (int c = 1; c <= 50; ++c)
          for (int d = 1; d <= 50; ++d) {
            int want = ((3*a + 5*b + c - 2*d) == 99) &&
                       ((a*a + b*c - d) == 283) &&
                       ((a + b + c + d) == 48);
            int got = fn(a, b, c, d);
            if (got != want) {
                fprintf(stderr, "mismatch at %d,%d,%d,%d: got %d want %d\n", a,b,c,d,got,want);
                return 5;
            }
          }
    dlclose(handle);
    return 0;
}
'''
    src = path + ".c"
    with open(src, "w", encoding="utf-8") as f:
        f.write(source)
    subprocess.run(["gcc", "-O2", src, "-ldl", "-o", path], check=True)


def test_submitted_library_and_c_source_implement_constraints():
    with tempfile.TemporaryDirectory() as td:
        checker = os.path.join(td, "checker")
        rebuilt = os.path.join(td, "rebuilt.so")
        build_checker(checker)

        # Exercise the submitted shared object itself over the complete required domain.
        subprocess.run([checker, LIBRARY], check=True, timeout=30)

        # Independently compile and exercise evaluate.c, so a dummy source cannot pass.
        subprocess.run(
            ["gcc", "-O2", "-shared", "-fPIC", EVALUATE_C, "-o", rebuilt],
            check=True,
            timeout=30,
        )
        subprocess.run([checker, rebuilt], check=True, timeout=30)


def test_solver_executes_ctypes_function_and_regenerates_solution():
    probe_source = r'''
#include <stdio.h>
#include <stdlib.h>

static unsigned long long calls = 0;
static unsigned long long valid_calls = 0;
static unsigned long long true_calls = 0;

int evaluate_constraints(int a, int b, int c, int d) {
    ++calls;
    if (a >= 1 && a <= 50 && b >= 1 && b <= 50 &&
        c >= 1 && c <= 50 && d >= 1 && d <= 50) ++valid_calls;
    int result = ((3*a + 5*b + c - 2*d) == 99) &&
                 ((a*a + b*c - d) == 283) &&
                 ((a + b + c + d) == 48);
    if (result) ++true_calls;
    return result;
}

__attribute__((destructor)) static void report(void) {
    const char *path = getenv("EVALUATE_PROBE_LOG");
    if (!path) return;
    FILE *f = fopen(path, "w");
    if (!f) return;
    fprintf(f, "%llu %llu %llu\n", calls, valid_calls, true_calls);
    fclose(f);
}
'''
    with tempfile.TemporaryDirectory() as td:
        probe_c = os.path.join(td, "probe.c")
        probe_so = os.path.join(td, "probe.so")
        backup = os.path.join(td, "submitted.so")
        log = os.path.join(td, "calls.log")
        with open(probe_c, "w", encoding="utf-8") as f:
            f.write(probe_source)
        subprocess.run(["gcc", "-O2", "-shared", "-fPIC", probe_c, "-o", probe_so], check=True)

        shutil.copy2(LIBRARY, backup)
        try:
            shutil.copy2(probe_so, LIBRARY)
            if os.path.exists(SOLUTION):
                os.unlink(SOLUTION)
            env = os.environ.copy()
            env["EVALUATE_PROBE_LOG"] = log
            subprocess.run(["python3", SOLVER], cwd=PIPELINE, env=env, check=True, timeout=90)
        finally:
            shutil.copy2(backup, LIBRARY)

        assert os.path.isfile(log), "solver.py did not invoke evaluate_constraints through the shared library"
        with open(log, "r", encoding="utf-8") as f:
            calls, valid_calls, true_calls = map(int, f.read().split())
        assert calls >= 100000, "solver.py did not perform the required version-space search"
        assert valid_calls == calls, "solver.py called the C function with values outside the required 1..50 domain"
        assert true_calls >= 1, "solver.py never found a satisfying combination through the C function"

        assert os.path.isfile(SOLUTION), "solver.py did not regenerate solution.txt"
        with open(SOLUTION, "r", encoding="utf-8") as f:
            generated = f.read().strip()
        solutions = [
            (a, b, c, d)
            for a in range(1, 51)
            for b in range(1, 51)
            for c in range(1, 51)
            for d in range(1, 51)
            if expected(a, b, c, d)
        ]
        assert len(solutions) == 1
        assert generated == ",".join(map(str, solutions[0]))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
