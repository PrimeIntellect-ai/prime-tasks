#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import textwrap
import time

import pytest

APP_DIR = "/home/user/app"
REPORT_PATH = "/home/user/report.json"
TEST_SCRIPT_PATH = "/home/user/test_race.py"
WORKER_PATH = os.path.join(APP_DIR, "worker.py")


def get_expected_commit_hash():
    try:
        result = subprocess.run(
            ["git", "log", "--grep=Optimize cache updates", "--format=%H"],
            cwd=APP_DIR,
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None


def test_report_json():
    assert os.path.isfile(REPORT_PATH), f"Report file not found at {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not valid JSON")

    expected_api_key = "sk-live-99a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4"
    expected_hash = get_expected_commit_hash()

    assert report.get("leaked_api_key") == expected_api_key, "Incorrect leaked_api_key in report.json"
    assert report.get("leak_commit_hash") == expected_hash, "Incorrect leak_commit_hash in report.json"


def test_regression_script_behavior():
    assert os.path.isfile(TEST_SCRIPT_PATH), f"Regression test script not found at {TEST_SCRIPT_PATH}"

    # Ensure we are on the buggy commit (HEAD)
    subprocess.run(["git", "checkout", "master"], cwd=APP_DIR, capture_output=True)

    # Run script on buggy code
    result_buggy = subprocess.run(
        ["python3", TEST_SCRIPT_PATH],
        cwd=APP_DIR,
        capture_output=True,
    )
    assert result_buggy.returncode == 1, "test_race.py should exit with code 1 when the race condition is present"

    # Checkout previous commit (safe code)
    try:
        subprocess.run(["git", "checkout", "HEAD~1"], cwd=APP_DIR, capture_output=True, check=True)

        # Run script on safe code
        result_safe = subprocess.run(
            ["python3", TEST_SCRIPT_PATH],
            cwd=APP_DIR,
            capture_output=True,
        )
        assert result_safe.returncode == 0, "test_race.py should exit with code 0 when the race condition is NOT present"
    finally:
        # Restore git state
        subprocess.run(["git", "checkout", "-"], cwd=APP_DIR, capture_output=True)


def _instrumented_worker(trace_path, vulnerable):
    common = f'''
import json
import os
import threading
import time

_TRACE_PATH = {trace_path!r}
_trace_guard = threading.Lock()


def _record(event):
    row = {{"event": event, "pid": os.getpid(), "tid": threading.get_ident()}}
    with _trace_guard:
        with open(_TRACE_PATH, "a", encoding="utf-8") as stream:
            stream.write(json.dumps(row) + "\\n")


class ConcurrentCache:
    def __init__(self):
        self.cache = []
        self._tracking_guard = threading.Lock()
        self._seen_threads = set()
        self._active = 0

    def _enter(self):
        tid = threading.get_ident()
        with self._tracking_guard:
            first = tid not in self._seen_threads
            self._seen_threads.add(tid)
            self._active += 1
        if first:
            _record("enter")
            # Release the GIL so independently started worker threads overlap.
            time.sleep(0.03)
        return first

    def _leave(self, first):
        if first:
            _record("exit")
        with self._tracking_guard:
            self._active -= 1
'''
    if vulnerable:
        body = '''
        # A decoy lock deliberately makes structural `_lock` checks insufficient.
        self._lock = threading.RLock()
        self._collision = threading.Barrier(2)
        self._forced = False
        self._reported = False

    def add_item(self, item):
        first = self._enter()
        try:
            old = self.cache
            force = not self._forced
            collided = False
            if force:
                try:
                    self._collision.wait(timeout=1.0)
                    collided = True
                except threading.BrokenBarrierError:
                    pass
            self.cache = old + [item]
            if collided:
                with self._tracking_guard:
                    self._forced = True
                    if not self._reported:
                        self._reported = True
                        _record("corruption")
        finally:
            self._leave(first)

    def clear(self):
        self.cache = []
'''
    else:
        body = '''
        # Correct synchronization intentionally does not use the name `_lock`.
        self.guard_for_updates = threading.RLock()

    def add_item(self, item):
        first = self._enter()
        try:
            with self.guard_for_updates:
                self.cache.append(item)
        finally:
            self._leave(first)

    def clear(self):
        with self.guard_for_updates:
            self.cache.clear()
'''
    return textwrap.dedent(common + body)


def _read_trace(path):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path, encoding="utf-8") as stream:
        for line in stream:
            try:
                rows.append(json.loads(line))
            except (ValueError, TypeError):
                pass
    return rows


def _assert_real_threaded_exercise(rows, require_corruption):
    # Find one process in which two distinct threads entered add_item before
    # either exited. This cannot be produced by merely checking HEAD or fields.
    by_pid = {}
    for row in rows:
        if row.get("event") in {"enter", "exit", "corruption"}:
            by_pid.setdefault(row.get("pid"), []).append(row)

    witnessed_overlap = False
    for events in by_pid.values():
        active = set()
        for row in events:
            if row.get("event") == "enter":
                active.add(row.get("tid"))
                if len(active) >= 2:
                    witnessed_overlap = True
            elif row.get("event") == "exit":
                active.discard(row.get("tid"))

    assert witnessed_overlap, "test_race.py did not exercise ConcurrentCache.add_item concurrently from multiple threads"
    corruption_seen = any(row.get("event") == "corruption" for row in rows)
    assert corruption_seen == require_corruption, "threaded execution did not exhibit the expected corruption behavior"


def test_regression_script_on_behavioral_variants(tmp_path):
    # Both variants run while HEAD remains master. The unsafe variant has an
    # `_lock`, while the safe variant does not, defeating fixed revision and
    # attribute-presence shortcuts.
    subprocess.run(["git", "checkout", "master"], cwd=APP_DIR, capture_output=True, check=True)
    with open(WORKER_PATH, "rb") as stream:
        original_worker = stream.read()

    cases = [(True, 1), (False, 0)]
    if secrets.randbelow(2):
        cases.reverse()

    try:
        for index, (vulnerable, expected_code) in enumerate(cases):
            trace_path = str(tmp_path / f"trace-{index}-{secrets.token_hex(8)}.jsonl")
            with open(WORKER_PATH, "w", encoding="utf-8") as stream:
                stream.write(_instrumented_worker(trace_path, vulnerable))
            subprocess.run(["rm", "-rf", os.path.join(APP_DIR, "__pycache__")], check=False)

            result = subprocess.run(
                ["python3", TEST_SCRIPT_PATH],
                cwd=APP_DIR,
                capture_output=True,
                timeout=30,
            )
            assert result.returncode == expected_code, (
                f"test_race.py returned {result.returncode} for a "
                f"{'corrupting' if vulnerable else 'thread-safe'} behavioral variant; expected {expected_code}"
            )
            _assert_real_threaded_exercise(_read_trace(trace_path), vulnerable)
    finally:
        with open(WORKER_PATH, "wb") as stream:
            stream.write(original_worker)
        subprocess.run(["rm", "-rf", os.path.join(APP_DIR, "__pycache__")], check=False)
        subprocess.run(["git", "checkout", "master"], cwd=APP_DIR, capture_output=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
