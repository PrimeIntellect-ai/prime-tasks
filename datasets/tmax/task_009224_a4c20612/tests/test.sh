#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

LOG_DIR = "/home/user/logs"
OUTPUT_FILE = "/home/user/hourly_errors.json"
SCRIPT_FILE = "/home/user/analyze_logs.py"
PATTERN = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}):\d{2}:\d{2}\]\s+(\w+)\s+(.*)$")


def compute_expected(log_dir):
    expected = {}
    if os.path.isdir(log_dir):
        for filename in os.listdir(log_dir):
            if not filename.endswith(".log"):
                continue
            filepath = os.path.join(log_dir, filename)
            with open(filepath, "r", encoding="utf-8") as f:
                for line in f:
                    match = PATTERN.match(line.strip())
                    if match:
                        hour_prefix, level, message = match.groups()
                        if level == "ERROR":
                            bucket = f"{hour_prefix}:00:00"
                            msg_hash = hashlib.md5(message.strip().encode("utf-8")).hexdigest()
                            expected.setdefault(bucket, set()).add(msg_hash)
    return {k: sorted(v) for k, v in expected.items()}


def assert_output(expected):
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        raw_content = f.read()
        try:
            actual = json.loads(raw_content)
        except json.JSONDecodeError:
            assert False, f"{OUTPUT_FILE} is not a valid JSON file."

    assert actual == expected, (
        f"JSON content does not match expected output.\nExpected: {expected}\nActual: {actual}"
    )
    expected_str = json.dumps(expected, indent=2, sort_keys=True)
    assert raw_content.strip() == expected_str.strip(), (
        "JSON formatting does not match expected (ensure indent=2 and sorted keys/lists)."
    )


def test_script_exists_and_uses_parallelism():
    assert os.path.isfile(SCRIPT_FILE), f"Script {SCRIPT_FILE} does not exist."
    with open(SCRIPT_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    # Retain the original assertion, then ensure the keyword is an actual import.
    has_multiprocessing = "multiprocessing" in content
    has_concurrent = "concurrent.futures" in content
    assert has_multiprocessing or has_concurrent, (
        "Script must use 'multiprocessing' or 'concurrent.futures' for parallel processing."
    )

    try:
        tree = ast.parse(content, filename=SCRIPT_FILE)
    except SyntaxError as exc:
        assert False, f"Script is not valid Python: {exc}"

    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module)
    assert any(name == "multiprocessing" or name.startswith("multiprocessing.") or
               name == "concurrent.futures" or name.startswith("concurrent.futures.")
               for name in imported), (
        "The parallel-processing module must be imported, not merely mentioned in text."
    )


def test_json_output_content_and_format():
    # Check the final artifact the instruction required for the original logs.
    expected = compute_expected(LOG_DIR)
    assert_output(expected)


def test_script_executes_on_changed_logs_and_invokes_parallel_api():
    backup_dir = "/tmp/logs_before_verification"
    hook_dir = "/tmp/parallel_audit_hook"
    marker = "/tmp/parallel_audit_events"
    old_output = None

    if os.path.exists(backup_dir):
        shutil.rmtree(backup_dir)
    if os.path.exists(hook_dir):
        shutil.rmtree(hook_dir)
    if os.path.exists(marker):
        os.remove(marker)
    if os.path.isfile(OUTPUT_FILE):
        with open(OUTPUT_FILE, "rb") as f:
            old_output = f.read()

    os.rename(LOG_DIR, backup_dir)
    os.makedirs(LOG_DIR)
    changed_logs = {
        "alpha.log": [
            "[2041-02-03 01:01:01] ERROR Zebra failure\n",
            "[2041-02-03 01:02:02] ERROR Zebra failure\n",
            "[2041-02-03 01:03:03] INFO Must not be included\n",
            "[2041-02-03 02:04:04] ERROR   whitespace-sensitive message   \n",
        ],
        "beta.log": [
            "[2041-02-03 01:55:00] ERROR Another newly injected error\n",
            "[2041-02-03 02:10:00] WARN Not an error\n",
            "[2041-02-04 23:59:59] ERROR Unicode café failure\n",
        ],
        "gamma.log": [
            "[2041-02-03 01:59:59] ERROR Another newly injected error\n",
            "[2041-02-03 03:00:00] ERRORS Wrong level\n",
            "malformed ERROR line\n",
        ],
    }
    for filename, lines in changed_logs.items():
        with open(os.path.join(LOG_DIR, filename), "w", encoding="utf-8") as f:
            f.writelines(lines)
    with open(os.path.join(LOG_DIR, "ignored.txt"), "w", encoding="utf-8") as f:
        f.write("[2041-02-03 09:00:00] ERROR Wrong extension\n")

    os.makedirs(hook_dir)
    hook = r'''
import os

_marker = os.environ.get("PARALLEL_AUDIT_MARKER")

def _record(event):
    if _marker:
        try:
            with open(_marker, "a", encoding="utf-8") as f:
                f.write(event + "\n")
        except Exception:
            pass

try:
    import concurrent.futures as _cf
    import concurrent.futures._base as _base

    for _name in ("ThreadPoolExecutor", "ProcessPoolExecutor"):
        _cls = getattr(_cf, _name)
        _old_init = _cls.__init__
        _old_submit = _cls.submit

        def _make_init(old, name):
            def wrapped(self, *args, **kwargs):
                _record("C_INIT:" + name)
                return old(self, *args, **kwargs)
            return wrapped

        def _make_submit(old, name):
            def wrapped(self, *args, **kwargs):
                _record("C_SUBMIT:" + name)
                return old(self, *args, **kwargs)
            return wrapped

        _cls.__init__ = _make_init(_old_init, _name)
        _cls.submit = _make_submit(_old_submit, _name)

    _old_base_map = _base.Executor.map
    def _base_map(self, *args, **kwargs):
        _record("C_MAP")
        return _old_base_map(self, *args, **kwargs)
    _base.Executor.map = _base_map

    _old_process_map = _cf.ProcessPoolExecutor.map
    def _process_map(self, *args, **kwargs):
        _record("C_MAP")
        return _old_process_map(self, *args, **kwargs)
    _cf.ProcessPoolExecutor.map = _process_map
except Exception:
    pass

try:
    import multiprocessing.pool as _mp_pool
    _old_pool_init = _mp_pool.Pool.__init__
    def _pool_init(self, *args, **kwargs):
        _record("P_INIT")
        return _old_pool_init(self, *args, **kwargs)
    _mp_pool.Pool.__init__ = _pool_init

    for _name in ("map", "map_async", "imap", "imap_unordered", "starmap", "starmap_async", "apply_async"):
        if hasattr(_mp_pool.Pool, _name):
            _old = getattr(_mp_pool.Pool, _name)
            def _make_pool_call(old, name):
                def wrapped(self, *args, **kwargs):
                    _record("P_OP:" + name)
                    return old(self, *args, **kwargs)
                return wrapped
            setattr(_mp_pool.Pool, _name, _make_pool_call(_old, _name))
except Exception:
    pass

try:
    import multiprocessing.process as _mp_process
    _old_start = _mp_process.BaseProcess.start
    def _start(self, *args, **kwargs):
        _record("M_START")
        return _old_start(self, *args, **kwargs)
    _mp_process.BaseProcess.start = _start
except Exception:
    pass
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(hook)

    try:
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)

        env = os.environ.copy()
        env["PARALLEL_AUDIT_MARKER"] = marker
        env["PYTHONPATH"] = hook_dir + os.pathsep + env.get("PYTHONPATH", "")
        result = subprocess.run(
            [sys.executable, SCRIPT_FILE],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Script failed when executed on changed logs.\nstdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )

        expected = compute_expected(LOG_DIR)
        assert_output(expected)

        events = []
        if os.path.isfile(marker):
            with open(marker, "r", encoding="utf-8") as f:
                events = [line.strip() for line in f if line.strip()]

        concurrent_init = any(e.startswith("C_INIT:") for e in events)
        concurrent_work = any(e == "C_MAP" for e in events) or sum(
            e.startswith("C_SUBMIT:") for e in events
        ) >= 2
        pool_used = "P_INIT" in events and any(e.startswith("P_OP:") for e in events)
        manual_processes = sum(e == "M_START" for e in events) >= 2
        assert (concurrent_init and concurrent_work) or pool_used or manual_processes, (
            "The executed script did not actually invoke a multiprocessing or "
            "concurrent.futures parallel-work API."
        )
    finally:
        if os.path.exists(LOG_DIR):
            shutil.rmtree(LOG_DIR)
        os.rename(backup_dir, LOG_DIR)
        if old_output is None:
            if os.path.exists(OUTPUT_FILE):
                os.remove(OUTPUT_FILE)
        else:
            with open(OUTPUT_FILE, "wb") as f:
                f.write(old_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
