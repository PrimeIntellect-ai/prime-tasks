#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import random
import runpy
import sqlite3
import sys
import tempfile

SCRIPT_PATH = "/home/user/log_processor.py"
FUZZ_PATH = "/home/user/fuzz_test.py"


def load_processor(module_name="log_processor_under_test"):
    spec = importlib.util.spec_from_file_location(module_name, SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def test_log_processor_fixed():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert "?" in content or ":username" in content or "%s" in content, \
        "The script does not seem to use parameterized queries."
    assert "f\"SELECT" not in content and "f'SELECT" not in content, \
        "The script still appears to use f-strings for the SQL query."
    assert "Lock" in content, \
        "The script does not seem to use threading.Lock for synchronization."


def test_processor_behavior_and_lock_usage():
    module = load_processor()
    entrypoint = getattr(module, "main", None)
    if not callable(entrypoint):
        entrypoint = getattr(module, "process_logs", None)
    assert callable(entrypoint), "log_processor.py has no callable main/process_logs entry point."

    # Find synchronization objects created by the submitted module. The tracking
    # dictionary below verifies that aggregation accesses occur while one is held.
    locks = []
    for value in vars(module).values():
        if callable(getattr(value, "acquire", None)) and callable(getattr(value, "release", None)):
            if callable(getattr(value, "locked", None)) or callable(getattr(value, "_is_owned", None)):
                locks.append(value)
    assert locks, "No usable synchronization primitive was created by log_processor.py."

    def lock_is_held(lock):
        try:
            if callable(getattr(lock, "locked", None)) and lock.locked():
                return True
        except Exception:
            pass
        try:
            if callable(getattr(lock, "_is_owned", None)) and lock._is_owned():
                return True
        except Exception:
            pass
        return False

    class TrackingDict(dict):
        def __init__(self):
            super().__init__()
            self.update_accesses = 0
            self.unlocked_accesses = 0

        def _check(self):
            self.update_accesses += 1
            if not any(lock_is_held(lock) for lock in locks):
                self.unlocked_accesses += 1

        def get(self, key, default=None):
            self._check()
            return super().get(key, default)

        def __getitem__(self, key):
            self._check()
            return super().__getitem__(key)

        def __setitem__(self, key, value):
            self._check()
            return super().__setitem__(key, value)

        def setdefault(self, key, default=None):
            self._check()
            return super().setdefault(key, default)

    tracker = TrackingDict()
    module.role_counts = tracker

    with tempfile.TemporaryDirectory() as tmp:
        db_path = os.path.join(tmp, "users.db")
        log_dir = os.path.join(tmp, "logs")
        os.mkdir(log_dir)

        conn = sqlite3.connect(db_path)
        conn.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, role TEXT)")
        users = [
            ("alice", "admin"),
            ("bob", "user"),
            ("O'Connor", "guest"),
            ("eve", "ordinary"),
            ("eve'--", "quoted"),
            ("dave_ops", "devops"),
        ]
        conn.executemany("INSERT INTO users (username, role) VALUES (?, ?)", users)
        conn.commit()
        conn.close()

        names = ["alice", "bob", "O'Connor", "eve'--", "dave_ops", "missing_user"]
        expected = {}
        role_map = dict(users)
        for file_number in range(20):
            path = os.path.join(log_dir, f"generated_{file_number}.log")
            with open(path, "w") as f:
                for line_number in range(60):
                    username = names[(file_number + line_number) % len(names)]
                    f.write(f"[2026-01-01T00:00:{line_number:02d}] {username} VIEW\n")
                    role = role_map.get(username, "unknown")
                    expected[role] = expected.get(role, 0) + 1

        result = entrypoint(log_dir, db_path)
        assert isinstance(result, dict), "The processing entry point did not return a dictionary."
        assert dict(result) == expected, \
            f"Processing generated concurrent logs produced wrong counts: expected {expected}, got {result}"
        assert module.role_counts is tracker, \
            "The submitted code replaced the aggregation dictionary, preventing synchronization validation."
        assert tracker.update_accesses > 0, "No aggregation updates were observed."
        assert tracker.unlocked_accesses == 0, \
            f"Observed {tracker.unlocked_accesses} aggregation accesses outside the synchronization primitive."


def inspect_generated_inputs(args, kwargs):
    count = 0
    has_tricky = False
    seen_paths = set()

    def inspect(value):
        nonlocal count, has_tricky
        if isinstance(value, os.PathLike):
            value = os.fspath(value)
        if isinstance(value, str):
            if os.path.isdir(value):
                for root, _, files in os.walk(value):
                    for filename in files:
                        if filename.endswith(".log"):
                            inspect(os.path.join(root, filename))
            elif os.path.isfile(value) and value.endswith(".log"):
                real = os.path.realpath(value)
                if real in seen_paths:
                    return
                seen_paths.add(real)
                with open(value, "r", errors="replace") as f:
                    for line in f:
                        if line.strip():
                            count += 1
                            if "O'Connor" in line:
                                has_tricky = True
            elif "\n" in value or (" " in value and "[" in value):
                for line in value.splitlines():
                    if line.strip():
                        count += 1
                        if "O'Connor" in line:
                            has_tricky = True
        elif isinstance(value, (list, tuple, set)):
            for item in value:
                inspect(item)
        elif isinstance(value, dict):
            for item in value.values():
                inspect(item)

    for value in args:
        inspect(value)
    for value in kwargs.values():
        inspect(value)
    return count, has_tricky


def execute_fuzzer(sabotage=False):
    module = load_processor("log_processor")
    observations = {"calls": 0, "lines": 0, "tricky": False}

    function_names = [name for name in ("main", "process_logs") if callable(getattr(module, name, None))]
    assert function_names, "log_processor.py has no main/process_logs function for the fuzzer to call."

    for name in function_names:
        original = getattr(module, name)

        def make_wrapper(fn):
            def wrapper(*args, **kwargs):
                line_count, has_tricky = inspect_generated_inputs(args, kwargs)
                observations["calls"] += 1
                observations["lines"] += line_count
                observations["tricky"] = observations["tricky"] or has_tricky
                result = fn(*args, **kwargs)
                if sabotage and isinstance(result, dict):
                    altered = dict(result)
                    key = next(iter(altered), "unknown")
                    altered[key] = altered.get(key, 0) + 1
                    return altered
                return result
            return wrapper

        setattr(module, name, make_wrapper(original))

    old_argv = sys.argv[:]
    old_path = sys.path[:]
    try:
        sys.argv = [FUZZ_PATH]
        if "/home/user" not in sys.path:
            sys.path.insert(0, "/home/user")
        runpy.run_path(FUZZ_PATH, run_name="__main__")
    finally:
        sys.argv = old_argv
        sys.path[:] = old_path
        sys.modules.pop("log_processor", None)
    return observations


def test_fuzz_test_exists_and_valid():
    assert os.path.exists(FUZZ_PATH), f"Fuzz testing script {FUZZ_PATH} does not exist."

    with open(FUZZ_PATH, "r") as f:
        content = f.read()

    try:
        tree = ast.parse(content)
    except SyntaxError as e:
        assert False, f"Syntax error in fuzz_test.py: {e}"

    # Preserve the original assertion check, then ensure it is not merely
    # `assert True` and that randomized generation is actually present.
    assertions = [node for node in ast.walk(tree) if isinstance(node, ast.Assert)]
    assert assertions, "fuzz_test.py does not contain any assert statements to validate the counts."
    assert any(not (isinstance(node.test, ast.Constant) and bool(node.test.value)) for node in assertions), \
        "fuzz_test.py only contains assertions that are unconditionally true."

    random_aliases = {"random"}
    random_functions = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "random":
                    random_aliases.add(alias.asname or alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module == "random":
            for alias in node.names:
                random_functions.add(alias.asname or alias.name)

    uses_random = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
            uses_random |= node.func.value.id in random_aliases
        elif isinstance(node.func, ast.Name):
            uses_random |= node.func.id in random_functions
    assert uses_random, "fuzz_test.py does not call a random-generation function."

    observations = execute_fuzzer(sabotage=False)
    assert observations["calls"] > 0, "fuzz_test.py did not call main/process_logs."
    assert observations["lines"] >= 100, \
        f"fuzz_test.py processed only {observations['lines']} generated lines; it must fuzz a large input."
    assert observations["tricky"], "fuzz_test.py did not process the required O'Connor username."

    try:
        execute_fuzzer(sabotage=True)
    except AssertionError:
        pass
    else:
        assert False, \
            "fuzz_test.py did not fail when the processor's returned total was deliberately made incorrect."


def test_final_counts_json():
    json_path = "/home/user/final_counts.json"
    assert os.path.exists(json_path), f"Final output file {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            actual_counts = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} is not a valid JSON file."

    db_path = "/home/user/users.db"
    assert os.path.exists(db_path), f"Database {db_path} missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT username, role FROM users")
    user_roles = dict(cursor.fetchall())
    conn.close()

    log_dir = "/home/user/test_logs"
    assert os.path.exists(log_dir), f"Log directory {log_dir} missing."

    expected_counts = {}
    for filename in os.listdir(log_dir):
        if filename.endswith('.log'):
            with open(os.path.join(log_dir, filename), "r") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    parts = line.split(' ')
                    if len(parts) >= 3:
                        username = parts[1]
                        role = user_roles.get(username, "unknown")
                        expected_counts[role] = expected_counts.get(role, 0) + 1

    assert actual_counts == expected_counts, \
        f"Final counts in {json_path} do not match the expected counts. Expected: {expected_counts}, Got: {actual_counts}"
TEST_EOF

if timeout 90s python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
