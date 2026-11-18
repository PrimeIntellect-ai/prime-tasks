#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import random
import subprocess
import sys
import tempfile
import textwrap

import pytest


def assert_trigger_payload(path):
    assert os.path.isfile(path), f"{path} does not exist."

    with open(path, 'r') as f:
        try:
            payload = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} is not valid JSON.")

    assert isinstance(payload, dict), "Payload must be a JSON object."
    nodes = payload.get('nodes', [])
    assert isinstance(nodes, list) and len(nodes) > 0, "No nodes found in the JSON payload."

    triggers = False
    for node in nodes:
        assert isinstance(node, dict), "Each node must be a JSON object."
        assert 'id' in node, "Each node must contain an id."
        assert 'metrics' in node and isinstance(node['metrics'], dict), \
            "Each node must contain a metrics object."
        m = node.get('metrics', {})
        b = m.get('base_score', 100)
        p = m.get('penalty', 0)
        l = m.get('latency_ms', 1)
        if b - p - l == 0:
            triggers = True
            break

    assert triggers, "bug_trigger.json does not contain metrics that would cause the divisor to be 0."
    return payload


def load_aggregator():
    path = '/home/user/health_aggregator.py'
    assert os.path.isfile(path), f"{path} does not exist."
    spec = importlib.util.spec_from_file_location('submitted_health_aggregator', path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_bug_trigger_payload():
    """Verify that bug_trigger.json exists, is valid JSON, and contains a crashing payload."""
    assert_trigger_payload('/home/user/bug_trigger.json')


def test_health_aggregator_fixed_logic():
    """Verify zero handling and preserve the original computation across varied inputs."""
    health_aggregator = load_aggregator()

    # Preserve the original fixed-fixture assertions.
    normal_metrics = {'base_score': 100, 'penalty': 0, 'latency_ms': 50}
    try:
        score = health_aggregator.compute_score(normal_metrics)
        assert score == 20.0, f"Normal computation failed, expected 20.0, got {score}"
    except Exception as e:
        pytest.fail(f"compute_score raised an exception for normal metrics: {e}")

    bug_metrics = {'base_score': 100, 'penalty': 50, 'latency_ms': 50}
    try:
        score_zero = health_aggregator.compute_score(bug_metrics)
        assert score_zero == 0, f"compute_score did not return 0 for zero divisor, got {score_zero}"
    except ZeroDivisionError:
        pytest.fail("compute_score still raises ZeroDivisionError when divisor is 0")
    except Exception as e:
        pytest.fail(f"compute_score raised an unexpected exception for bug metrics: {e}")

    # Exercise dynamically generated cases whose expected values are derived here.
    rng = random.SystemRandom()
    cases = [{}, {'base_score': 20}, {'penalty': -7}, {'latency_ms': 9}]
    for _ in range(120):
        base = rng.randint(-10000, 10000)
        penalty = rng.randint(-10000, 10000)
        if rng.randrange(5) == 0:
            latency = base - penalty
        else:
            latency = rng.randint(-10000, 10000)
            if base - penalty - latency == 0:
                latency += 1
        cases.append({
            'base_score': base,
            'penalty': penalty,
            'latency_ms': latency,
            'irrelevant': rng.randint(-100, 100),
        })

    for metrics in cases:
        base = metrics.get('base_score', 100)
        penalty = metrics.get('penalty', 0)
        latency = metrics.get('latency_ms', 1)
        divisor = base - penalty - latency
        expected = 0 if divisor == 0 else 1000 / divisor
        try:
            actual = health_aggregator.compute_score(dict(metrics))
        except Exception as e:
            pytest.fail(f"compute_score raised for generated metrics {metrics!r}: {e}")
        assert actual == expected, \
            f"compute_score({metrics!r}) returned {actual!r}; expected {expected!r}"


def test_fuzzer_exists_and_runs_randomized_search():
    """Run the submitted fuzzer against the original buggy program and inspect its result."""
    fuzzer_path = '/home/user/fuzzer.py'
    aggregator_path = '/home/user/health_aggregator.py'
    trigger_path = '/home/user/bug_trigger.json'
    assert os.path.isfile(fuzzer_path), f"{fuzzer_path} does not exist."

    with open(aggregator_path, 'rb') as f:
        fixed_aggregator = f.read()
    with open(trigger_path, 'rb') as f:
        original_trigger = f.read()

    buggy_aggregator = textwrap.dedent('''\
        import json
        import sys

        def compute_score(metrics):
            base = metrics.get('base_score', 100)
            penalty = metrics.get('penalty', 0)
            latency = metrics.get('latency_ms', 1)
            divisor = base - penalty - latency
            return 1000 / divisor

        def process_health_data(data):
            for node in data.get("nodes", []):
                node_id = node.get("id", "unknown")
                metrics = node.get("metrics", {})
                try:
                    score = compute_score(metrics)
                    print(f"Node {node_id} score: {score}")
                except ZeroDivisionError as e:
                    raise ZeroDivisionError(f"Crash processing node {node_id}") from e

        if __name__ == "__main__":
            if len(sys.argv) != 2:
                print("Usage: python health_aggregator.py <payload.json>")
                sys.exit(1)
            try:
                with open(sys.argv[1], 'r') as f:
                    data = json.load(f)
                process_health_data(data)
            except Exception as e:
                print(f"Fatal Error: {type(e).__name__}: {e}")
                sys.exit(1)
    ''')

    with tempfile.TemporaryDirectory() as hook_dir:
        call_log = os.path.join(hook_dir, 'random_calls.log')
        sitecustomize = textwrap.dedent('''\
            import functools
            import os
            import random
            import secrets

            _log = os.environ.get('FUZZ_RANDOM_CALL_LOG')
            def _record(name):
                if _log:
                    with open(_log, 'a') as f:
                        f.write(name + "\\n")

            def _wrap(module, name):
                original = getattr(module, name, None)
                if original is None:
                    return
                @functools.wraps(original)
                def wrapped(*args, **kwargs):
                    _record(module.__name__ + '.' + name)
                    return original(*args, **kwargs)
                setattr(module, name, wrapped)

            for _name in ('random', 'randint', 'randrange', 'choice', 'choices',
                          'sample', 'shuffle', 'uniform', 'getrandbits'):
                _wrap(random, _name)
            for _name in ('choice', 'randbelow', 'randbits', 'token_bytes',
                          'token_hex', 'token_urlsafe'):
                _wrap(secrets, _name)

            _original_urandom = os.urandom
            def _urandom(n):
                _record('os.urandom')
                return _original_urandom(n)
            os.urandom = _urandom
        ''')
        with open(os.path.join(hook_dir, 'sitecustomize.py'), 'w') as f:
            f.write(sitecustomize)

        generated_payload = None
        try:
            with open(aggregator_path, 'w') as f:
                f.write(buggy_aggregator)
            os.unlink(trigger_path)

            env = os.environ.copy()
            env['PYTHONPATH'] = hook_dir + os.pathsep + env.get('PYTHONPATH', '')
            env['FUZZ_RANDOM_CALL_LOG'] = call_log
            try:
                result = subprocess.run(
                    [sys.executable, fuzzer_path],
                    cwd='/home/user', env=env,
                    capture_output=True, text=True, timeout=20
                )
            except subprocess.TimeoutExpired:
                pytest.fail("fuzzer.py did not finish within 20 seconds against the buggy program.")

            assert result.returncode == 0, (
                f"fuzzer.py exited with code {result.returncode}.\n"
                f"Stdout: {result.stdout}\nStderr: {result.stderr}"
            )
            generated_payload = assert_trigger_payload(trigger_path)
            assert os.path.isfile(call_log) and os.path.getsize(call_log) > 0, \
                "fuzzer.py completed without using a standard randomized input source."
        finally:
            with open(aggregator_path, 'wb') as f:
                f.write(fixed_aggregator)
            with open(trigger_path, 'wb') as f:
                f.write(original_trigger)

        assert generated_payload is not None


def test_health_aggregator_execution():
    """Verify that running the script with bug_trigger.json exits with 0 and doesn't crash."""
    script_path = '/home/user/health_aggregator.py'
    payload_path = '/home/user/bug_trigger.json'

    if not os.path.exists(payload_path):
        pytest.skip("bug_trigger.json not found, skipping execution test.")

    result = subprocess.run(
        [sys.executable, script_path, payload_path],
        capture_output=True, text=True
    )

    assert result.returncode == 0, (
        f"health_aggregator.py exited with code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert "ZeroDivisionError" not in result.stdout, "health_aggregator.py stdout contains ZeroDivisionError."
    assert "ZeroDivisionError" not in result.stderr, "health_aggregator.py stderr contains ZeroDivisionError."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
