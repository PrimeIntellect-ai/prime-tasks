#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import shutil
import subprocess
import tempfile

WORK_DIR = "/home/user/polyglot"
BUILD_SCRIPT = os.path.join(WORK_DIR, "build.sh")
LIBSEQ_C = os.path.join(WORK_DIR, "libseq.c")
VERIFY_PY = os.path.join(WORK_DIR, "verify.py")
TEST_MEM_C = os.path.join(WORK_DIR, "test_mem.c")


def setup_module(module):
    for f in ["build_report.txt", "libseq.so", "test_mem"]:
        path = os.path.join(WORK_DIR, f)
        if os.path.exists(path):
            os.remove(path)


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def make_tool_wrappers(tmpdir):
    logs = {}
    for tool, real in [("gcc", "/usr/bin/gcc"), ("valgrind", "/usr/bin/valgrind"), ("python3", "/usr/bin/python3")]:
        log = os.path.join(tmpdir, tool + ".jsonl")
        logs[tool] = log
        wrapper = os.path.join(tmpdir, tool)
        with open(wrapper, "w") as f:
            f.write("#!/usr/bin/python3\n")
            f.write("import json, os, sys\n")
            f.write("with open(%r, 'a') as out: out.write(json.dumps(sys.argv[1:]) + '\\n')\n" % log)
            f.write("os.execv(%r, [%r] + sys.argv[1:])\n" % (real, real))
        os.chmod(wrapper, 0o755)
    return logs


def read_log(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [json.loads(line) for line in f if line.strip()]


def assert_required_build_invocations(logs, mode):
    gcc_calls = read_log(logs["gcc"])
    expected = ["-shared", "-fPIC"]
    if mode == "PROD":
        expected += ["-O3", "-DNDEBUG"]
    else:
        expected += ["-g", "-O0"]
    expected += ["libseq.c", "-o", "libseq.so"]
    assert expected in gcc_calls, f"Missing required {mode} shared-library gcc invocation; saw {gcc_calls}"

    assert any("test_mem.c" in call and "-o" in call and call[call.index("-o") + 1] == "test_mem"
               for call in gcc_calls), f"build.sh did not compile test_mem.c into test_mem; saw {gcc_calls}"
    assert ["--error-exitcode=1", "--leak-check=full", "./test_mem"] in read_log(logs["valgrind"]), \
        f"build.sh did not invoke the required Valgrind command; saw {read_log(logs['valgrind'])}"
    assert ["verify.py"] in read_log(logs["python3"]), \
        f"build.sh did not run python3 verify.py; saw {read_log(logs['python3'])}"


def run_instrumented_build(mode_marker):
    with tempfile.TemporaryDirectory() as td:
        logs = make_tool_wrappers(td)
        env = os.environ.copy()
        env["PATH"] = td + os.pathsep + env["PATH"]
        if mode_marker is None:
            env.pop("BUILD_MODE", None)
            expected_mode = "DEBUG"
        else:
            env["BUILD_MODE"] = mode_marker
            expected_mode = "PROD" if mode_marker == "PROD" else "DEBUG"
        result = run(["./build.sh"], cwd=WORK_DIR, env=env)
        assert result.returncode == 0, (
            f"build.sh failed for BUILD_MODE={mode_marker!r}:\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
        assert_required_build_invocations(logs, expected_mode)
        return result


def test_files_exist():
    assert os.path.isdir(WORK_DIR), f"Directory {WORK_DIR} does not exist"
    assert os.path.isfile(BUILD_SCRIPT), f"{BUILD_SCRIPT} does not exist"
    assert os.path.isfile(LIBSEQ_C), f"{LIBSEQ_C} does not exist"
    assert os.path.isfile(VERIFY_PY), f"{VERIFY_PY} does not exist"
    assert os.path.isfile(TEST_MEM_C), f"{TEST_MEM_C} does not exist"


def test_build_script_executable():
    assert os.access(BUILD_SCRIPT, os.X_OK), f"{BUILD_SCRIPT} is not executable"


def test_build_stops_when_valgrind_finds_library_leak():
    with open(LIBSEQ_C, "rb") as f:
        original = f.read()
    leaky = b'''#include <stdlib.h>\nint* compute_sequence(int n) {\n int *temp=malloc(n*sizeof(int));\n int *result=malloc(n*sizeof(int));\n for(int i=0;i<n;i++) temp[i]=i*2;\n for(int i=0;i<n;i++) result[i]=temp[i]+1;\n return result;\n}\nvoid free_sequence(int *seq) { free(seq); }\n'''
    report = os.path.join(WORK_DIR, "build_report.txt")
    if os.path.exists(report):
        os.remove(report)
    try:
        with open(LIBSEQ_C, "wb") as f:
            f.write(leaky)
        env = os.environ.copy()
        env["BUILD_MODE"] = "DEBUG"
        result = run(["./build.sh"], cwd=WORK_DIR, env=env)
        assert result.returncode != 0, "build.sh succeeded even though compute_sequence leaked memory"
        assert not os.path.exists(report), "build.sh created its success report after Valgrind should have failed"
    finally:
        with open(LIBSEQ_C, "wb") as f:
            f.write(original)


def test_build_prod_mode():
    setup_module(None)
    run_instrumented_build("PROD")
    report_path = os.path.join(WORK_DIR, "build_report.txt")
    assert os.path.isfile(report_path), "build_report.txt was not created"
    with open(report_path, "r") as f:
        content = f.read().strip()
    assert content == "ALL_SYSTEMS_GO", f"build_report.txt contains incorrect text: {content}"


def test_build_debug_mode():
    setup_module(None)
    run_instrumented_build("DEBUG")


def test_build_defaults_to_debug_when_unset():
    setup_module(None)
    run_instrumented_build(None)


def test_build_defaults_to_debug_for_other_value():
    setup_module(None)
    run_instrumented_build("SOMETHING_ELSE")


def test_library_behavior_independently():
    code = r'''
import ctypes, os, secrets
lib = ctypes.CDLL(os.path.join("/home/user/polyglot", "libseq.so"))
lib.compute_sequence.argtypes = [ctypes.c_int]
lib.compute_sequence.restype = ctypes.POINTER(ctypes.c_int)
lib.free_sequence.argtypes = [ctypes.POINTER(ctypes.c_int)]
lib.free_sequence.restype = None
sizes = [1, 5, 100, 257, secrets.randbelow(400) + 20]
for n in sizes:
    ptr = lib.compute_sequence(n)
    if not ptr:
        raise SystemExit("compute_sequence returned NULL")
    got = [ptr[i] for i in range(n)]
    expected = [(i * 2) + 1 for i in range(n)]
    try:
        if got != expected:
            raise SystemExit("wrong sequence for n=%d" % n)
    finally:
        lib.free_sequence(ptr)
'''
    result = run(["python3", "-c", code], cwd=WORK_DIR)
    assert result.returncode == 0, f"Independent libseq.so test failed:\n{result.stdout}\n{result.stderr}"


def test_submitted_library_has_no_leaks_under_trusted_harness():
    harness = r'''
#include <stdlib.h>
int* compute_sequence(int n);
void free_sequence(int* seq);
int main(void) {
    int sizes[] = {1, 5, 100, 257};
    for (int k = 0; k < 4; ++k) {
        int n = sizes[k];
        int *p = compute_sequence(n);
        if (!p) return 2;
        for (int i = 0; i < n; ++i) if (p[i] != i * 2 + 1) return 3;
        free_sequence(p);
    }
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        hp = os.path.join(td, "harness.c")
        exe = os.path.join(td, "harness")
        with open(hp, "w") as f:
            f.write(harness)
        comp = run(["gcc", hp, LIBSEQ_C, "-o", exe])
        assert comp.returncode == 0, f"Could not compile trusted memory harness:\n{comp.stderr}"
        result = run([
            "valgrind", "--error-exitcode=1", "--leak-check=full",
            "--show-leak-kinds=all", "--errors-for-leak-kinds=all", exe
        ])
        assert result.returncode == 0, f"Trusted harness found errors or leaks:\n{result.stderr}"


def compile_spy_library(td, wrong_values=False):
    marker_logic = r'''
#include <stdio.h>
#include <stdlib.h>
static int seen = 0;
static int *issued = NULL;
int* compute_sequence(int n) {
    if (n != 5) return NULL;
    seen = 1;
    issued = malloc(5 * sizeof(int));
    if (!issued) return NULL;
    for (int i=0; i<5; ++i) issued[i] = WRONG ? 42 : (i*2+1);
    return issued;
}
void free_sequence(int *p) {
    if (!seen || p != issued) return;
    free(p); issued = NULL;
    const char *m = getenv("SEQ_SPY_MARKER");
    if (m) { FILE *f=fopen(m,"w"); if (f) { fputs("ok",f); fclose(f); } }
}
'''.replace("WRONG", "1" if wrong_values else "0")
    src = os.path.join(td, "spy.c")
    so = os.path.join(td, "libseq.so")
    with open(src, "w") as f:
        f.write(marker_logic)
    result = run(["gcc", "-shared", "-fPIC", src, "-o", so])
    assert result.returncode == 0, result.stderr
    return so


def test_verify_py_really_loads_calls_checks_and_frees():
    live_lib = os.path.join(WORK_DIR, "libseq.so")
    backup = live_lib + ".verifier_backup"
    shutil.copy2(live_lib, backup)
    try:
        for wrong in (False, True):
            with tempfile.TemporaryDirectory() as td:
                spy = compile_spy_library(td, wrong)
                shutil.copy2(spy, live_lib)
                marker = os.path.join(td, "freed")
                env = os.environ.copy()
                env["SEQ_SPY_MARKER"] = marker
                result = run(["python3", "verify.py"], cwd=WORK_DIR, env=env)
                assert os.path.exists(marker), "verify.py did not call compute_sequence(5) and free_sequence"
                if wrong:
                    assert result.returncode != 0, "verify.py accepted an incorrect sequence"
                else:
                    assert result.returncode == 0, f"verify.py failed:\n{result.stderr}"
                    assert "VERIFICATION_PASSED" in result.stdout, \
                        f"verify.py did not output VERIFICATION_PASSED, got: {result.stdout}"
    finally:
        os.replace(backup, live_lib)


def test_verify_py_output():
    result = run(["python3", "verify.py"], cwd=WORK_DIR)
    assert result.returncode == 0, f"verify.py failed:\n{result.stderr}"
    assert "VERIFICATION_PASSED" in result.stdout, f"verify.py did not output VERIFICATION_PASSED, got: {result.stdout}"


def test_test_mem_calls_required_functions():
    spy = r'''
#include <stdio.h>
#include <stdlib.h>
static int *issued;
static int called;
int* compute_sequence(int n) {
    if (n != 100) exit(81);
    called = 1;
    issued = malloc(100 * sizeof(int));
    if (!issued) exit(82);
    for (int i=0;i<100;i++) issued[i]=i*2+1;
    return issued;
}
void free_sequence(int *p) {
    if (!called || p != issued) exit(83);
    free(p); issued=NULL;
    const char *m=getenv("TEST_MEM_MARKER");
    if (m) { FILE *f=fopen(m,"w"); if (f) { fputs("ok",f); fclose(f); } }
}
'''
    with tempfile.TemporaryDirectory() as td:
        original = open(LIBSEQ_C, "rb").read()
        spy_so = os.path.join(td, "libspy.so")
        spy_copy = os.path.join(td, "spy.c")
        exe = os.path.join(td, "test_mem_audit")
        marker = os.path.join(td, "marker")
        with open(spy_copy, "w") as f:
            f.write(spy)
        try:
            with open(LIBSEQ_C, "w") as f:
                f.write(spy)
            comp1 = run(["gcc", "-shared", "-fPIC", spy_copy, "-o", spy_so])
            assert comp1.returncode == 0, comp1.stderr
            comp2 = run(["gcc", TEST_MEM_C, "-L" + td, "-lspy", "-Wl,-rpath," + td, "-o", exe])
            assert comp2.returncode == 0, f"test_mem.c could not be compiled against the audit library:\n{comp2.stderr}"
        finally:
            with open(LIBSEQ_C, "wb") as f:
                f.write(original)
        env = os.environ.copy()
        env["TEST_MEM_MARKER"] = marker
        result = run([exe], env=env)
        assert result.returncode == 0, f"test_mem did not run cleanly: {result.stderr}"
        assert os.path.exists(marker), "test_mem did not call compute_sequence(100) and free_sequence on its result"


def test_valgrind_memory_leak():
    test_mem_path = os.path.join(WORK_DIR, "test_mem")
    assert os.path.isfile(test_mem_path), "test_mem executable not found"
    result = run(["valgrind", "--error-exitcode=1", "--leak-check=full", "./test_mem"], cwd=WORK_DIR)
    assert result.returncode == 0, f"Valgrind detected memory leaks:\n{result.stderr}"


def test_libseq_c_fixed():
    with open(LIBSEQ_C, "r") as f:
        content = f.read()
    assert "free(temp)" in content.replace(" ", "") or "free(temp);" in content, \
        "libseq.c does not appear to free 'temp' to fix the memory leak."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
