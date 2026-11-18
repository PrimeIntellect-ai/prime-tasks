#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import time
import pytest

BASE = "/home/user/monitor_env"
MONITOR = "/app/uptime_monitor"
WRAPPER = f"{BASE}/fast_wrapper"
SOURCE = f"{BASE}/fast_wrapper.c"
REGRESSION = f"{BASE}/regression_test.sh"
SETTINGS = f"{BASE}/config/settings.bin"
LIBLINK = f"{BASE}/libs/libuptime_calc.so"
LIBV1 = f"{BASE}/libs/libuptime_calc.so.1"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_settings_bin_recovered():
    assert os.path.isfile(SETTINGS), f"Expected recovered file {SETTINGS} does not exist."
    assert os.path.getsize(SETTINGS) > 0, f"Expected {SETTINGS} to contain data."
    with open(SETTINGS, "rb") as f:
        recovered = f.read()
    assert recovered.strip() == b"UPTIME_SEED=42", "settings.bin does not contain the deleted configuration data."


def test_uptime_monitor_runs_and_is_repaired_original_kind():
    assert os.path.isfile(MONITOR) and not os.path.islink(MONITOR), "uptime_monitor must remain a regular binary."
    with open(MONITOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "uptime_monitor was replaced by a non-ELF program."

    dynamic = run(["readelf", "-d", MONITOR], timeout=3)
    assert dynamic.returncode == 0, dynamic.stderr
    assert "libuptime_calc.so" in dynamic.stdout, "uptime_monitor no longer has its required shared-library dependency."

    assert os.path.islink(LIBLINK), "The libuptime_calc.so linker symlink was not repaired."
    assert os.path.realpath(LIBLINK) == os.path.realpath(LIBV1), "libuptime_calc.so does not select the working library version."

    start = time.monotonic()
    result = run([MONITOR], timeout=2)
    elapsed = time.monotonic() - start
    assert result.returncode == 0, f"/app/uptime_monitor failed to run. Return code: {result.returncode}, stderr: {result.stderr}"
    assert len(result.stdout.strip()) > 0, "/app/uptime_monitor produced no output."
    assert result.stdout.strip() == "Uptime: 99999", "uptime_monitor did not produce the library's expected result."
    assert elapsed >= 0.07, "uptime_monitor was replaced by a deliberately simplified fast program."

    # Confirm that the binary still performs its required configuration check.
    saved_settings = SETTINGS + ".verifier-save"
    os.replace(SETTINGS, saved_settings)
    try:
        missing = run([MONITOR], timeout=2)
        assert missing.returncode != 0, "uptime_monitor succeeds even when its required settings file is absent."
        assert "settings.bin not found" in missing.stderr, "uptime_monitor no longer performs the expected settings check."
    finally:
        os.replace(saved_settings, SETTINGS)

    # Confirm output is actually obtained through the dynamically loaded library,
    # rather than from a replacement program printing a fixed expected string.
    original_target = os.readlink(LIBLINK)
    token = "VERIFIER_" + secrets.token_hex(12)
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "probe.c")
        probe = os.path.join(td, "libprobe.so")
        with open(src, "w") as f:
            f.write('#include <stdio.h>\nvoid calc_uptime(void) { puts("' + token + '"); }\n')
        built = run(["gcc", "-shared", "-fPIC", src, "-o", probe], timeout=10)
        assert built.returncode == 0, built.stderr
        os.unlink(LIBLINK)
        os.symlink(probe, LIBLINK)
        try:
            probed = run([MONITOR], timeout=2)
            assert probed.returncode == 0, probed.stderr
            assert probed.stdout.strip() == token, "uptime_monitor output is not supplied by libuptime_calc.so."
        finally:
            os.unlink(LIBLINK)
            os.symlink(original_target, LIBLINK)


def test_fast_wrapper_exists_and_executable():
    assert os.path.isfile(WRAPPER), f"Expected wrapper binary {WRAPPER} does not exist."
    assert os.access(WRAPPER, os.X_OK), f"Expected {WRAPPER} to be executable."
    assert os.path.isfile(SOURCE), f"Expected C source {SOURCE} does not exist."
    assert os.path.getsize(SOURCE) > 0, f"Expected {SOURCE} to contain C source."
    assert os.path.isfile(REGRESSION), f"Expected regression script {REGRESSION} does not exist."
    assert os.path.getsize(REGRESSION) > 0, f"Expected {REGRESSION} to contain a test script."


def test_fast_wrapper_correctness():
    orig_result = run([MONITOR], timeout=2)
    wrap_result = run([WRAPPER], timeout=2)
    assert wrap_result.returncode == 0, f"fast_wrapper failed to run. stderr: {wrap_result.stderr}"
    assert orig_result.stdout.strip() == wrap_result.stdout.strip(), "fast_wrapper output does not match original binary output."


def test_fast_wrapper_speedup():
    start = time.time()
    for _ in range(100):
        subprocess.run([MONITOR], stdout=subprocess.DEVNULL)
    base_time = time.time() - start

    start = time.time()
    for _ in range(100):
        subprocess.run([WRAPPER], stdout=subprocess.DEVNULL)
    wrapper_time = time.time() - start
    speedup = base_time / wrapper_time
    assert speedup >= 50.0, f"Speedup factor is {speedup:.2f}, which is less than the required 50.0. Base time: {base_time:.2f}s, Wrapper time: {wrapper_time:.2f}s."


def test_regression_script_runs():
    syntax = run(["bash", "-n", REGRESSION], timeout=5)
    assert syntax.returncode == 0, f"regression_test.sh has invalid bash syntax: {syntax.stderr}"
    result = run(["bash", REGRESSION], timeout=30)
    assert result.returncode == 0, f"regression_test.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}"


def test_submitted_c_source_really_executes_and_caches_for_five_seconds():
    # Compile the submitted source independently so the installed executable alone
    # cannot conceal a missing or unrelated C implementation.
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "rebuilt_wrapper")
        compilation = run(["gcc", "-O2", SOURCE, "-o", rebuilt], timeout=15)
        assert compilation.returncode == 0, f"fast_wrapper.c does not compile: {compilation.stderr}"

        controlled_src = os.path.join(td, "controlled.c")
        controlled_bin = os.path.join(td, "controlled_monitor")
        counter = os.path.join(td, "counter")
        token = "CACHE_" + secrets.token_hex(12)
        with open(controlled_src, "w") as f:
            f.write(r'''#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(void) {
    const char *p = getenv("VERIFIER_COUNTER");
    const char *t = getenv("VERIFIER_TOKEN");
    int n = 0;
    FILE *in = fopen(p, "r");
    if (in) { fscanf(in, "%d", &n); fclose(in); }
    n++;
    FILE *out = fopen(p, "w");
    if (!out) return 3;
    fprintf(out, "%d\n", n); fclose(out);
    usleep(100000);
    printf("%s-%d\n", t, n);
    return 0;
}
''')
        compilation = run(["gcc", controlled_src, "-o", controlled_bin], timeout=10)
        assert compilation.returncode == 0, compilation.stderr

        backup = os.path.join(td, "original_uptime_monitor")
        env = os.environ.copy()
        env["VERIFIER_COUNTER"] = counter
        env["VERIFIER_TOKEN"] = token

        # Expire any cache created by prior checks, then temporarily provide a
        # monitor whose changing, unpredictable answer exposes whether it ran.
        time.sleep(5.3)
        os.replace(MONITOR, backup)
        try:
            subprocess.run(["cp", controlled_bin, MONITOR], check=True)
            os.chmod(MONITOR, 0o755)

            start = time.monotonic()
            first = run([rebuilt], env=env, cwd=td, timeout=3)
            first_time = time.monotonic() - start
            start = time.monotonic()
            second = run([rebuilt], env=env, cwd=td, timeout=3)
            second_time = time.monotonic() - start

            assert first.returncode == 0 and second.returncode == 0, f"rebuilt wrapper failed: {first.stderr} {second.stderr}"
            assert first.stdout.strip() == f"{token}-1", "The wrapper did not execute /app/uptime_monitor on the first request."
            assert second.stdout.strip() == first.stdout.strip(), "Consecutive calls within five seconds did not return the cached value."
            with open(counter) as f:
                assert f.read().strip() == "1", "The wrapper executed uptime_monitor again instead of using its cache."
            assert second_time < first_time, "The cached call was not faster than the initial call."

            time.sleep(5.3)
            third = run([rebuilt], env=env, cwd=td, timeout=3)
            assert third.returncode == 0, third.stderr
            assert third.stdout.strip() == f"{token}-2", "The wrapper did not refresh its cache after five seconds."
            with open(counter) as f:
                assert f.read().strip() == "2", "Unexpected number of underlying monitor executions."
        finally:
            if os.path.lexists(MONITOR):
                os.unlink(MONITOR)
            os.replace(backup, MONITOR)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
