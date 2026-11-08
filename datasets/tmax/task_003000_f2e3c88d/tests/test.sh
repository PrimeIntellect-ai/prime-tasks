#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import secrets
import subprocess
import sys


def load_monitor():
    monitor_script = '/home/user/sre_app/monitor.py'
    assert os.path.isfile(monitor_script), f"{monitor_script} does not exist."
    spec = importlib.util.spec_from_file_location('submitted_monitor', monitor_script)
    assert spec is not None and spec.loader is not None, "Could not load monitor.py."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, 'check_gaps', None)), "monitor.py does not define callable check_gaps."
    return module


def test_fixed_output():
    output_file = '/home/user/fixed_output.txt'
    assert os.path.isfile(output_file), f"{output_file} does not exist."
    with open(output_file, 'r') as f:
        content = f.read().strip()
    assert "Total alerts: 1" in content, f"Expected 'Total alerts: 1' in {output_file}, but got: {content}"


def test_timeline_json():
    timeline_file = '/home/user/timeline.json'
    assert os.path.isfile(timeline_file), f"{timeline_file} does not exist."

    with open(timeline_file, 'r') as f:
        try:
            timeline = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{timeline_file} is not valid JSON."

    expected_timeline = [
        {"timestamp": 1700000000, "service": "app", "message": "Service started"},
        {"timestamp": 1700000005, "service": "monitor", "message": "Monitor started"},
        {"timestamp": 1700000010, "service": "app", "message": "Ping OK"},
        {"timestamp": 1700000015, "service": "monitor", "message": "Processed early pings"},
        {"timestamp": 1700000020, "service": "app", "message": "Ping OK"},
        {"timestamp": 1700000090, "service": "app", "message": "Ping OK"},
        {"timestamp": 1700000100, "service": "app", "message": "Ping OK"},
        {"timestamp": 1700000105, "service": "monitor", "message": "Crash imminent"}
    ]

    assert isinstance(timeline, list), "Timeline must be a JSON array."
    assert len(timeline) == len(expected_timeline), f"Expected {len(expected_timeline)} events, got {len(timeline)}."

    for i, (actual, expected) in enumerate(zip(timeline, expected_timeline)):
        assert actual == expected, f"Event at index {i} mismatch. Expected {expected}, got {actual}."


def test_check_gaps_behavior_on_derived_inputs():
    module = load_monitor()

    cases = [
        [],
        [{"time": secrets.randbelow(1000000)}],
        [{"time": 10}, {"time": 70}, {"time": 130}],
        [{"time": 5}, {"time": 70}],
        [{"time": 0}, {"time": 61}, {"time": 122}, {"time": 182}],
    ]

    for _ in range(12):
        current = secrets.randbelow(1000000)
        pings = [{"time": current}]
        for _ in range(1 + secrets.randbelow(8)):
            current += secrets.randbelow(101)
            pings.append({"time": current})
        cases.append(pings)

    for pings in cases:
        expected = sum(
            1 for i in range(len(pings) - 1)
            if pings[i + 1]['time'] - pings[i]['time'] > 60
        )
        actual = module.check_gaps([dict(ping) for ping in pings])
        assert actual == expected, f"check_gaps({pings!r}) returned {actual!r}, expected {expected}."


def test_monitor_py_fixed():
    # Test that running monitor.py does not raise IndexError and exits cleanly
    monitor_script = '/home/user/sre_app/monitor.py'
    assert os.path.isfile(monitor_script), f"{monitor_script} does not exist."

    result = subprocess.run([sys.executable, monitor_script], capture_output=True, text=True)
    assert result.returncode == 0, f"monitor.py failed to run. Stderr: {result.stderr}"
    assert "Total alerts: 1" in result.stdout, "monitor.py output did not contain the correct alert count."


def test_test_monitor_py():
    test_script = '/home/user/sre_app/test_monitor.py'
    assert os.path.isfile(test_script), f"{test_script} does not exist."

    with open(test_script, 'r') as f:
        content = f.read()
    assert "check_gaps" in content, "test_monitor.py does not import or use check_gaps."

    runner = '/tmp/validate_regression_tests.py'
    for mode in ('real', 'mutant_nogap', 'mutant_65'):
        result = subprocess.run(
            [sys.executable, runner, mode, test_script],
            cwd='/home/user/sre_app',
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, (
            f"Regression-test validation failed in mode {mode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
TEST_EOF

cat << 'RUNNER_EOF' > /tmp/validate_regression_tests.py
import copy
import importlib.util
import os
import sys

import pytest

mode = sys.argv[1]
test_script = sys.argv[2]
monitor_path = '/home/user/sre_app/monitor.py'

spec = importlib.util.spec_from_file_location('monitor', monitor_path)
if spec is None or spec.loader is None:
    raise SystemExit(2)
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)
original = monitor.check_gaps
calls = []


def instrumented(pings):
    try:
        calls.append(copy.deepcopy(pings))
    except Exception:
        calls.append(pings)
    result = original(pings)
    if mode == 'mutant_nogap' and isinstance(pings, list) and len(pings) == 5:
        try:
            gaps = [pings[i + 1]['time'] - pings[i]['time'] for i in range(4)]
            if all(gap <= 60 for gap in gaps):
                return result + 97
        except Exception:
            pass
    if mode == 'mutant_65' and isinstance(pings, list):
        try:
            gaps = [pings[i + 1]['time'] - pings[i]['time'] for i in range(len(pings) - 1)]
            if 65 in gaps:
                return result + 97
        except Exception:
            pass
    return result


monitor.check_gaps = instrumented
sys.modules['monitor'] = monitor
sys.modules['sre_app.monitor'] = monitor
sys.path.insert(0, '/home/user/sre_app')
sys.path.insert(0, '/home/user')


class CollectionCounter:
    def __init__(self):
        self.count = 0

    def pytest_collection_finish(self, session):
        self.count = len(session.items)


plugin = CollectionCounter()
pytest_rc = int(pytest.main(['-q', test_script], plugins=[plugin]))

if mode != 'real':
    # A meaningful regression suite must detect either deliberately wrong result.
    raise SystemExit(0 if pytest_rc != 0 else 1)

if pytest_rc != 0 or plugin.count < 2:
    raise SystemExit(1)

saw_five_no_gap = False
saw_exact_65 = False
for pings in calls:
    if not isinstance(pings, list):
        continue
    try:
        times = [ping['time'] for ping in pings]
        gaps = [times[i + 1] - times[i] for i in range(len(times) - 1)]
    except Exception:
        continue
    if len(pings) == 5 and all(gap <= 60 for gap in gaps):
        saw_five_no_gap = True
    if 65 in gaps:
        saw_exact_65 = True

raise SystemExit(0 if saw_five_no_gap and saw_exact_65 else 1)
RUNNER_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
