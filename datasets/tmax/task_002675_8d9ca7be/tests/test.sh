#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import shutil
import subprocess
import tempfile

ROOT = "/home/user/sensor_service"
MAKEFILE = os.path.join(ROOT, "Makefile")
SOURCE = os.path.join(ROOT, "sensor_lib.c")
LIBRARY = os.path.join(ROOT, "libsensor.so")
SCRIPT = os.path.join(ROOT, "test_regression.py")
LOG = os.path.join(ROOT, "regression_result.log")
EXPECTED_LOG = "REGRESSION_TEST_PASSED"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def check_sources_and_build():
    assert os.path.exists(MAKEFILE), "Makefile is missing."
    with open(MAKEFILE) as f:
        make_content = f.read()
    assert "-fPIC" in make_content, "Makefile does not contain -fPIC."

    assert os.path.exists(SOURCE), "sensor_lib.c is missing."
    with open(SOURCE) as f:
        c_content = f.read()
    assert re.search(r'(size_t|uint64_t|int64_t|long\s+long)', c_content), \
        "sensor_lib.c does not use a sufficiently large integer type."
    assert "free(" in c_content, "sensor_lib.c does not contain a free() call."

    clean = run(["make", "clean"], cwd=ROOT, timeout=30)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"
    build = run(["make"], cwd=ROOT, timeout=60)
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(LIBRARY), "libsensor.so was not built."
    with open(LIBRARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libsensor.so is not an ELF library."


def check_large_call():
    code = r'''
import ctypes, json
lib = ctypes.CDLL("/home/user/sensor_service/libsensor.so")
fn = lib.process_sensor_data
fn.argtypes = [ctypes.c_int32, ctypes.c_int32]
fn.restype = ctypes.c_int
rc = fn(60000, 50000)
try:
    freefn = lib.free_buffer
except AttributeError:
    freefn = None
if freefn is not None:
    freefn.argtypes = []
    freefn.restype = None
    freefn()
print(json.dumps({"rc": rc}))
'''
    result = run(["python3", "-c", code], cwd=ROOT, timeout=90)
    assert result.returncode == 0, \
        f"Independent large-batch call crashed or failed:\n{result.stdout}\n{result.stderr}"
    data = json.loads(result.stdout.strip().splitlines()[-1])
    assert data["rc"] == 60000, f"Large-batch call returned {data['rc']}, expected 60000."


def check_memory_behavior():
    code = r'''
import ctypes, json, psutil, resource
lib = ctypes.CDLL("/home/user/sensor_service/libsensor.so")
fn = lib.process_sensor_data
fn.argtypes = [ctypes.c_int32, ctypes.c_int32]
fn.restype = ctypes.c_int
try:
    freefn = lib.free_buffer
except AttributeError:
    freefn = None
if freefn is not None:
    freefn.argtypes = []
    freefn.restype = None

# Bound a defective leaking implementation so verification cannot consume all RAM.
resource.setrlimit(resource.RLIMIT_AS, (700 * 1024 * 1024, 700 * 1024 * 1024))
proc = psutil.Process()
rc = fn(100, 1024)
if freefn is not None:
    freefn()
assert rc == 100
start = proc.memory_info().rss
peak = start
for i in range(10000):
    rc = fn(100, 1024)
    if freefn is not None:
        freefn()
    assert rc == 100, (i, rc)
    if i % 100 == 0:
        peak = max(peak, proc.memory_info().rss)
end = proc.memory_info().rss
peak = max(peak, end)
print(json.dumps({"start": start, "end": end, "peak": peak}))
assert end - start <= 10 * 1024 * 1024, (start, end)
assert peak - start <= 10 * 1024 * 1024, (start, peak)
'''
    result = run(["python3", "-c", code], cwd=ROOT, timeout=90)
    assert result.returncode == 0, \
        f"Independent 10,000-call memory test failed:\n{result.stdout}\n{result.stderr}"


def check_regression_script_with_real_library():
    assert os.path.isfile(SCRIPT), "test_regression.py is missing."
    if os.path.exists(LOG):
        os.remove(LOG)
    result = run(["python3", SCRIPT], cwd=ROOT, timeout=120)
    assert result.returncode == 0, \
        f"test_regression.py failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.exists(LOG), "test_regression.py did not create regression_result.log."
    with open(LOG) as f:
        content = f.read().strip()
    assert content == EXPECTED_LOG, \
        f"regression_result.log contains {content!r}, expected {EXPECTED_LOG!r}."


def compile_probe(path, leaking):
    source = r'''
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned long large_calls = 0;
static unsigned long small_calls = 0;
int process_sensor_data(int32_t count, int32_t size) {
    if (count == 60000 && size == 50000) large_calls++;
    if (count == 100 && size == 1024) {
        small_calls++;
#ifdef LEAKING
        void *p = malloc(8192);
        if (p) memset(p, 0x5a, 8192);
#endif
    }
    return (count > 0 && size > 0) ? count : -1;
}
void free_buffer(void) { }
__attribute__((destructor)) static void report(void) {
    const char *p = getenv("TRACE_PATH");
    if (p) {
        FILE *f = fopen(p, "w");
        if (f) { fprintf(f, "%lu %lu\n", large_calls, small_calls); fclose(f); }
    }
}
'''
    c_path = path + ".c"
    with open(c_path, "w") as f:
        f.write(source)
    cmd = ["gcc", "-shared", "-fPIC", "-O0", "-o", path, c_path]
    if leaking:
        cmd.insert(1, "-DLEAKING")
    result = run(cmd, timeout=30)
    assert result.returncode == 0, f"Could not compile verifier probe:\n{result.stderr}"


def check_regression_script_is_genuine():
    tempdir = tempfile.mkdtemp(prefix="sensor_probe_")
    backup = os.path.join(tempdir, "real_libsensor.so")
    trace = os.path.join(tempdir, "trace.txt")
    probe = os.path.join(tempdir, "probe.so")
    saved_log = EXPECTED_LOG
    shutil.copy2(LIBRARY, backup)
    try:
        compile_probe(probe, leaking=False)
        shutil.copy2(probe, LIBRARY)
        if os.path.exists(LOG):
            os.remove(LOG)
        env = os.environ.copy()
        env["TRACE_PATH"] = trace
        result = run(["python3", SCRIPT], cwd=ROOT, env=env, timeout=60)
        assert result.returncode == 0, \
            f"Regression script failed against a compatible instrumented library:\n{result.stdout}\n{result.stderr}"
        assert os.path.exists(trace), "Regression script did not load/call libsensor.so."
        with open(trace) as f:
            large_calls, small_calls = map(int, f.read().split())
        assert large_calls >= 1, "Regression script did not call (60000, 50000)."
        assert small_calls >= 10000, "Regression script did not perform 10,000 small calls."
        assert os.path.exists(LOG) and open(LOG).read().strip() == EXPECTED_LOG, \
            "Regression script did not report success for the non-leaking probe."

        # A real memory regression test must reject an implementation that leaks
        # well over the allowed 10 MB during its 10,000 calls.
        compile_probe(probe, leaking=True)
        shutil.copy2(probe, LIBRARY)
        if os.path.exists(LOG):
            os.remove(LOG)
        env.pop("TRACE_PATH", None)
        result = run(["python3", SCRIPT], cwd=ROOT, env=env, timeout=60)
        falsely_passed = (result.returncode == 0 and os.path.exists(LOG)
                          and open(LOG).read().strip() == EXPECTED_LOG)
        assert not falsely_passed, \
            "test_regression.py reports success despite an intentional >10 MB leak."
    finally:
        shutil.copy2(backup, LIBRARY)
        with open(LOG, "w") as f:
            f.write(saved_log)
        shutil.rmtree(tempdir, ignore_errors=True)


def main():
    check_sources_and_build()
    check_large_call()
    check_memory_behavior()
    check_regression_script_with_real_library()
    check_regression_script_is_genuine()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
