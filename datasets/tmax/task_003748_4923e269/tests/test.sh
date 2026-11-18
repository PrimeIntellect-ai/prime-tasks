#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import sys
import textwrap

import pytest
from packaging.version import Version

BASE = "/home/user/ci_pipeline"
PKG = os.path.join(BASE, "math_accel")
VERSION_SCRIPT = os.path.join(BASE, "version_check.py")
VERSION_OUT = os.path.join(BASE, "version_out.txt")
BENCHMARK = os.path.join(BASE, "benchmark.py")
BENCHMARK_RESULTS = os.path.join(BASE, "benchmark_results.txt")
SORTED_RESULTS = os.path.join(BASE, "sorted_results.txt")

EXPECTED_BENCHMARK = '''import sys
import time
sys.path.insert(0, '/home/user/ci_pipeline/math_accel')

try:
    from math_accel.core import fast_pow
    c_ext_loaded = True
except ImportError as e:
    print(f"Failed to load C extension: {e}")
    sys.exit(1)

def pure_py_pow(base, exp):
    return base ** exp

def run_bench():
    # Pure Py
    start = time.time()
    for _ in range(5000000):
        pure_py_pow(2.0, 10.0)
    py_time = time.time() - start

    # C Ext
    start = time.time()
    for _ in range(5000000):
        fast_pow(2.0, 10.0)
    c_time = time.time() - start

    with open('/home/user/ci_pipeline/benchmark_results.txt', 'w') as f:
        f.write(f"PurePython,{py_time:.6f}\\n")
        f.write(f"CExtension,{c_time:.6f}\\n")

if __name__ == '__main__':
    run_bench()
'''


def test_setup_py_modified():
    setup_path = os.path.join(PKG, "setup.py")
    assert os.path.isfile(setup_path), f"File {setup_path} does not exist."
    with open(setup_path) as f:
        content = f.read()
    assert re.search(r"libraries\s*=\s*\[\s*['\"]m['\"]\s*\]", content), \
        "setup.py does not appear to link against the math library (libraries=['m'] is missing)."


def test_extension_built_inplace():
    ext_dir = os.path.join(PKG, "math_accel")
    assert os.path.isdir(ext_dir), f"Directory {ext_dir} does not exist."
    so_files = [f for f in os.listdir(ext_dir) if f.endswith('.so')]
    assert so_files, "The C extension (.so file) was not found in the math_accel/math_accel directory. Was it built in-place?"

    probe = textwrap.dedent('''
        import importlib.machinery
        import math
        import random
        import sys
        sys.path.insert(0, r"/home/user/ci_pipeline/math_accel")
        import math_accel.core as core
        assert any(core.__file__.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), core.__file__
        rng = random.SystemRandom()
        cases = [(2.0, 10.0), (9.0, 0.5), (5.0, -2.0)]
        cases += [(rng.uniform(0.2, 8.0), rng.uniform(-3.0, 4.0)) for _ in range(8)]
        for base, exp in cases:
            got = core.fast_pow(base, exp)
            expected = math.pow(base, exp)
            assert isinstance(got, float)
            assert math.isclose(got, expected, rel_tol=1e-12, abs_tol=1e-12), (base, exp, got, expected)
    ''')
    subprocess.run([sys.executable, "-c", probe], check=True, timeout=30)


def test_version_output():
    assert os.path.isfile(VERSION_OUT), f"File {VERSION_OUT} does not exist."
    with open(VERSION_OUT) as f:
        content = f.read().strip()
    assert content == "1.2.1-beta.11", \
        f"version_out.txt contains '{content}', but expected '1.2.1-beta.11'."


def test_version_script_semantics_and_arity():
    assert os.path.isfile(VERSION_SCRIPT), f"File {VERSION_SCRIPT} does not exist."

    rng = random.SystemRandom()
    n1 = rng.randrange(2, 1000)
    n2 = n1 + rng.randrange(1, 1000)
    cases = [
        ("1.0.0-alpha.2", "1.0.0-alpha.10"),
        ("2.4.0-rc.9", "2.4.0"),
        ("3.1.7-beta.8+build.999", "3.1.7-beta.12+build.1"),
        (f"7.2.0-alpha.{n1}", f"7.2.0-alpha.{n2}"),
    ]

    try:
        for left, right in cases:
            expected = left if Version(left) > Version(right) else right
            subprocess.run([sys.executable, VERSION_SCRIPT, left, right], check=True, timeout=15)
            with open(VERSION_OUT) as f:
                assert f.read().strip() == expected

        for bad_args in [[], ["1.0.0"], ["1.0.0", "2.0.0", "3.0.0"]]:
            proc = subprocess.run([sys.executable, VERSION_SCRIPT, *bad_args], timeout=15)
            assert proc.returncode != 0, f"version_check.py accepted {len(bad_args)} positional arguments"
    finally:
        subprocess.run(
            [sys.executable, VERSION_SCRIPT, "1.2.1-beta.2", "1.2.1-beta.11"],
            check=True,
            timeout=15,
        )


def parse_results(path):
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path) as f:
        lines = f.read().splitlines()
    assert lines and all(lines), f"{path} contains blank or no result lines."

    parsed = []
    for line in lines:
        parts = line.split(',')
        assert len(parts) == 2, f"Line '{line}' is not in 'Method,Time' format."
        method = parts[0]
        try:
            value = float(parts[1])
        except ValueError:
            pytest.fail(f"Could not parse time value in line: '{line}'")
        assert math.isfinite(value) and value >= 0, f"Invalid execution time in line '{line}'"
        parsed.append((method, value, line))
    return parsed


def test_benchmark_executes_with_extension(tmp_path):
    assert os.path.isfile(BENCHMARK), f"File {BENCHMARK} does not exist."
    with open(BENCHMARK) as f:
        assert f.read() == EXPECTED_BENCHMARK, "The supplied benchmark.py must not be replaced or modified."

    redirected = tmp_path / "fresh_benchmark_results.txt"
    runner = textwrap.dedent(f'''
        import builtins
        import os
        import runpy
        real_open = builtins.open
        def redirected_open(path, *args, **kwargs):
            if os.fspath(path) == {BENCHMARK_RESULTS!r}:
                path = {str(redirected)!r}
            return real_open(path, *args, **kwargs)
        builtins.open = redirected_open
        runpy.run_path({BENCHMARK!r}, run_name="__main__")
    ''')
    subprocess.run([sys.executable, "-c", runner], check=True, timeout=120)
    fresh = parse_results(str(redirected))
    assert len(fresh) == 2
    assert {row[0] for row in fresh} == {"PurePython", "CExtension"}


def test_sorted_results():
    source = parse_results(BENCHMARK_RESULTS)
    results = parse_results(SORTED_RESULTS)

    assert len(results) == 2, f"sorted_results.txt should contain exactly 2 lines, found {len(results)}."
    assert len(source) == 2, f"benchmark_results.txt should contain exactly 2 lines, found {len(source)}."
    assert {row[0] for row in source} == {"PurePython", "CExtension"}

    expected_lines = [row[2] for row in sorted(source, key=lambda row: row[1])]
    actual_lines = [row[2] for row in results]
    assert actual_lines == expected_lines, \
        "sorted_results.txt is not an exact numerical-time sort of benchmark_results.txt."

    assert results[0][1] <= results[1][1], "The results are not sorted by execution time in ascending order."
    assert results[0][0] == "CExtension", "CExtension should be faster than PurePython and appear first."
    assert results[1][0] == "PurePython", "PurePython should appear second."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
