#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/voice_trace
cat << 'TRACE_EOF' > /tmp/voice_trace/sitecustomize.py
import atexit
import inspect
import json
import os
import threading

_REAL_LOCK = threading.Lock
_REAL_THREAD = threading.Thread
_TRACE_GUARD = _REAL_LOCK()
_AGENT_PATH = os.path.realpath(os.environ.get("VOICE_AGENT_PATH", ""))
_EVENTS = []
_LOCKS = {}


def _from_agent():
    for frame in inspect.stack()[2:]:
        if os.path.realpath(frame.filename) == _AGENT_PATH:
            return True
    return False


def _record(event):
    with _TRACE_GUARD:
        _EVENTS.append(event)


class _TracedLock:
    def __init__(self, user_created):
        self._lock = _REAL_LOCK()
        self._user_created = user_created
        self._id = id(self)
        if user_created:
            with _TRACE_GUARD:
                _LOCKS[str(self._id)] = {"acquires": 0, "releases": 0, "held": 0}

    def acquire(self, *args, **kwargs):
        result = self._lock.acquire(*args, **kwargs)
        if result and self._user_created:
            ident = threading.get_ident()
            with _TRACE_GUARD:
                state = _LOCKS[str(self._id)]
                state["acquires"] += 1
                state["held"] += 1
                _EVENTS.append({"kind": "acquire", "lock": self._id, "thread": ident})
        return result

    def release(self):
        if self._user_created:
            ident = threading.get_ident()
            with _TRACE_GUARD:
                state = _LOCKS[str(self._id)]
                state["releases"] += 1
                state["held"] -= 1
                _EVENTS.append({"kind": "release", "lock": self._id, "thread": ident})
        return self._lock.release()

    def locked(self):
        return self._lock.locked()

    def __enter__(self):
        self.acquire()
        return self

    def __exit__(self, exc_type, exc, tb):
        self.release()
        return False


def _lock_factory(*args, **kwargs):
    return _TracedLock(_from_agent())


class _TracedThread(_REAL_THREAD):
    def __init__(self, *args, **kwargs):
        self._voice_user_created = _from_agent()
        super().__init__(*args, **kwargs)
        if self._voice_user_created:
            _record({"kind": "thread_created", "object": id(self)})

    def start(self):
        if self._voice_user_created:
            _record({"kind": "thread_started", "object": id(self)})
        return super().start()

    def join(self, *args, **kwargs):
        result = super().join(*args, **kwargs)
        if self._voice_user_created:
            _record({"kind": "thread_joined", "object": id(self)})
        return result


threading.Lock = _lock_factory
threading.Thread = _TracedThread


@atexit.register
def _write_trace():
    path = os.environ.get("VOICE_TRACE_PATH")
    if path:
        with open(path, "w") as f:
            json.dump({"events": _EVENTS, "locks": _LOCKS}, f)
TRACE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import filecmp
import json
import os
import random
import re
import subprocess
import tempfile
import pytest

TIMELINE = (
    "Thread 1 acquires lock A. Thread 2 acquires lock B. "
    "Thread 1 attempts to acquire lock B and blocks. "
    "Thread 2 attempts to acquire lock A and blocks. "
    "Deadlock occurs during tmp file writing assertion failure."
)
AGENT_SCRIPT = "/home/user/fixed_voice_processor.py"
ORACLE_PATH = "/app/oracle_voice_processor"


def normalize_words(value):
    return re.findall(r"[a-z0-9]+", value.lower())


def configured_agent_command():
    return [
        "runuser", "-u", "user", "--", "env", "-u", "PROCESSOR_TMP_DIR",
        "HOME=/home/user", "bash", "--noprofile", "-ic",
        'exec python3 "$1"', "bash", AGENT_SCRIPT,
    ]


def test_reconstructed_timeline_exists():
    path = "/home/user/reconstructed_timeline.txt"
    assert os.path.isfile(path), f"Reconstructed timeline is missing at {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert len(content) > 0, "Reconstructed timeline is empty"
    assert normalize_words(content) == normalize_words(TIMELINE), (
        "The reconstructed timeline does not match the dictated sequence"
    )


def test_fixed_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Fixed script is missing at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert not filecmp.cmp(AGENT_SCRIPT, ORACLE_PATH, shallow=False), (
        "The submitted script must not be a byte-identical copy of the reference"
    )


def test_environment_is_persistently_configured_and_writable():
    proc = subprocess.run(
        [
            "runuser", "-u", "user", "--", "env", "-u", "PROCESSOR_TMP_DIR",
            "HOME=/home/user", "bash", "--noprofile", "-ic",
            'printf "__PROCESSOR_VALUE__%s" "$PROCESSOR_TMP_DIR"',
        ],
        text=True, capture_output=True, timeout=5,
    )
    assert proc.returncode == 0, proc.stderr
    marker = "__PROCESSOR_VALUE__"
    assert marker in proc.stdout, "Could not read the configured user environment"
    value = proc.stdout.rsplit(marker, 1)[1]
    assert value == "/tmp/voice_processing", (
        f"PROCESSOR_TMP_DIR is not persistently configured correctly: {value!r}"
    )
    assert os.path.isdir(value), f"Configured temporary directory does not exist: {value}"

    probe = os.path.join(value, ".verifier_write_probe")
    try:
        write_proc = subprocess.run(
            ["runuser", "-u", "user", "--", "sh", "-c", 'printf test > "$1"', "sh", probe],
            text=True, capture_output=True, timeout=5,
        )
        assert write_proc.returncode == 0, (
            f"Configured temporary directory is not writable by user: {write_proc.stderr}"
        )
    finally:
        try:
            os.unlink(probe)
        except FileNotFoundError:
            pass


def test_repaired_multithreaded_logic_executes():
    with open(AGENT_SCRIPT, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=AGENT_SCRIPT)

    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call)]
    attrs = [n.func.attr for n in calls if isinstance(n.func, ast.Attribute)]
    names = [n.func.id for n in calls if isinstance(n.func, ast.Name)]
    assert attrs.count("start") >= 2, "The repaired daemon must start its worker threads"
    assert attrs.count("join") >= 2, "The repaired daemon must join its worker threads"
    assert ("acquire" in attrs and "release" in attrs) or any(
        isinstance(n, (ast.With, ast.AsyncWith)) for n in ast.walk(tree)
    ), "The fixed script must retain repaired synchronization logic"
    assert attrs.count("Lock") + names.count("Lock") >= 2, (
        "The fixed script must repair, rather than discard, the two-lock logic"
    )
    assert attrs.count("Thread") + names.count("Thread") >= 2, (
        "The fixed script must retain the multithreaded daemon logic"
    )

    trace_path = "/tmp/voice_processor_trace.json"
    try:
        os.unlink(trace_path)
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/voice_trace" + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    env["VOICE_TRACE_PATH"] = trace_path
    env["VOICE_AGENT_PATH"] = AGENT_SCRIPT

    proc = subprocess.run(
        configured_agent_command(), input="1 2 3 4", text=True,
        capture_output=True, timeout=5, env=env,
    )
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout.strip() == "2 4 6 8"
    assert os.path.isfile(trace_path), "The instrumented script did not produce a trace"

    with open(trace_path, "r") as f:
        trace = json.load(f)
    events = trace["events"]
    locks = trace["locks"]
    created = {e["object"] for e in events if e["kind"] == "thread_created"}
    started = {e["object"] for e in events if e["kind"] == "thread_started"}
    joined = {e["object"] for e in events if e["kind"] == "thread_joined"}
    worker_ids = {e["thread"] for e in events if e["kind"] == "acquire"}

    assert len(created) >= 2 and len(started) >= 2 and len(joined) >= 2, (
        "At least two agent-created worker threads must actually start and be joined"
    )
    assert len(locks) >= 2, "At least two agent-created locks must execute"
    assert len(worker_ids) >= 2, "Both worker threads must execute synchronized work"
    for state in locks.values():
        assert state["acquires"] > 0, "Each repaired lock must actually be acquired"
        assert state["acquires"] == state["releases"], "A lock was not released"
        assert state["held"] == 0, "A lock remained held after processing"


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

    random.seed(42)
    N = 100
    for i in range(N):
        num_ints = random.randint(1, 1000)
        input_data = " ".join(str(random.randint(0, 10000)) for _ in range(num_ints))

        try:
            oracle_proc = subprocess.run(
                [ORACLE_PATH], input=input_data, text=True,
                capture_output=True, timeout=5, check=True,
            )
            oracle_out = oracle_proc.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail("Oracle timed out")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed with error: {e.stderr}")

        try:
            agent_proc = subprocess.run(
                configured_agent_command(), input=input_data, text=True,
                capture_output=True, timeout=5,
            )
            agent_out = agent_proc.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input: {input_data[:50]}...")

        if agent_proc.returncode != 0:
            pytest.fail(
                f"Agent script failed with return code {agent_proc.returncode}. "
                f"Stderr: {agent_proc.stderr}"
            )

        assert agent_out == oracle_out, (
            f"Output mismatch on run {i+1}.\n"
            f"Input (first 50 chars): {input_data[:50]}...\n"
            f"Expected (Oracle): {oracle_out[:100]}...\n"
            f"Got (Agent): {agent_out[:100]}..."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
