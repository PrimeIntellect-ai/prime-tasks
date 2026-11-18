#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import stat
import subprocess
from concurrent.futures import ThreadPoolExecutor

PROJECT_DIR = "/home/user/project"

def test_directory_structure():
    expected_dirs = ["src", "cmd", "lib", "bin"]
    for d in expected_dirs:
        dir_path = os.path.join(PROJECT_DIR, d)
        assert os.path.isdir(dir_path), f"Directory {dir_path} is missing."

def test_source_files_exist():
    expected_files = [
        "src/lib.c",
        "src/lib.h",
        "src/magic.s",
        "cmd/main.go"
    ]
    for f in expected_files:
        file_path = os.path.join(PROJECT_DIR, f)
        assert os.path.isfile(file_path), f"Source file {file_path} is missing."

def test_c_bug_fixed():
    lib_c_path = os.path.join(PROJECT_DIR, "src/lib.c")
    assert os.path.isfile(lib_c_path), f"{lib_c_path} is missing."
    with open(lib_c_path, 'r') as f:
        content = f.read()

    assert "i <= 10" not in content, "The out-of-bounds memory access bug in lib.c (i <= 10) was not fixed."

def test_compiled_artifacts():
    so_path = os.path.join(PROJECT_DIR, "lib/libmyc.so")
    app_path = os.path.join(PROJECT_DIR, "bin/app")

    assert os.path.isfile(so_path), f"Shared library {so_path} is missing."
    assert os.path.isfile(app_path), f"Go executable {app_path} is missing."

    st = os.stat(app_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Go binary {app_path} is not executable."

def test_output_txt():
    output_path = os.path.join(PROJECT_DIR, "output.txt")
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    with open(output_path, 'r') as f:
        content = f.read().strip()

    assert content == "750", f"Expected output.txt to contain '750', but got '{content}'."

def test_makefile_library_and_application_behavior():
    makefile = os.path.join(PROJECT_DIR, "Makefile")
    assert os.path.isfile(makefile), "Makefile is missing."
    text = open(makefile, encoding="utf-8").read()
    for required in ("src/lib.c", "src/magic.s", "lib/libmyc.so"):
        assert required in text, f"Makefile does not build {required}."

    so_path = os.path.join(PROJECT_DIR, "lib/libmyc.so")
    app_path = os.path.join(PROJECT_DIR, "bin/app")
    output_path = os.path.join(PROJECT_DIR, "output.txt")

    os.remove(so_path)
    subprocess.run(["make", "-C", PROJECT_DIR], check=True, timeout=60)
    assert os.path.isfile(so_path), "Makefile did not recreate lib/libmyc.so."
    assert open(so_path, "rb").read(4) == b"\x7fELF", "libmyc.so is not an ELF shared library."
    assert open(app_path, "rb").read(4) == b"\x7fELF", "bin/app is not a compiled executable."

    build_info = subprocess.run(
        ["go", "version", "-m", app_path], capture_output=True, text=True, timeout=15
    )
    assert build_info.returncode == 0 and "go1." in build_info.stdout, "bin/app is not a Go binary."

    lib = ctypes.CDLL(so_path)
    lib.process.argtypes = []
    lib.process.restype = ctypes.c_int
    assert lib.process() == 50, "process() must return 50."
    with ThreadPoolExecutor(max_workers=15) as pool:
        results = list(pool.map(lambda _: lib.process(), range(30)))
    assert results == [50] * 30, "The C library is not safe or correct under concurrent calls."

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = os.path.join(PROJECT_DIR, "lib")
    if os.path.exists(output_path):
        os.remove(output_path)
    subprocess.run([app_path], cwd=PROJECT_DIR, env=env, check=True, timeout=30)
    assert open(output_path).read().strip() == "750", "Running bin/app did not generate the expected total."

    shim_c = "/tmp/verifier_shim.c"
    shim_log = "/tmp/verifier_shim.log"
    shim_so = "/tmp/verifier_libmyc.so"
    backup_so = "/tmp/verifier_real_libmyc.so"
    for path in (shim_log, shim_so, backup_so):
        if os.path.exists(path):
            os.remove(path)
    with open(shim_c, "w") as f:
        f.write(r'''
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static int calls = 0, active = 0, maximum = 0;
int process(void) {
    int id;
    pthread_mutex_lock(&lock);
    id = ++calls;
    active++;
    if (active > maximum) maximum = active;
    pthread_mutex_unlock(&lock);
    usleep(500000);
    pthread_mutex_lock(&lock);
    active--;
    pthread_mutex_unlock(&lock);
    return id;
}
__attribute__((destructor)) static void report(void) {
    FILE *f = fopen("/tmp/verifier_shim.log", "w");
    if (f) { fprintf(f, "%d %d\n", calls, maximum); fclose(f); }
}
''')
    subprocess.run(["gcc", "-shared", "-fPIC", "-pthread", shim_c, "-o", shim_so], check=True, timeout=30)

    os.rename(so_path, backup_so)
    try:
        subprocess.run(["cp", shim_so, so_path], check=True)
        if os.path.exists(output_path):
            os.remove(output_path)
        subprocess.run([app_path], cwd=PROJECT_DIR, env=env, check=True, timeout=30)
        assert os.path.isfile(shim_log), "bin/app did not load and invoke libmyc.so."
        calls, maximum = map(int, open(shim_log).read().split())
        assert calls == 15, f"Expected exactly 15 calls to process(), observed {calls}."
        assert maximum == 15, f"Expected 15 process() calls to run concurrently, maximum overlap was {maximum}."
        assert open(output_path).read().strip() == "120", "Application did not sum all 15 instrumented call results."
    finally:
        if os.path.exists(so_path):
            os.remove(so_path)
        os.rename(backup_so, so_path)

    subprocess.run([app_path], cwd=PROJECT_DIR, env=env, check=True, timeout=30)
    assert open(output_path).read().strip() == "750"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
