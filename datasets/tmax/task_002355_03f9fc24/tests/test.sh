#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/async_probe

cat << 'PROBE_EOF' > /tmp/async_probe/sitecustomize.py
import asyncio
import os

_trace_path = os.environ.get("ASYNC_QUEUE_TRACE")
_original_queue = asyncio.Queue


def _emit(message):
    if not _trace_path:
        return
    fd = os.open(_trace_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, (message + "\n").encode("utf-8"))
    finally:
        os.close(fd)


class TracingQueue(_original_queue):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        _emit(f"Q {id(self)}")

    async def put(self, item):
        _emit(f"P {id(self)}")
        return await super().put(item)

    def put_nowait(self, item):
        _emit(f"P {id(self)}")
        return super().put_nowait(item)

    async def get(self):
        task = asyncio.current_task()
        _emit(f"G {id(self)} {id(task)}")
        # Give concurrently started workers an opportunity to reach Queue.get().
        await asyncio.sleep(0.005)
        return await super().get()


asyncio.Queue = TracingQueue
asyncio.queues.Queue = TracingQueue
PROBE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import shutil
import subprocess

import pytest

SCRIPT_PATH = "/home/user/resolve.py"
DEPS_PATH = "/home/user/deps.txt"
LIB_DIR = "/home/user/mock_libs"
LOG_PATH = "/home/user/link_results.log"
TRACE_PATH = "/tmp/resolve_queue_trace.log"


def write_environment(entries, existing_libraries):
    shutil.rmtree(LIB_DIR, ignore_errors=True)
    os.makedirs(LIB_DIR, exist_ok=True)
    for library in existing_libraries:
        open(os.path.join(LIB_DIR, library), "wb").close()

    with open(DEPS_PATH, "w", encoding="utf-8") as deps:
        for target, expression in entries:
            encoded = base64.b64encode(expression.encode("utf-8")).decode("ascii")
            deps.write(f"{target}: {encoded}\n")


def run_resolver(trace=False):
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)

    env = os.environ.copy()
    if trace:
        env["PYTHONPATH"] = "/tmp/async_probe" + (
            os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
        )
        env["ASYNC_QUEUE_TRACE"] = TRACE_PATH

    completed = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"resolve.py exited with {completed.returncode}. "
        f"stdout={completed.stdout!r}, stderr={completed.stderr!r}"
    )


def test_resolve_py_exists_and_imports_asyncio():
    script_path = "/home/user/resolve.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    assert "import asyncio" in content or "from asyncio" in content, "The script does not seem to import asyncio."
    assert "asyncio.Queue" in content or "Queue" in content, "The script does not seem to use asyncio.Queue."


def test_link_results_log_content():
    baseline_entries = [
        ("AppCore", "libalpha.so AND libbeta.so"),
        ("AppUI", "libgamma.so OR libdelta.so"),
        ("AppNet", "libalpha.so AND libomega.so"),
        ("AppData", "libomega.so OR libsigma.so"),
        ("AppUtil", "libepsilon.so"),
    ]
    write_environment(
        baseline_entries,
        {"libalpha.so", "libbeta.so", "libdelta.so", "libepsilon.so"},
    )
    run_resolver()

    log_path = "/home/user/link_results.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    expected_lines = [
        "AppCore: SUCCESS",
        "AppData: FAILED",
        "AppNet: FAILED",
        "AppUI: SUCCESS",
        "AppUtil: SUCCESS"
    ]

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_lines, f"Content of {log_path} does not match expected output. Got: {lines}"


def test_dynamic_dependency_evaluation_and_worker_pool():
    nonce = secrets.token_hex(6)
    libraries = [f"lib_{nonce}_{index}.so" for index in range(8)]
    existing = {libraries[0], libraries[2], libraries[4], libraries[7]}

    cases = [
        (f"Target_{nonce}_Zulu", f"{libraries[0]} AND {libraries[2]}", True),
        (f"Target_{nonce}_Alpha", f"{libraries[0]} AND {libraries[1]}", False),
        (f"Target_{nonce}_Echo", f"{libraries[1]} OR {libraries[4]}", True),
        (f"Target_{nonce}_Bravo", f"{libraries[3]} OR {libraries[5]}", False),
        (f"Target_{nonce}_Hotel", libraries[7], True),
        (f"Target_{nonce}_Charlie", libraries[6], False),
        (f"Target_{nonce}_Golf", f"{libraries[0]} AND {libraries[2]} AND {libraries[4]}", True),
        (f"Target_{nonce}_Delta", f"{libraries[1]} OR {libraries[3]} OR {libraries[7]}", True),
        (f"Target_{nonce}_Foxtrot", f"{libraries[0]} AND {libraries[2]} AND {libraries[6]}", False),
    ]

    write_environment([(target, expression) for target, expression, _ in cases], existing)
    run_resolver(trace=True)

    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist after execution."
    with open(LOG_PATH, "r", encoding="utf-8") as result_file:
        actual_lines = result_file.read().splitlines()

    expected_lines = sorted(
        f"{target}: {'SUCCESS' if result else 'FAILED'}"
        for target, _, result in cases
    )
    assert actual_lines == expected_lines, (
        "resolve.py did not decode and evaluate the generated dependency map correctly "
        "or did not sort/format its output strictly. "
        f"Got: {actual_lines}"
    )

    assert os.path.isfile(TRACE_PATH), "No asyncio.Queue activity was observed."
    queue_stats = {}
    with open(TRACE_PATH, "r", encoding="utf-8") as trace_file:
        for line in trace_file:
            parts = line.split()
            if len(parts) < 2 or parts[0] not in {"Q", "P", "G"}:
                continue
            stats = queue_stats.setdefault(parts[1], {"created": False, "puts": 0, "gets": 0, "tasks": set()})
            if parts[0] == "Q":
                stats["created"] = True
            elif parts[0] == "P":
                stats["puts"] += 1
            elif parts[0] == "G" and len(parts) == 3:
                stats["gets"] += 1
                stats["tasks"].add(parts[2])

    qualifying = [
        stats for stats in queue_stats.values()
        if stats["created"]
        and stats["puts"] >= len(cases)
        and stats["gets"] >= len(cases)
        and len(stats["tasks"]) >= 3
    ]
    assert qualifying, (
        "The generated work was not processed through one asyncio.Queue by at least "
        "three async worker tasks. Observed queue activity: " + repr(queue_stats)
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
