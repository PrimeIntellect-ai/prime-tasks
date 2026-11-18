#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import io
import json
import os
import pathlib
import random
import shutil
import string
import subprocess
import sys
import tempfile
import types
import unittest

APP = "/home/user/app"
MONITOR = os.path.join(APP, "monitor.py")
LIBRARY = os.path.join(APP, "libuptime.so")
REGRESSION = os.path.join(APP, "test_monitor.py")
LONG_HOST = "super_long_hostname_that_would_normally_crash_the_service.internal.com"


def test_limit_file_content():
    """Verify that limit.txt contains the correct maximum safe string length."""
    path = os.path.join(APP, "limit.txt")
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "15", f"Expected {path} to contain '15', but found '{content}'."


def test_regression_test_passes():
    """Verify that the regression test file exists and passes."""
    assert os.path.isfile(REGRESSION), f"Regression test file {REGRESSION} does not exist."

    cmd = [sys.executable, "-m", "unittest", REGRESSION]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=APP)
    assert result.returncode == 0, (
        "Regression test failed or crashed.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def _run_regression_against_fake(status):
    calls = []
    fake_monitor = types.ModuleType("monitor")

    def monitor_host(hostname):
        calls.append(hostname)
        return status

    fake_monitor.monitor_host = monitor_host
    old_monitor = sys.modules.get("monitor")
    module_name = f"submitted_regression_{status}_{random.randrange(1 << 30)}"
    try:
        sys.modules["monitor"] = fake_monitor
        spec = importlib.util.spec_from_file_location(module_name, REGRESSION)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        calls.clear()
        suite = unittest.defaultTestLoader.loadTestsFromModule(module)
        count = suite.countTestCases()
        stream = io.StringIO()
        result = unittest.TextTestRunner(stream=stream, verbosity=0).run(suite)
        return count, result.wasSuccessful(), calls, stream.getvalue()
    finally:
        sys.modules.pop(module_name, None)
        if old_monitor is None:
            sys.modules.pop("monitor", None)
        else:
            sys.modules["monitor"] = old_monitor


def test_regression_test_is_meaningful():
    """Require a unittest that calls the specified hostname and checks for status 200."""
    count, passed, calls, output = _run_regression_against_fake(200)
    assert count > 0, "test_monitor.py contains no unittest-discoverable test cases"
    assert passed, f"Regression test did not accept status 200:\n{output}"
    assert LONG_HOST in calls, "Regression test did not call monitor_host with the required hostname"

    count, passed, calls, output = _run_regression_against_fake(418)
    assert LONG_HOST in calls, "Regression test did not exercise the required hostname"
    assert not passed, "Regression test does not verify that monitor_host returns 200"


def test_monitor_no_segfault():
    """Verify that monitor_host safely handles a long string without crashing."""
    code = (
        "import sys\n"
        "sys.path.insert(0, '/home/user/app')\n"
        "import monitor\n"
        "result = monitor.monitor_host('A' * 100)\n"
        "print(result)\n"
    )
    cmd = [sys.executable, "-c", code]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=APP)

    assert result.returncode == 0, (
        "Calling monitor_host with a long string crashed (likely a segmentation fault).\n"
        f"STDERR:\n{result.stderr}"
    )
    assert "200" in result.stdout.strip(), (
        f"Expected monitor_host to return 200, got: {result.stdout.strip()}"
    )


def _fnv_status(value, salt):
    h = (2166136261 ^ salt) & 0xffffffff
    for byte in value.encode("ascii"):
        h ^= byte
        h = (h * 16777619) & 0xffffffff
    return 1000 + (h % 1000000)


def test_monitor_truncates_and_calls_library():
    """Instrument the library call and verify exact truncation and return propagation."""
    assert os.path.isfile(MONITOR), f"File {MONITOR} does not exist."
    assert os.path.isfile(LIBRARY), f"File {LIBRARY} does not exist."

    work = tempfile.mkdtemp(prefix="monitor-verifier-")
    backup = os.path.join(work, "libuptime.original.so")
    probe = os.path.join(work, "libuptime.probe.so")
    log_path = os.path.join(work, "calls.log")
    source = os.path.join(work, "probe.c")
    salt = random.SystemRandom().randrange(1, 2**32)

    c_source = r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define SALT %dU
#define LOG_PATH %s

int check_uptime(const char *hostname) {
    const unsigned char *p = (const unsigned char *)hostname;
    uint32_t h = 2166136261U ^ SALT;
    FILE *f = fopen(LOG_PATH, "a");
    if (f != NULL) {
        while (*p) {
            fprintf(f, "%%02x", (unsigned int)*p);
            p++;
        }
        fputc('\n', f);
        fclose(f);
    }
    p = (const unsigned char *)hostname;
    while (*p) {
        h ^= *p++;
        h *= 16777619U;
    }
    return 1000 + (int)(h %% 1000000U);
}
''' % (salt, json.dumps(log_path))

    pathlib.Path(source).write_text(c_source)
    compiled = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", probe, source],
        capture_output=True,
        text=True,
    )
    assert compiled.returncode == 0, f"Could not build probe library: {compiled.stderr}"

    alphabet = string.ascii_letters + string.digits
    rng = random.SystemRandom()
    lengths = [0, 1, 7, 14, 15, 16, 31, 100]
    hostnames = ["".join(rng.choice(alphabet) for _ in range(n)) for n in lengths]

    shutil.copy2(LIBRARY, backup)
    try:
        shutil.copy2(probe, LIBRARY)
        payload = json.dumps(hostnames)
        code = (
            "import json, sys\n"
            "sys.path.insert(0, '/home/user/app')\n"
            "import monitor\n"
            f"hosts = json.loads({payload!r})\n"
            "results = [monitor.monitor_host(host) for host in hosts]\n"
            "print('VERIFIER_RESULTS=' + json.dumps(results))\n"
        )
        result = subprocess.run(
            [sys.executable, "-c", code], capture_output=True, text=True, cwd=APP
        )
        assert result.returncode == 0, (
            "Instrumented monitor_host calls failed or crashed.\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )

        result_lines = [
            line for line in result.stdout.splitlines()
            if line.startswith("VERIFIER_RESULTS=")
        ]
        assert result_lines, f"monitor test produced no result list: {result.stdout!r}"
        returned = json.loads(result_lines[-1].split("=", 1)[1])

        assert os.path.isfile(log_path), "monitor_host did not call libuptime.so"
        with open(log_path, "r") as f:
            observed = [bytes.fromhex(line.strip()).decode("ascii") for line in f if line.strip()]

        expected_arguments = [hostname[:15] for hostname in hostnames]
        expected_results = [_fnv_status(value, salt) for value in expected_arguments]
        assert observed == expected_arguments, (
            "monitor_host did not pass each hostname unchanged up to 15 characters "
            "and truncate longer hostnames exactly to 15 characters. "
            f"Expected {expected_arguments!r}, observed {observed!r}"
        )
        assert returned == expected_results, (
            "monitor_host did not return the integer statuses produced by libuptime.so. "
            f"Expected {expected_results!r}, got {returned!r}"
        )
    finally:
        if os.path.exists(backup):
            os.replace(backup, LIBRARY)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
