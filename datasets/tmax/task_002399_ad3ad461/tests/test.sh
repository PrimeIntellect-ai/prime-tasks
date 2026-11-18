#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import inspect
import importlib.util
import json
import os
import secrets
import subprocess
import sys
import textwrap
import pytest

APP_DIR = "/home/user/app"
EVENT_PROCESSOR_FILE = "/home/user/app/event_processor.py"
BUGGY_FILE = "/home/user/app/event_processor_buggy.py"
FUZZ_TEST_FILE = "/home/user/fuzz_test.py"
MRE_FILE = "/home/user/mre.py"
REPORT_FILE = "/home/user/incident_report.txt"


def load_submission():
    spec = importlib.util.spec_from_file_location("submitted_event_processor", EVENT_PROCESSOR_FILE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_event_processor_fixed():
    assert os.path.isfile(EVENT_PROCESSOR_FILE), f"File {EVENT_PROCESSOR_FILE} is missing."

    # Preserve the original fixed-case assertion.
    sys.path.insert(0, APP_DIR)
    try:
        sys.modules.pop("event_processor", None)
        from event_processor import run_batch
    except ImportError as e:
        pytest.fail(f"Failed to import run_batch from event_processor: {e}")
    finally:
        sys.path.pop(0)

    num_events = 1000
    events = [json.dumps({"user": "test", "amount": 1}) for _ in range(num_events)]
    stats = run_batch(events)
    assert stats.get("test") == num_events, (
        f"Race condition still exists: expected {num_events}, got {stats.get('test')}"
    )

    assert os.path.isfile(BUGGY_FILE), "The supplied buggy version is missing."
    with open(EVENT_PROCESSOR_FILE, "rb") as fixed, open(BUGGY_FILE, "rb") as buggy:
        assert fixed.read() != buggy.read(), "event_processor.py was not changed from the buggy version."

    module = load_submission()
    assert hasattr(module, "Aggregator") and hasattr(module, "run_batch")
    assert list(inspect.signature(module.Aggregator.process_event).parameters) == ["self", "event_json"]
    assert list(inspect.signature(module.Aggregator.get_stats).parameters) == ["self"]
    assert list(inspect.signature(module.run_batch).parameters) == ["events", "max_workers"]

    # Exercise unpredictable, independently-derived batches so a fixed answer cannot pass.
    rng = secrets.SystemRandom()
    for trial in range(6):
        expected = {}
        events = []
        users = [f"u_{secrets.token_hex(6)}_{i}" for i in range(rng.randint(4, 14))]
        for _ in range(rng.randint(350, 800)):
            user = rng.choice(users)
            amount = rng.randint(-25, 250)
            events.append(json.dumps({"user": user, "amount": amount}))
            expected[user] = expected.get(user, 0) + amount
        # These are part of the existing behavior and must not affect totals.
        events.extend(["not-json", json.dumps({"amount": 999}), "{"])
        rng.shuffle(events)
        actual = module.run_batch(events, max_workers=rng.randint(8, 32))
        assert actual == expected, f"Incorrect concurrent aggregation on randomized trial {trial}"


def run_fuzz(env_extra):
    env = os.environ.copy()
    env.update(env_extra)
    env["PYTHONPATH"] = "/home/user/app:/home/user:" + env.get("PYTHONPATH", "")
    return subprocess.run(
        [sys.executable, FUZZ_TEST_FILE], cwd="/home/user", env=env,
        capture_output=True, text=True, timeout=45
    )


def test_fuzz_test_script():
    assert os.path.isfile(FUZZ_TEST_FILE), f"File {FUZZ_TEST_FILE} is missing."

    # Preserve the original execution assertion against the submitted implementation.
    result = subprocess.run(
        [sys.executable, FUZZ_TEST_FILE], cwd="/home/user",
        capture_output=True, text=True, timeout=45
    )
    assert result.returncode == 0, f"fuzz_test.py failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    # Replace run_batch briefly with a probe. This verifies that the script really
    # generates a large varied batch, calls run_batch, and detects a wrong answer.
    with open(EVENT_PROCESSOR_FILE, "rb") as f:
        original = f.read()
    probe = textwrap.dedent(r'''
        import json
        import os

        def run_batch(events, max_workers=20):
            events = list(events)
            totals = {}
            pairs = set()
            valid = 0
            for raw in events:
                try:
                    event = json.loads(raw)
                except (json.JSONDecodeError, TypeError):
                    continue
                if not isinstance(event, dict) or event.get("user") is None:
                    continue
                user = event.get("user")
                amount = event.get("amount", 0)
                totals[user] = totals.get(user, 0) + amount
                pairs.add((repr(user), repr(amount)))
                valid += 1
            with open(os.environ["FUZZ_PROBE_LOG"], "a", encoding="utf-8") as log:
                log.write(json.dumps({"count": len(events), "valid": valid,
                                      "variety": len(pairs)}) + "\n")
            if os.environ.get("FUZZ_PROBE_CORRUPT") == "1":
                if totals:
                    key = next(iter(totals))
                    totals[key] += 1000003
                else:
                    totals["__probe_wrong__"] = 1000003
            return totals

        class Aggregator:
            pass
    ''').encode()
    log_path = f"/tmp/fuzz_probe_{secrets.token_hex(8)}.jsonl"
    try:
        with open(EVENT_PROCESSOR_FILE, "wb") as f:
            f.write(probe)
        good = run_fuzz({"FUZZ_PROBE_LOG": log_path, "FUZZ_PROBE_CORRUPT": "0"})
        assert good.returncode == 0, (
            "fuzz_test.py did not accept correct independently-computed results.\n"
            f"Stdout: {good.stdout}\nStderr: {good.stderr}"
        )
        assert os.path.isfile(log_path), "fuzz_test.py did not call run_batch."
        with open(log_path, encoding="utf-8") as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert calls, "fuzz_test.py did not call run_batch."
        assert sum(c["count"] for c in calls) >= 500, "fuzz_test.py did not generate a large batch."
        assert max(c["variety"] for c in calls) >= 3, "fuzz_test.py did not generate varied randomized events."

        bad_log = log_path + ".bad"
        bad = run_fuzz({"FUZZ_PROBE_LOG": bad_log, "FUZZ_PROBE_CORRUPT": "1"})
        assert bad.returncode == 1, (
            "fuzz_test.py did not exit with code 1 when run_batch returned an incorrect total.\n"
            f"Stdout: {bad.stdout}\nStderr: {bad.stderr}"
        )
    finally:
        with open(EVENT_PROCESSOR_FILE, "wb") as f:
            f.write(original)
        for path in (log_path, log_path + ".bad"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_mre_script():
    assert os.path.isfile(MRE_FILE), f"File {MRE_FILE} is missing."
    with open(MRE_FILE, "r", encoding="utf-8") as f:
        source = f.read()
    lines = source.splitlines(keepends=True)
    assert len(lines) < 35, f"mre.py has {len(lines)} lines, which is 35 or more."

    tree = ast.parse(source, filename=MRE_FILE)
    imports_buggy_aggregator = any(
        isinstance(node, ast.ImportFrom)
        and node.module is not None
        and node.module.endswith("event_processor_buggy")
        and any(alias.name == "Aggregator" for alias in node.names)
        for node in ast.walk(tree)
    )
    assert imports_buggy_aggregator, "mre.py must import Aggregator from event_processor_buggy."
    assert "ThreadPoolExecutor" not in source, "MRE must use simpler raw threading, not a thread pool."
    assert not any(
        isinstance(node, (ast.Import, ast.ImportFrom))
        and ((isinstance(node, ast.ImportFrom) and node.module == "json") or
             (isinstance(node, ast.Import) and any(a.name == "json" for a in node.names)))
        for node in ast.walk(tree)
    ), "MRE must not depend on JSON parsing."

    attrs = {node.attr for node in ast.walk(tree) if isinstance(node, ast.Attribute)}
    names = {node.id for node in ast.walk(tree) if isinstance(node, ast.Name)}
    assert "Aggregator" in names, "mre.py does not instantiate or use Aggregator."
    assert "stats" in attrs, "mre.py does not demonstrate the Aggregator's lost update."
    assert "Thread" in attrs or "Thread" in names, "mre.py must use raw threading."
    assert "start" in attrs and "join" in attrs, "mre.py must run and join its threads."
    assert any(isinstance(node, (ast.Compare, ast.Assert)) for node in ast.walk(tree)), (
        "mre.py must compare the observed result to the expected result."
    )

    # A consistent MRE should complete successfully on repeated executions.
    for attempt in range(3):
        result = subprocess.run(
            [sys.executable, MRE_FILE], cwd="/home/user",
            capture_output=True, text=True, timeout=20
        )
        assert result.returncode == 0, (
            f"mre.py failed to demonstrate the race consistently on attempt {attempt + 1}.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )


def test_incident_report():
    assert os.path.isfile(REPORT_FILE), f"File {REPORT_FILE} is missing."
    with open(REPORT_FILE, "r", encoding="utf-8") as f:
        raw = f.read()
        content = raw.strip().lower()

    # Preserve the original assertion.
    assert "lock" in content or "rlock" in content, (
        f"Incident report does not contain the correct concurrency primitive name. Content: {content}"
    )
    assert len(raw.splitlines()) == 1, "Incident report must contain exactly one line."
    assert raw.strip() in {"Lock", "RLock"}, (
        "Incident report must contain exactly the primitive name Lock or RLock."
    )
    with open(EVENT_PROCESSOR_FILE, "r", encoding="utf-8") as f:
        processor_source = f.read()
    assert raw.strip() in processor_source, "The reported primitive is not used in event_processor.py."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
