#!/bin/bash
set -e
mkdir -p /logs/verifier

HOOK_DIR=/tmp/verifier_hooks
EVENT_LOG=/tmp/parallel_mcmc_pool_events.jsonl
rm -rf "$HOOK_DIR"
mkdir -p "$HOOK_DIR"
rm -f "$EVENT_LOG"

cat << 'HOOK_EOF' > "$HOOK_DIR/sitecustomize.py"
import json
import multiprocessing
import os

_real_pool = multiprocessing.Pool
_log_path = os.environ.get("POOL_EVENT_LOG")


def _log(event):
    if not _log_path:
        return
    with open(_log_path, "a") as f:
        f.write(json.dumps(event, default=repr) + "\n")


def _function_info(func):
    return {
        "module": getattr(func, "__module__", None),
        "name": getattr(func, "__name__", None),
    }


class TrackingPool:
    def __init__(self, *args, **kwargs):
        _log({"event": "pool_created"})
        self._pool = _real_pool(*args, **kwargs)

    def map(self, func, iterable, *args, **kwargs):
        items = list(iterable)
        _log({"event": "submit", "method": "map", "function": _function_info(func), "items": items})
        return self._pool.map(func, items, *args, **kwargs)

    def map_async(self, func, iterable, *args, **kwargs):
        items = list(iterable)
        _log({"event": "submit", "method": "map_async", "function": _function_info(func), "items": items})
        return self._pool.map_async(func, items, *args, **kwargs)

    def imap(self, func, iterable, *args, **kwargs):
        items = list(iterable)
        _log({"event": "submit", "method": "imap", "function": _function_info(func), "items": items})
        return self._pool.imap(func, items, *args, **kwargs)

    def imap_unordered(self, func, iterable, *args, **kwargs):
        items = list(iterable)
        _log({"event": "submit", "method": "imap_unordered", "function": _function_info(func), "items": items})
        return self._pool.imap_unordered(func, items, *args, **kwargs)

    def starmap(self, func, iterable, *args, **kwargs):
        items = list(iterable)
        _log({"event": "submit", "method": "starmap", "function": _function_info(func), "items": items})
        return self._pool.starmap(func, items, *args, **kwargs)

    def starmap_async(self, func, iterable, *args, **kwargs):
        items = list(iterable)
        _log({"event": "submit", "method": "starmap_async", "function": _function_info(func), "items": items})
        return self._pool.starmap_async(func, items, *args, **kwargs)

    def apply_async(self, func, args=(), kwds=None, *extra_args, **extra_kwargs):
        if kwds is None:
            kwds = {}
        _log({"event": "submit", "method": "apply_async", "function": _function_info(func), "items": list(args)})
        return self._pool.apply_async(func, args, kwds, *extra_args, **extra_kwargs)

    def __enter__(self):
        self._pool.__enter__()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return self._pool.__exit__(exc_type, exc_value, traceback)

    def __getattr__(self, name):
        return getattr(self._pool, name)


multiprocessing.Pool = TrackingPool
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess
import sys

import pytest

SCRIPT_PATH = '/home/user/parallel_mcmc.py'
OUTPUT_PATH = '/home/user/final_k.txt'
EVENT_LOG = '/tmp/parallel_mcmc_pool_events.jsonl'


@pytest.fixture(scope='session', autouse=True)
def execute_and_check_parallel_script():
    assert os.path.isfile(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."

    with open(SCRIPT_PATH, 'r') as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)
    imported = any(
        isinstance(node, ast.ImportFrom)
        and node.module == 'mcmc_ode'
        and any(alias.name == 'run_mcmc' for alias in node.names)
        for node in ast.walk(tree)
    )
    assert imported, "parallel_mcmc.py must import run_mcmc from mcmc_ode.py"

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    if os.path.exists(EVENT_LOG):
        os.remove(EVENT_LOG)

    env = os.environ.copy()
    env['POOL_EVENT_LOG'] = EVENT_LOG
    hook_dir = '/tmp/verifier_hooks'
    env['PYTHONPATH'] = hook_dir + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"parallel_mcmc.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isfile(EVENT_LOG), "parallel_mcmc.py did not create a multiprocessing.Pool"
    with open(EVENT_LOG, 'r') as f:
        events = [json.loads(line) for line in f if line.strip()]
    assert any(event.get('event') == 'pool_created' for event in events), (
        "parallel_mcmc.py did not use multiprocessing.Pool"
    )

    submitted_seeds = []
    for event in events:
        if event.get('event') != 'submit':
            continue
        function = event.get('function', {})
        if function.get('module') != 'mcmc_ode' or function.get('name') != 'run_mcmc':
            continue
        method = event.get('method')
        items = event.get('items', [])
        if method in {'map', 'map_async', 'imap', 'imap_unordered'}:
            submitted_seeds.extend(items)
        elif method in {'starmap', 'starmap_async'}:
            submitted_seeds.extend(item[0] for item in items if item)
        elif method == 'apply_async' and items:
            submitted_seeds.append(items[0])

    assert submitted_seeds == [42, 43, 44, 45], (
        "multiprocessing.Pool must run mcmc_ode.run_mcmc for seeds [42, 43, 44, 45]"
    )


def test_parallel_mcmc_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."


def test_final_k_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Expected output file {OUTPUT_PATH} does not exist."


def test_final_k_value():
    sys.path.insert(0, '/home/user')
    try:
        from mcmc_ode import run_mcmc
    except ImportError:
        pytest.fail("Could not import run_mcmc from /home/user/mcmc_ode.py")

    res = []
    for s in [42, 43, 44, 45]:
        res.append(run_mcmc(s))
    expected_k = sum(res) / 4.0
    expected_str = f"{expected_k:.4f}"

    with open(OUTPUT_PATH, 'r') as f:
        actual_str = f.read().strip()

    assert actual_str == expected_str, f"Expected final k value to be '{expected_str}', but got '{actual_str}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
