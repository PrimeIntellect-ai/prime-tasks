#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import importlib
import math
import os
import random
import re
import runpy
import subprocess
import sys

import pytest

PROJECT = "/home/user/project"
EXT = os.path.join(PROJECT, "ext")
LIB = os.path.join(EXT, "libwaf.so")


@pytest.fixture(scope="session", autouse=True)
def build_with_supplied_makefile():
    makefile = os.path.join(EXT, "Makefile")
    assert os.path.isfile(makefile), "ext/Makefile is missing"
    if os.path.exists(LIB):
        os.remove(LIB)
    result = subprocess.run(
        ["make"], cwd=EXT, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(LIB), "Running make did not produce ext/libwaf.so"


def load_lib():
    lib = ctypes.CDLL(LIB)
    lib.check_xss.argtypes = [ctypes.c_char_p, ctypes.c_int]
    lib.check_xss.restype = ctypes.c_int
    lib.check_sqli_c.argtypes = [ctypes.c_char_p]
    lib.check_sqli_c.restype = ctypes.c_int
    return lib


def test_libwaf_so_exists_and_is_elf():
    assert os.path.exists(LIB), f"{LIB} does not exist."
    with open(LIB, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"{LIB} is not a valid ELF file."
    load_lib()


def test_waf_c_vulnerability_fixed_source_assertion():
    waf_c_path = os.path.join(EXT, "waf.c")
    assert os.path.exists(waf_c_path), f"{waf_c_path} does not exist."
    with open(waf_c_path, "r") as f:
        content = f.read()
    assert "i <= len" not in content, "The OOB read vulnerability (i <= len) was not fixed in waf.c."


def test_waf_c_contains_check_sqli_c():
    waf_c_path = os.path.join(EXT, "waf.c")
    with open(waf_c_path, "r") as f:
        content = f.read()
    assert "check_sqli_c" in content, "check_sqli_c function is missing from waf.c."
    assert hasattr(load_lib(), "check_sqli_c"), "check_sqli_c not exported in libwaf.so"


def test_xss_behavior_and_guard_page_memory_safety(tmp_path):
    lib = load_lib()
    fixed = [(b"hello <script", 1), (b"hello world", 0), (b"<s", 1), (b"<", 0), (b"", 0)]
    for payload, expected in fixed:
        assert lib.check_xss(payload, len(payload)) == expected

    rng = random.SystemRandom()
    alphabet = b"abcXYZ<>sS 123"
    for _ in range(100):
        payload = bytes(rng.choice(alphabet) for _ in range(rng.randrange(0, 100)))
        expected = 1 if b"<s" in payload else 0
        assert lib.check_xss(payload, len(payload)) == expected

    helper = tmp_path / "guard_xss.c"
    exe = tmp_path / "guard_xss"
    helper.write_text(r'''
#include <dlfcn.h>
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>

typedef int (*check_fn)(const char *, int);
int main(int argc, char **argv) {
    if (argc != 2) return 10;
    void *h = dlopen(argv[1], RTLD_NOW);
    if (!h) return 11;
    check_fn check = (check_fn)dlsym(h, "check_xss");
    if (!check) return 12;
    long page = sysconf(_SC_PAGESIZE);
    char *mem = mmap(NULL, page * 2, PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mem == MAP_FAILED) return 13;
    if (mprotect(mem + page, page, PROT_NONE) != 0) return 14;

    /* Each payload ends exactly at an inaccessible page. A correct function
       may inspect only bytes inside the declared length. */
    for (int len = 0; len <= 64; ++len) {
        char *p = mem + page - len;
        if (len) {
            memset(p, 'A', len);
            p[len - 1] = '<';
        }
        if (check(p, len) != 0) return 20;
    }
    char *p = mem + page - 2;
    p[0] = '<'; p[1] = 's';
    if (check(p, 2) != 1) return 21;
    return 0;
}
''')
    compiled = subprocess.run(
        ["gcc", "-O0", str(helper), "-ldl", "-o", str(exe)],
        capture_output=True, text=True
    )
    assert compiled.returncode == 0, compiled.stderr
    result = subprocess.run([str(exe), LIB], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (
        f"check_xss failed guard-page safety test (return code {result.returncode}); "
        "it likely read outside the supplied payload length"
    )


def test_check_sqli_c_matches_python_logic_on_generated_inputs():
    if PROJECT not in sys.path:
        sys.path.insert(0, PROJECT)
    py_waf = importlib.import_module("py_waf")
    lib = load_lib()

    rng = random.SystemRandom()
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 '_-*;/"
    payloads = [
        "admin' OR 1=1 -- UNION SELECT * FROM users",
        "hello world",
        "UNION SELECT",
        "union select",
        "UnIoN SeLeCt",
        "UNION  SELECT",
        "UNION\tSELECT",
        "xUNION SELECTy",
        "SELECT UNION",
        "",
    ]
    for _ in range(250):
        base = "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 180)))
        if rng.randrange(2):
            signature = "".join(rng.choice((c.lower(), c.upper())) for c in "UNION SELECT")
            at = rng.randrange(len(base) + 1)
            base = base[:at] + signature + base[at:]
        payloads.append(base)

    for payload in payloads:
        expected = int(py_waf.check_sqli(payload))
        actual = lib.check_sqli_c(payload.encode("ascii"))
        assert actual in (0, 1)
        assert actual == expected, f"Mismatch for generated payload {payload!r}"


def test_test_fixture_uses_mock_and_unittest_passes():
    test_path = os.path.join(PROJECT, "tests", "test_waf.py")
    assert os.path.isfile(test_path)
    source = open(test_path, encoding="utf-8").read()
    assert "mock" in source and "patch" in source, "tests/test_waf.py does not use unittest.mock.patch"
    assert "status_code" in source and "200" in source
    assert re.search(r'["\']OK["\']', source)

    result = subprocess.run(
        ["python3", "-m", "unittest", "tests.test_waf"],
        cwd=PROJECT, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"Unittests failed:\n{result.stdout}\n{result.stderr}"


def test_benchmark_executes_both_functions_exactly_100000_times(monkeypatch):
    benchmark = os.path.join(PROJECT, "benchmark.py")
    assert os.path.isfile(benchmark), "benchmark.py does not exist"
    source = open(benchmark, encoding="utf-8").read()
    ast.parse(source)

    if PROJECT not in sys.path:
        sys.path.insert(0, PROJECT)
    py_waf = importlib.import_module("py_waf")
    real_python = py_waf.check_sqli
    real_cdll = ctypes.CDLL
    counts = {"python": 0, "c": 0}

    def counted_python(payload):
        counts["python"] += 1
        return real_python(payload)

    class CountedFunction:
        def __init__(self, fn):
            object.__setattr__(self, "fn", fn)
        def __call__(self, *args):
            counts["c"] += 1
            return self.fn(*args)
        def __getattr__(self, name):
            return getattr(self.fn, name)
        def __setattr__(self, name, value):
            if name == "fn":
                object.__setattr__(self, name, value)
            else:
                setattr(self.fn, name, value)

    class CountedLibrary:
        def __init__(self, *args, **kwargs):
            self._real = real_cdll(*args, **kwargs)
            self.check_sqli_c = CountedFunction(self._real.check_sqli_c)
        def __getattr__(self, name):
            return getattr(self._real, name)

    monkeypatch.setattr(py_waf, "check_sqli", counted_python)
    monkeypatch.setattr(ctypes, "CDLL", CountedLibrary)
    monkeypatch.setattr(ctypes.cdll, "LoadLibrary", lambda *a, **k: CountedLibrary(*a, **k))

    old_cwd = os.getcwd()
    try:
        os.chdir(PROJECT)
        runpy.run_path(benchmark, run_name="__main__")
    finally:
        os.chdir(old_cwd)

    assert counts["python"] == 100000, f"Python check_sqli was called {counts['python']} times, not 100000"
    assert counts["c"] == 100000, f"C check_sqli_c was called {counts['c']} times, not 100000"


def test_benchmark_log_generated_by_running_script_and_correct():
    benchmark = os.path.join(PROJECT, "benchmark.py")
    log_path = os.path.join(PROJECT, "bench_results.log")
    if os.path.exists(log_path):
        os.remove(log_path)

    result = subprocess.run(
        ["python3", benchmark], cwd=PROJECT, capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f"benchmark.py failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(log_path), "Running benchmark.py did not generate bench_results.log"

    content = open(log_path, encoding="utf-8").read()
    pattern = re.compile(
        r"\APYTHON_TIME: ([0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)\n"
        r"C_TIME: ([0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)\n"
        r"C_IS_FASTER: (True|False)\n?\Z"
    )
    match = pattern.fullmatch(content)
    assert match, "bench_results.log does not have exactly the required format"
    python_time = float(match.group(1))
    c_time = float(match.group(2))
    faster = match.group(3) == "True"
    assert math.isfinite(python_time) and python_time > 0
    assert math.isfinite(c_time) and c_time > 0
    assert faster == (c_time < python_time), "C_IS_FASTER does not agree with the recorded timings"
    assert faster, "C_IS_FASTER: True missing from benchmark log."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
