#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import subprocess
import tempfile
import time

APP = "/app"
RUST = "/app/divsum-0.1.0"
WORKER = "/app/bin/worker"
LIB = "/app/divsum-0.1.0/target/release/libdivsum.so"


def compute_sum_of_divisors(n: int) -> int:
    if n == 0:
        return 0
    total = 0
    i = 1
    while i <= n // i:
        if n % i == 0:
            total += i
            if i != n // i:
                total += n // i
        i += 1
    return total


def worker_env():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = RUST + "/target/release:" + env.get("LD_LIBRARY_PATH", "")
    return env


def test_01_output_correctness():
    assert os.path.isfile("/app/input.json"), "Input file missing"
    assert os.path.isfile("/app/output.json"), "Output file missing"

    with open("/app/input.json", "r") as f:
        inputs = json.load(f)
    with open("/app/output.json", "r") as f:
        outputs = json.load(f)

    for n in inputs:
        expected = compute_sum_of_divisors(n)
        actual = outputs.get(str(n))
        assert actual == expected, (
            f"Incorrect sum of divisors for {n}: expected {expected}, got {actual}"
        )


def test_02_required_sources_and_build_system():
    cargo_toml = os.path.join(RUST, "Cargo.toml")
    rust_source = os.path.join(RUST, "src", "lib.rs")
    go_source = "/app/go-worker/main.go"
    go_mod = "/app/go-worker/go.mod"
    makefile = "/app/Makefile"

    for path in (cargo_toml, rust_source, go_source, go_mod, makefile):
        assert os.path.isfile(path), f"Required file missing: {path}"

    cargo_text = open(cargo_toml, encoding="utf-8").read()
    assert re.search(r"crate-type\s*=\s*\[[^\]]*[\"']cdylib[\"']", cargo_text, re.S), \
        "Cargo.toml does not configure the Rust library as a cdylib"

    go_text = open(go_source, encoding="utf-8").read()
    assert re.search(r'import\s+(?:\([^)]*)?[\"`]C[\"`]', go_text, re.S), \
        "Go worker does not use CGO"

    make_text = open(makefile, encoding="utf-8").read()
    assert re.search(r"(?m)^build\s*:", make_text), "Makefile has no build target"

    # Ensure the build target really creates both demanded artifacts rather than
    # merely relying on files that happened to exist before verification.
    for path in (WORKER, LIB):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["make", "-B", "build"], cwd=APP, env=worker_env(),
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=240
    )
    assert result.returncode == 0, "make build failed:\n" + result.stdout[-4000:]
    assert os.path.isfile(WORKER) and os.access(WORKER, os.X_OK), \
        "Makefile did not create an executable /app/bin/worker"
    assert os.path.isfile(LIB), "Makefile did not create the release Rust shared library"

    lib_file = subprocess.run(["file", LIB], capture_output=True, text=True, check=True).stdout
    assert "shared object" in lib_file, "Rust output is not a shared object"

    symbols = subprocess.run(["nm", "-D", LIB], capture_output=True, text=True, check=True).stdout
    assert re.search(r"\bsum_of_divisors\b", symbols), \
        "Rust shared library does not export sum_of_divisors"

    linked = subprocess.run(
        ["ldd", WORKER], env=worker_env(), capture_output=True, text=True, check=True
    ).stdout
    assert "libdivsum.so" in linked and "libdivsum.so => not found" not in linked, \
        "Go worker is not dynamically linked to the Rust divsum library"


def test_03_concurrency_speedup():
    assert os.path.isfile(WORKER), "Worker binary missing"
    env = worker_env()

    env["GOMAXPROCS"] = "1"
    start_serial = time.time()
    subprocess.run(
        [WORKER], env=env, check=True, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, timeout=240
    )
    serial_time = time.time() - start_serial

    env["GOMAXPROCS"] = "4"
    start_concurrent = time.time()
    subprocess.run(
        [WORKER], env=env, check=True, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, timeout=240
    )
    concurrent_time = time.time() - start_concurrent

    speedup = serial_time / concurrent_time
    assert speedup >= 2.0, (
        f"Speedup too low: {speedup:.2f} (Serial: {serial_time:.2f}s, "
        f"Concurrent: {concurrent_time:.2f}s). Expected at least 2.0."
    )


def test_04_worker_uses_ffi_on_fresh_inputs_with_four_call_limit():
    shim_source = r'''
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdatomic.h>

static _Atomic int active_calls = 0;

uint64_t sum_of_divisors(uint64_t n) {
    int active = atomic_fetch_add(&active_calls, 1) + 1;
    const char *path = getenv("DIVSUM_AUDIT_LOG");
    if (path) {
        int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) {
            char buf[32];
            int len = snprintf(buf, sizeof(buf), "%d\n", active);
            write(fd, buf, (size_t)len);
            close(fd);
        }
    }

    /* Keep calls overlapping long enough to observe the actual semaphore. */
    usleep(80000);

    uint64_t total = 0;
    if (n != 0) {
        for (uint64_t i = 1; i <= n / i; ++i) {
            if (n % i == 0) {
                total += i;
                uint64_t other = n / i;
                if (other != i) total += other;
            }
        }
    }
    atomic_fetch_sub(&active_calls, 1);
    return total;
}
'''
    tempdir = tempfile.mkdtemp(prefix="divsum-audit-")
    shim_c = os.path.join(tempdir, "audit.c")
    shim_so = os.path.join(tempdir, "libaudit.so")
    audit_log = os.path.join(tempdir, "calls.log")
    with open(shim_c, "w", encoding="utf-8") as f:
        f.write(shim_source)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", "-o", shim_so, shim_c], check=True
    )

    input_path = "/app/input.json"
    output_path = "/app/output.json"
    old_input = open(input_path, "rb").read() if os.path.exists(input_path) else None
    old_output = open(output_path, "rb").read() if os.path.exists(output_path) else None

    try:
        rng = random.SystemRandom()
        values = set()
        while len(values) < 16:
            values.add(rng.randrange(100000, 2000000))
        inputs = list(values)
        rng.shuffle(inputs)
        with open(input_path, "w", encoding="utf-8") as f:
            json.dump(inputs, f)
        try:
            os.remove(output_path)
        except FileNotFoundError:
            pass

        env = worker_env()
        env["GOMAXPROCS"] = "4"
        env["LD_PRELOAD"] = shim_so
        env["DIVSUM_AUDIT_LOG"] = audit_log
        run = subprocess.run(
            [WORKER], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=30
        )
        assert run.returncode == 0, f"Worker failed on fresh inputs: {run.stderr[-2000:]}"
        assert os.path.isfile(output_path), "Worker did not create /app/output.json"

        with open(output_path, "r", encoding="utf-8") as f:
            actual = json.load(f)
        expected = {str(n): compute_sum_of_divisors(n) for n in inputs}
        assert actual == expected, "Worker output is incorrect for verifier-generated inputs"

        assert os.path.isfile(audit_log), \
            "No calls reached the dynamically linked sum_of_divisors function"
        with open(audit_log, "r", encoding="utf-8") as f:
            observed = [int(line.strip()) for line in f if line.strip()]
        assert len(observed) == len(inputs), \
            f"Expected one Rust FFI call per input, observed {len(observed)} for {len(inputs)} inputs"
        assert max(observed) <= 4, \
            f"More than four Rust FFI calls overlapped (observed {max(observed)})"
        assert max(observed) >= 2, \
            "Rust FFI calls did not execute concurrently"
    finally:
        if old_input is None:
            try: os.remove(input_path)
            except FileNotFoundError: pass
        else:
            with open(input_path, "wb") as f: f.write(old_input)
        if old_output is None:
            try: os.remove(output_path)
            except FileNotFoundError: pass
        else:
            with open(output_path, "wb") as f: f.write(old_output)
        shutil.rmtree(tempdir, ignore_errors=True)
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
