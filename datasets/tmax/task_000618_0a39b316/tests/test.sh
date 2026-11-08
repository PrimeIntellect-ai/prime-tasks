#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import importlib.machinery
import json
import os
import random
import re
import shutil
import string
import subprocess
import sys
import sysconfig
import tempfile

PROJECT = "/home/user/api_scanner"
VERIFIED_MODULE_DIR = "/tmp/verified_fast_fuzzer"


def test_extracted_payloads():
    path = "/home/user/api_scanner/extracted_payloads.txt"
    assert os.path.exists(path), f"File {path} does not exist. Did you extract the payloads from the video?"

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["1a2b3c", "4d5e6f", "7g8h9i", "0j1k2l", "3m4n5o"]
    assert lines == expected, f"Extracted payloads do not match the expected values from the video.\nExpected: {expected}\nGot: {lines}"


def test_scanner_import_order():
    path = "/home/user/api_scanner/scanner.py"
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    fast_fuzzer_idx = content.find("import fast_fuzzer")
    requests_idx = content.find("import requests")
    ssl_idx = content.find("import ssl")

    assert fast_fuzzer_idx != -1, "import fast_fuzzer not found in scanner.py"
    assert requests_idx != -1, "import requests not found in scanner.py"
    assert ssl_idx != -1, "import ssl not found in scanner.py"

    assert fast_fuzzer_idx > requests_idx, "fast_fuzzer must be imported AFTER requests to fix the CI monkey-patching bug."
    assert fast_fuzzer_idx > ssl_idx, "fast_fuzzer must be imported AFTER ssl to fix the CI monkey-patching bug."


def test_compile_rust_extension_release():
    cargo_toml = os.path.join(PROJECT, "Cargo.toml")
    lib_rs = os.path.join(PROJECT, "src", "lib.rs")
    assert os.path.isfile(cargo_toml), "Cargo.toml does not exist."
    assert os.path.isfile(lib_rs), "src/lib.rs does not exist."

    clean = subprocess.run(
        ["cargo", "clean"], cwd=PROJECT, capture_output=True, text=True, timeout=120
    )
    assert clean.returncode == 0, f"cargo clean failed:\n{clean.stdout}\n{clean.stderr}"

    build = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert build.returncode == 0, f"Rust extension failed to compile in release mode:\n{build.stdout}\n{build.stderr}"

    built = os.path.join(PROJECT, "target", "release", "libfast_fuzzer.so")
    assert os.path.isfile(built), f"Release build did not produce {built}."
    with open(built, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The built fast_fuzzer artifact is not an ELF shared library."

    shutil.rmtree(VERIFIED_MODULE_DIR, ignore_errors=True)
    os.makedirs(VERIFIED_MODULE_DIR)
    suffix = sysconfig.get_config_var("EXT_SUFFIX") or ".so"
    verified = os.path.join(VERIFIED_MODULE_DIR, "fast_fuzzer" + suffix)
    shutil.copy2(built, verified)


def test_benchmark_performance():
    path = "/home/user/api_scanner/benchmark.py"
    assert os.path.exists(path), f"Benchmark script {path} does not exist."

    env = os.environ.copy()
    if "PYTHONPATH" in env:
        env["PYTHONPATH"] = f"/home/user/api_scanner:{env['PYTHONPATH']}"
    else:
        env["PYTHONPATH"] = "/home/user/api_scanner"

    result = subprocess.run([sys.executable, path], capture_output=True, text=True, env=env)
    assert result.returncode == 0, f"benchmark.py failed with error:\n{result.stderr}"

    output = result.stdout
    match = re.search(r"Throughput:\s*([0-9]*\.?[0-9]+)\s*seconds", output)
    assert match is not None, f"Could not find 'Throughput: <float> seconds' in benchmark stdout.\nOutput was:\n{output}"

    execution_time = float(match.group(1))
    threshold = 0.25
    assert execution_time <= threshold, f"Benchmark execution time {execution_time} exceeds threshold of {threshold} seconds. The Rust extension might not be fully optimized or built in release mode."


def test_benchmark_actually_processes_all_payloads():
    path = os.path.join(PROJECT, "benchmark.py")
    expected = ["1a2b3c", "4d5e6f", "7g8h9i", "0j1k2l", "3m4n5o"]
    driver = r'''
import contextlib
import io
import json
import runpy
import sys
import types

expected = json.loads(sys.argv[2])
state = {"count": 0}
module = types.ModuleType("fast_fuzzer")

def process_payload(payload):
    index = state["count"]
    wanted = expected[index % len(expected)]
    if payload != wanted:
        raise AssertionError("benchmark payload/order mismatch at call %d: expected %r, got %r" % (index, wanted, payload))
    state["count"] += 1
    return sum(ord(c) for c in payload)

module.process_payload = process_payload
sys.modules["fast_fuzzer"] = module
output = io.StringIO()
with contextlib.redirect_stdout(output):
    runpy.run_path(sys.argv[1], run_name="__main__")
if state["count"] != 50000:
    raise AssertionError("benchmark called process_payload %d times, expected 50000" % state["count"])
print(output.getvalue(), end="")
'''
    result = subprocess.run(
        [sys.executable, "-c", driver, path, json.dumps(expected)],
        cwd="/tmp",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"benchmark.py does not process the five payloads 10,000 times in sequence:\n{result.stderr}"
    match = re.search(r"Throughput:\s*([0-9]*\.?[0-9]+)\s*seconds", result.stdout)
    assert match is not None, f"Could not find benchmark throughput output. Output was:\n{result.stdout}"


def test_rust_extension_directly():
    assert os.path.isdir(VERIFIED_MODULE_DIR), "Verified release extension was not prepared."

    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + "_-:/"
    payloads = [
        "",
        "1a2b3c",
        "4d5e6f",
        "7g8h9i",
        "0j1k2l",
        "3m4n5o",
        "éλ漢字🙂",
        "a\\0b",
    ]
    for _ in range(80):
        payloads.append("".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 80))))
    expected = [sum(ord(c) for c in payload) for payload in payloads]

    code = r'''
import importlib.machinery
import json
import os
import sys
import time

payloads = json.loads(sys.stdin.read())
import fast_fuzzer
origin = os.path.realpath(fast_fuzzer.__file__)
if not isinstance(fast_fuzzer.__loader__, importlib.machinery.ExtensionFileLoader):
    raise AssertionError("fast_fuzzer was not loaded as a compiled Python extension: " + origin)
results = [fast_fuzzer.process_payload(p) for p in payloads]
critical = ["1a2b3c", "4d5e6f", "7g8h9i", "0j1k2l", "3m4n5o"]
start = time.perf_counter()
for _ in range(10000):
    for p in critical:
        fast_fuzzer.process_payload(p)
elapsed = time.perf_counter() - start
print(json.dumps({"results": results, "elapsed": elapsed, "origin": origin}))
'''
    env = os.environ.copy()
    env["PYTHONPATH"] = VERIFIED_MODULE_DIR
    result = subprocess.run(
        [sys.executable, "-c", code],
        input=json.dumps(payloads),
        capture_output=True,
        text=True,
        cwd="/tmp",
        env=env,
        timeout=30,
    )
    assert result.returncode == 0, f"Failed to import and run the freshly compiled fast_fuzzer extension.\nError:\n{result.stderr}"

    data = json.loads(result.stdout.strip())
    assert os.path.commonpath([os.path.realpath(data["origin"]), VERIFIED_MODULE_DIR]) == VERIFIED_MODULE_DIR, "The test did not load the freshly compiled release extension."
    assert data["results"] == expected, f"process_payload returned incorrect values.\nExpected: {expected}\nGot: {data['results']}"

    execution_time = float(data["elapsed"])
    threshold = 0.25
    assert execution_time <= threshold, f"Direct execution time {execution_time} exceeds threshold of {threshold} seconds. Ensure lib.rs borrows &str and is built in release mode."


def test_lib_rs_optimized():
    path = "/home/user/api_scanner/src/lib.rs"
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "&str" in content, "lib.rs does not seem to use &str for string borrowing. You should borrow the string slice from Python instead of taking ownership."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
