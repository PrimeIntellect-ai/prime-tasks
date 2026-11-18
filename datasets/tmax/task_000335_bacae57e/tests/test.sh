#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import textwrap

PROJECT_DIR = "/home/user/forensic_project"
REPORT_PATH = "/home/user/debug_report.txt"


def run(cmd, **kwargs):
    return subprocess.run(cmd, **kwargs)


def test_makefile_builds_successfully():
    subprocess.run(["make", "clean"], cwd=PROJECT_DIR,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = subprocess.run(["make"], cwd=PROJECT_DIR,
                            capture_output=True, text=True)
    assert result.returncode == 0, f"make failed with error:\n{result.stderr}"

    exe_path = os.path.join(PROJECT_DIR, "forensic_tool")
    assert os.path.isfile(exe_path), "forensic_tool executable was not created by make."
    assert os.access(exe_path, os.X_OK), "forensic_tool is not executable."

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = os.path.join(PROJECT_DIR, "lib")
    executed = subprocess.run([exe_path], cwd=PROJECT_DIR, env=env,
                              capture_output=True, text=True, timeout=10)
    assert executed.returncode == 0, executed.stderr
    assert "Auth token: TOK" in executed.stdout, "Built program did not use libauth correctly."


def test_auth_h_signature_fixed():
    auth_h_path = os.path.join(PROJECT_DIR, "include", "auth.h")
    assert os.path.isfile(auth_h_path), "include/auth.h is missing."
    with open(auth_h_path, "r") as f:
        content = f.read()

    match = re.search(r"void\s+generate_token\s*\(\s*int\b[^,]*,\s*char\s*\*\b[^,]*,\s*int\b[^)]*\)\s*;", content)
    assert match is not None, "auth.h does not contain the correct signature for generate_token."


def _strip_c_comments(content):
    content = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    return re.sub(r"//[^\n]*", "", content)


def test_extractor_c_uses_strtok_r():
    extractor_path = os.path.join(PROJECT_DIR, "extractor.c")
    assert os.path.isfile(extractor_path), "extractor.c is missing."
    with open(extractor_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "strtok_r" in content, "extractor.c does not use the thread-safe strtok_r function."
    assert re.search(r"\bstrtok\s*\(", content) is None, "extractor.c still contains calls to the non-thread-safe strtok."

    # Ensure the occurrence is an actual call in parse_log_entry, not a comment
    # or an unrelated helper.
    clean = _strip_c_comments(content)
    start = re.search(r"\bparse_log_entry\s*\([^)]*\)\s*\{", clean)
    assert start, "parse_log_entry is missing."
    pos = start.end()
    depth = 1
    while pos < len(clean) and depth:
        if clean[pos] == "{":
            depth += 1
        elif clean[pos] == "}":
            depth -= 1
        pos += 1
    assert depth == 0, "Could not parse parse_log_entry body."
    body = clean[start.end():pos - 1]
    assert re.search(r"\bstrtok_r\s*\(", body), "parse_log_entry does not call strtok_r."

    obj = os.path.join(PROJECT_DIR, "extractor.o")
    symbols = subprocess.run(["nm", "-u", obj], capture_output=True, text=True)
    assert symbols.returncode == 0, symbols.stderr
    assert re.search(r"\bstrtok_r(?:@@[^\s]+)?$", symbols.stdout, re.M), "extractor.o does not reference strtok_r."
    assert not re.search(r"\bstrtok(?:@@[^\s]+)?$", symbols.stdout, re.M), "extractor.o references unsafe strtok."


def test_parse_log_entry_behavior_under_concurrency():
    harness = r'''
#define _POSIX_C_SOURCE 200809L
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern char *parse_log_entry(const char *);
#define NTHREADS 20
#define ROUNDS 2500
static pthread_barrier_t barrier;
static atomic_int failed;

static void *worker(void *arg) {
    long id = (long)arg;
    pthread_barrier_wait(&barrier);
    for (int i = 0; i < ROUNDS; ++i) {
        char input[256], expected[80];
        snprintf(expected, sizeof expected, "ACTION_%ld_%d", id, i);
        snprintf(input, sizeof input, "USER_%ld_%d,ROLE_%d,%d,%s",
                 id, i, (i * 17 + (int)id) % 97, i * 31, expected);
        char *answer = parse_log_entry(input);
        if (!answer || strcmp(answer, expected) != 0)
            atomic_store(&failed, 1);
        free(answer);
    }
    return NULL;
}

int main(void) {
    const char *basic[] = {"A,B,C,D", "one,two,three,final-value", "x,y,987654,Z"};
    const char *want[] = {"D", "final-value", "Z"};
    for (int i = 0; i < 3; ++i) {
        char *p = parse_log_entry(basic[i]);
        if (!p || strcmp(p, want[i]) != 0) return 2;
        free(p);
    }
    pthread_t threads[NTHREADS];
    if (pthread_barrier_init(&barrier, NULL, NTHREADS) != 0) return 3;
    for (long i = 0; i < NTHREADS; ++i)
        if (pthread_create(&threads[i], NULL, worker, (void *)i) != 0) return 4;
    for (int i = 0; i < NTHREADS; ++i) pthread_join(threads[i], NULL);
    pthread_barrier_destroy(&barrier);
    return atomic_load(&failed) ? 1 : 0;
}
'''
    src = "/tmp/extractor_stress.c"
    exe = "/tmp/extractor_stress"
    with open(src, "w") as f:
        f.write(harness)
    built = subprocess.run([
        "gcc", "-std=c11", "-O2", "-pthread", src,
        os.path.join(PROJECT_DIR, "extractor.c"), "-o", exe
    ], cwd=PROJECT_DIR, capture_output=True, text=True)
    assert built.returncode == 0, f"Could not build independent parser test:\n{built.stderr}"
    tested = subprocess.run([exe], cwd=PROJECT_DIR, capture_output=True,
                            text=True, timeout=30)
    assert tested.returncode == 0, "parse_log_entry failed generated concurrent inputs."


def _build_instrumented_regression():
    wrapper = r'''
#define _POSIX_C_SOURCE 200809L
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static atomic_int creates;
static atomic_int calls;
static atomic_int bad_input;
static atomic_int fault_used;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_t callers[128];
static int unique_callers;

int __real_pthread_create(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
char *__real_parse_log_entry(const char *);

int __wrap_pthread_create(pthread_t *t, const pthread_attr_t *a,
                          void *(*fn)(void *), void *arg) {
    atomic_fetch_add(&creates, 1);
    return __real_pthread_create(t, a, fn, arg);
}

char *__wrap_parse_log_entry(const char *s) {
    atomic_fetch_add(&calls, 1);
    if (!s || strcmp(s, "USER,ADMIN,12345,LOGIN") != 0)
        atomic_fetch_add(&bad_input, 1);

    pthread_t self = pthread_self();
    pthread_mutex_lock(&lock);
    int found = 0;
    for (int i = 0; i < unique_callers; ++i)
        if (pthread_equal(callers[i], self)) found = 1;
    if (!found && unique_callers < 128) callers[unique_callers++] = self;
    pthread_mutex_unlock(&lock);

    char *answer = __real_parse_log_entry(s);
    if (getenv("REG_FAIL_ONE") && atomic_exchange(&fault_used, 1) == 0) {
        free(answer);
        return strdup("NOT_LOGIN");
    }
    return answer;
}

__attribute__((destructor)) static void report(void) {
    const char *path = getenv("REG_STATS");
    if (!path) return;
    FILE *f = fopen(path, "w");
    if (!f) return;
    fprintf(f, "%d %d %d %d\n", atomic_load(&creates), atomic_load(&calls),
            unique_callers, atomic_load(&bad_input));
    fclose(f);
}
'''
    wrapper_path = "/tmp/reg_wrapper.c"
    reg_obj = "/tmp/regression_test.o"
    ext_obj = "/tmp/regression_extractor.o"
    exe = "/tmp/instrumented_regression"
    with open(wrapper_path, "w") as f:
        f.write(wrapper)

    commands = [
        ["gcc", "-std=c11", "-pthread", "-I", PROJECT_DIR,
         "-c", os.path.join(PROJECT_DIR, "regression_test.c"), "-o", reg_obj],
        ["gcc", "-std=c11", "-pthread", "-I", PROJECT_DIR,
         "-c", os.path.join(PROJECT_DIR, "extractor.c"), "-o", ext_obj],
        ["gcc", "-std=c11", "-pthread", reg_obj, ext_obj, wrapper_path,
         "-Wl,--wrap=pthread_create", "-Wl,--wrap=parse_log_entry",
         "-L", os.path.join(PROJECT_DIR, "lib"), "-lauth", "-o", exe],
    ]
    for command in commands:
        result = subprocess.run(command, cwd=PROJECT_DIR, capture_output=True, text=True)
        assert result.returncode == 0, f"Could not compile regression_test.c:\n{result.stderr}"
    return exe


def _read_stats(path):
    assert os.path.isfile(path), "Regression instrumentation produced no statistics."
    fields = open(path).read().strip().split()
    assert len(fields) == 4, "Invalid regression statistics."
    return tuple(map(int, fields))


def test_regression_test_exists_and_passes():
    reg_src = os.path.join(PROJECT_DIR, "regression_test.c")
    assert os.path.isfile(reg_src), "regression_test.c is missing."

    reg_exe = os.path.join(PROJECT_DIR, "regression_test")
    assert os.path.isfile(reg_exe), "regression_test executable is missing. Make sure it is compiled."
    assert os.access(reg_exe, os.X_OK), "regression_test is not executable."

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = os.path.join(PROJECT_DIR, "lib") + ":" + env.get("LD_LIBRARY_PATH", "")
    result = subprocess.run([reg_exe], cwd=PROJECT_DIR, capture_output=True,
                            env=env, timeout=20)
    assert result.returncode == 0, "regression_test failed (non-zero exit code)."

    # Recompile the submitted source and instrument its calls. This proves it
    # really creates 20 threads and has each thread call parse_log_entry with
    # the required input, rather than merely returning zero.
    instrumented = _build_instrumented_regression()
    stats = "/tmp/regression_stats_ok"
    try:
        os.unlink(stats)
    except FileNotFoundError:
        pass
    env["REG_STATS"] = stats
    normal = subprocess.run([instrumented], cwd=PROJECT_DIR, env=env,
                            capture_output=True, timeout=20)
    assert normal.returncode == 0, "Submitted regression source fails with the real parser."
    creates, calls, unique, bad = _read_stats(stats)
    assert creates >= 20, "regression_test.c does not create 20 threads."
    assert calls >= 20, "regression_test.c does not call parse_log_entry from every thread."
    assert unique >= 20, "parse_log_entry was not called by 20 distinct threads."
    assert bad == 0, "Regression test did not use the exact required log entry."

    # A valid regression must return 1 when even one worker receives a result
    # other than LOGIN.
    fault_stats = "/tmp/regression_stats_fault"
    try:
        os.unlink(fault_stats)
    except FileNotFoundError:
        pass
    fault_env = env.copy()
    fault_env["REG_STATS"] = fault_stats
    fault_env["REG_FAIL_ONE"] = "1"
    faulty = subprocess.run([instrumented], cwd=PROJECT_DIR, env=fault_env,
                            capture_output=True, timeout=20)
    assert faulty.returncode == 1, "regression_test does not detect an incorrect final token."


def test_debug_report_contents():
    assert os.path.isfile(REPORT_PATH), "debug_report.txt is missing."
    with open(REPORT_PATH, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert re.search(r"THREAD_SAFE_FUNC:\s*strtok_r", content), "debug_report.txt missing or incorrect THREAD_SAFE_FUNC."
    assert re.search(r"REGRESSION_PASS:\s*YES", content), "debug_report.txt missing or incorrect REGRESSION_PASS."
    assert re.search(r"SIGNATURE:\s*void\s+generate_token", content), "debug_report.txt missing or incorrect SIGNATURE."

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert len(lines) == 3, "debug_report.txt must contain exactly the three requested entries."
    assert lines[0].startswith("SIGNATURE:"), "SIGNATURE must be the first report entry."
    assert lines[1] == "THREAD_SAFE_FUNC: strtok_r", "THREAD_SAFE_FUNC entry is not exact."
    assert lines[2] == "REGRESSION_PASS: YES", "REGRESSION_PASS entry is not exact."

    header = open(os.path.join(PROJECT_DIR, "include", "auth.h")).read()
    declaration = re.search(r"void\s+generate_token\s*\([^;]*\)\s*;", _strip_c_comments(header), re.S)
    assert declaration, "Could not find generate_token declaration in auth.h."
    reported = lines[0].split(":", 1)[1].strip()
    canonical = lambda s: re.sub(r"\s+", "", s)
    assert canonical(reported) == canonical(declaration.group(0)), \
        "Reported signature is not the exact declaration placed in auth.h."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
