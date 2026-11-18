#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import importlib.util
import os
import secrets
import subprocess
import sys
import time

import pytest
from hypothesis import given, settings, strategies as st

DATAPROC = '/home/user/dataproc'
TEST_FILE = '/home/user/dataproc/test_models.py'


def _add_dataproc_path():
    if DATAPROC not in sys.path:
        sys.path.insert(0, DATAPROC)


def test_circular_import_fixed():
    """Verify that models.py can be imported without ImportError."""
    sys.path.insert(0, '/home/user/dataproc')
    try:
        import models
        import validator
    except ImportError as e:
        assert False, f"ImportError still present: {e}"
    finally:
        if '/home/user/dataproc' in sys.path:
            sys.path.remove('/home/user/dataproc')


def test_rate_limiting_logic():
    """Verify the rate limiter allows 3 requests per second per client_id."""
    sys.path.insert(0, '/home/user/dataproc')
    try:
        import validator
        importlib.reload(validator) # Ensure clean state if previously imported
    except ImportError:
        assert False, "Could not import validator.py"
    finally:
        if '/home/user/dataproc' in sys.path:
            sys.path.remove('/home/user/dataproc')

    client_id = "test_client_final"
    results = [validator.rate_limit_check(client_id) for _ in range(5)]
    assert results == [True, True, True, False, False], f"Rate limiting failed for 5 rapid requests. Got {results}"

    time.sleep(1.1)
    assert validator.rate_limit_check(client_id) is True, "Rate limiting failed to reset after 1 second."


def test_rate_limiting_is_per_random_client():
    """Exercise independent, unpredictable client IDs rather than one fixed case."""
    _add_dataproc_path()
    import validator
    importlib.reload(validator)

    client_ids = [f"verify-{secrets.token_hex(16)}" for _ in range(5)]
    rounds = []
    for _ in range(4):
        rounds.append([validator.rate_limit_check(client_id) for client_id in client_ids])

    assert rounds[:3] == [[True] * len(client_ids)] * 3
    assert rounds[3] == [False] * len(client_ids)

    fresh_client = f"verify-fresh-{secrets.token_hex(16)}"
    assert validator.rate_limit_check(fresh_client) is True


def test_test_results_log_exists_and_passed():
    """Verify that test_results.log exists and contains passing output."""
    log_path = '/home/user/test_results.log'
    assert os.path.exists(log_path), f"{log_path} does not exist."

    with open(log_path, 'r') as f:
        content = f.read()

    assert "test_models.py" in content, "test_results.log does not mention test_models.py."
    assert "passed" in content or "1 passed" in content, "test_results.log does not indicate a passed test."


def test_hypothesis_test_implemented():
    """Verify test_models.py contains the required hypothesis test and decorator."""
    test_file_path = '/home/user/dataproc/test_models.py'
    assert os.path.exists(test_file_path), f"{test_file_path} does not exist."

    with open(test_file_path, 'r') as f:
        content = f.read()

    assert "test_event_serialization_symmetry" in content, "test_event_serialization_symmetry not found in test_models.py."
    assert "@given" in content, "@given decorator not found in test_models.py."


def test_submitted_test_file_really_runs():
    """Run the exact required pytest target instead of trusting the saved log."""
    assert os.path.isfile(TEST_FILE), f"{TEST_FILE} is not a regular file."
    env = os.environ.copy()
    env['PYTHONPATH'] = DATAPROC + os.pathsep + env.get('PYTHONPATH', '')
    result = subprocess.run(
        [sys.executable, '-m', 'pytest', TEST_FILE],
        cwd=DATAPROC,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, result.stdout
    assert 'passed' in result.stdout, result.stdout


def test_submitted_property_test_is_effective():
    """Ensure the named test is a real Hypothesis test over varied Events and detects bad deserialization."""
    _add_dataproc_path()
    import models

    spec = importlib.util.spec_from_file_location('submitted_test_models_verifier', TEST_FILE)
    assert spec is not None and spec.loader is not None
    submitted = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(submitted)

    test_fn = getattr(submitted, 'test_event_serialization_symmetry', None)
    assert callable(test_fn), "test_event_serialization_symmetry is not callable"
    assert getattr(test_fn, 'is_hypothesis_test', False), "The required test is not decorated by Hypothesis @given"

    seen = set()
    invalid_generated_event = []
    original_to_json = models.Event.to_json

    def tracking_to_json(self):
        if not isinstance(self.name, str) or not isinstance(self.payload, dict):
            invalid_generated_event.append((self.name, self.payload))
        elif not all(isinstance(k, str) and isinstance(v, str) for k, v in self.payload.items()):
            invalid_generated_event.append((self.name, self.payload))
        else:
            seen.add((self.name, tuple(sorted(self.payload.items()))))
        return original_to_json(self)

    models.Event.to_json = tracking_to_json
    try:
        test_fn()
    finally:
        models.Event.to_json = original_to_json

    assert not invalid_generated_event, "The property test generated Events with invalid name or payload types"
    assert len(seen) >= 5, "The property test did not exercise varied randomly generated Events"

    original_from_json = models.Event.__dict__['from_json']
    models.Event.from_json = classmethod(lambda cls, data: object())
    try:
        with pytest.raises(AssertionError):
            test_fn()
    finally:
        models.Event.from_json = original_from_json


@given(
    name=st.text(),
    payload=st.dictionaries(st.text(), st.text(), max_size=20),
)
@settings(max_examples=80, deadline=None)
def test_event_serialization_behavior(name, payload):
    """Independently validate equality and JSON round trips on derived inputs."""
    _add_dataproc_path()
    from models import Event

    event = Event(name, payload)
    clone = Event.from_json(event.to_json())
    assert clone == event
    assert event == clone
    assert event == Event(name, dict(payload))
    assert event != Event(name + '\0', dict(payload))

    changed_payload = dict(payload)
    extra_key = '\0'
    while extra_key in changed_payload:
        extra_key += '\0'
    changed_payload[extra_key] = 'verifier-value'
    assert event != Event(name, changed_payload)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
