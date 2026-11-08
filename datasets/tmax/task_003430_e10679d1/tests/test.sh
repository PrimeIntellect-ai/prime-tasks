#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import importlib.util
import inspect
import math
import os
import secrets
import subprocess
import sys

FIXED_PATH = "/home/user/app/server_fixed.py"
REGRESSION_TEST_PATH = "/home/user/app/test_regression.py"


def load_fixed_module():
    spec = importlib.util.spec_from_file_location(
        "server_fixed_" + secrets.token_hex(8), FIXED_PATH
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_server_fixed_exists():
    assert os.path.exists(FIXED_PATH), f"{FIXED_PATH} does not exist."
    assert os.path.isfile(FIXED_PATH), f"{FIXED_PATH} is not a file."


def test_regression_script_exists():
    assert os.path.exists(REGRESSION_TEST_PATH), f"{REGRESSION_TEST_PATH} does not exist."
    assert os.path.isfile(REGRESSION_TEST_PATH), f"{REGRESSION_TEST_PATH} is not a file."


def test_required_classes_and_signatures():
    mod = load_fixed_module()
    assert hasattr(mod, "UptimeMonitor")
    assert hasattr(mod, "MetricsServer")
    assert list(inspect.signature(mod.UptimeMonitor.add_uptime_delta).parameters) == ["self", "delta"]
    assert list(inspect.signature(mod.MetricsServer.handle_process_request).parameters) == ["self"]
    assert inspect.iscoroutinefunction(mod.MetricsServer.handle_process_request)


def test_precision_fix():
    assert os.path.exists(FIXED_PATH), "server_fixed.py is missing"
    mod = load_fixed_module()
    monitor = mod.UptimeMonitor()

    # Preserve the required ten-million-addition regression assertion.
    for _ in range(10000000):
        monitor.add_uptime_delta(1e-9)

    assert monitor.total_uptime > 100000000.0, \
        "Precision loss issue is not fixed: value did not increment."
    actual = float(monitor.total_uptime)
    expected = 100000000.0 + 10000000 * 1e-9
    assert math.isfinite(actual)
    assert math.isclose(actual, expected, rel_tol=0.0, abs_tol=3e-8), \
        f"Incorrect accumulated uptime: got {actual!r}, expected {expected!r}"

    # Exercise independently derived, varying totals so assigning a fixed large
    # value cannot satisfy the precision check.
    for _ in range(3):
        count = 100000 + secrets.randbelow(400001)
        delta = (1 + secrets.randbelow(9)) * 1e-9
        candidate = mod.UptimeMonitor()
        for _ in range(count):
            candidate.add_uptime_delta(delta)
        actual = float(candidate.total_uptime)
        expected = 100000000.0 + count * delta
        assert math.isfinite(actual)
        assert math.isclose(actual, expected, rel_tol=0.0, abs_tol=3e-8), \
            f"Uptime accumulation is not delta-preserving: got {actual!r}, expected {expected!r}"


async def _exercise_asyncio_fix():
    mod = load_fixed_module()

    # Verify the normal handler actually spawns and awaits its worker.
    server = mod.MetricsServer()
    started = asyncio.Event()
    release = asyncio.Event()
    finished = asyncio.Event()

    async def controlled_worker():
        started.set()
        try:
            await release.wait()
        finally:
            finished.set()

    server._background_worker = controlled_worker
    normal_task = asyncio.create_task(server.handle_process_request())
    await asyncio.wait_for(started.wait(), timeout=1.0)
    await asyncio.sleep(0)
    assert not normal_task.done(), "handle_process_request returned without awaiting its worker"
    release.set()
    await asyncio.wait_for(normal_task, timeout=1.0)
    assert finished.is_set(), "The background worker was not processed to completion"

    # Verify cancellation reaches the spawned worker and leaves no orphan task.
    server = mod.MetricsServer()
    worker_started = asyncio.Event()
    worker_cancelled = asyncio.Event()
    worker_finished = asyncio.Event()

    async def cancellable_worker():
        worker_started.set()
        try:
            await asyncio.Event().wait()
        except asyncio.CancelledError:
            worker_cancelled.set()
            raise
        finally:
            worker_finished.set()

    server._background_worker = cancellable_worker
    baseline_tasks = set(asyncio.all_tasks())
    initial_tasks = len(baseline_tasks)

    handler_task = asyncio.create_task(server.handle_process_request())
    await asyncio.wait_for(worker_started.wait(), timeout=1.0)
    assert not handler_task.done(), "handle_process_request returned before processing its worker"
    handler_task.cancel()

    try:
        await asyncio.wait_for(handler_task, timeout=1.0)
    except asyncio.CancelledError:
        pass

    await asyncio.sleep(0.05)
    assert worker_cancelled.is_set(), "Cancellation was not propagated to the background worker"
    assert worker_finished.is_set(), "The cancelled background worker was not awaited to completion"

    final_set = set(asyncio.all_tasks())
    final_tasks = len(final_set)
    assert final_tasks <= initial_tasks, \
        f"Asyncio task leak issue is not fixed: {final_tasks} tasks running, expected <= {initial_tasks}."
    assert not (final_set - baseline_tasks), \
        f"Orphaned asyncio tasks remain: {final_set - baseline_tasks!r}"


def test_asyncio_leak_fix():
    assert os.path.exists(FIXED_PATH), "server_fixed.py is missing"
    asyncio.run(_exercise_asyncio_fix())


def run_regression_script():
    return subprocess.run(
        [sys.executable, REGRESSION_TEST_PATH],
        capture_output=True,
        timeout=40,
        cwd=os.path.dirname(REGRESSION_TEST_PATH),
    )


def test_regression_script_execution():
    assert os.path.exists(REGRESSION_TEST_PATH), "test_regression.py is missing"
    result = run_regression_script()
    assert result.returncode == 0, \
        f"Regression test script failed or exited non-zero.\nStdout: {result.stdout.decode()}\nStderr: {result.stderr.decode()}"


def test_regression_script_detects_both_regressions():
    original = open(FIXED_PATH, "rb").read()

    precision_broken = b'''\
import asyncio

class UptimeMonitor:
    def __init__(self):
        self.total_uptime = 100000000.0
    def add_uptime_delta(self, delta: float):
        self.total_uptime += delta

class MetricsServer:
    def __init__(self):
        self.monitor = UptimeMonitor()
    async def _background_worker(self):
        await asyncio.sleep(10)
    async def handle_process_request(self):
        worker_task = asyncio.create_task(self._background_worker())
        try:
            await asyncio.sleep(1)
            await worker_task
        finally:
            if not worker_task.done():
                worker_task.cancel()
            try:
                await worker_task
            except asyncio.CancelledError:
                pass
'''

    asyncio_broken = b'''\
import asyncio
import math

class UptimeMonitor:
    def __init__(self):
        self.total_uptime = 100000000.0
        self._added = 0.0
    def add_uptime_delta(self, delta: float):
        self._added = math.fsum((self._added, delta))
        self.total_uptime = math.fsum((100000000.0, self._added))

class MetricsServer:
    def __init__(self):
        self.monitor = UptimeMonitor()
    async def _background_worker(self):
        try:
            await asyncio.sleep(10)
        except asyncio.CancelledError:
            pass
    async def handle_process_request(self):
        worker_task = asyncio.create_task(self._background_worker())
        await asyncio.sleep(1)
        await worker_task
'''

    try:
        with open(FIXED_PATH, "wb") as f:
            f.write(precision_broken)
        result = run_regression_script()
        assert result.returncode != 0, \
            "test_regression.py does not detect the required precision-loss regression"

        with open(FIXED_PATH, "wb") as f:
            f.write(asyncio_broken)
        result = run_regression_script()
        assert result.returncode != 0, \
            "test_regression.py does not detect the required asyncio task-leak regression"
    finally:
        with open(FIXED_PATH, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
