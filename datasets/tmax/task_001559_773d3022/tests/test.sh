#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import io
import json
import os
import re
import secrets
import sqlite3
import subprocess
import sys
import unittest


def incident_metadata():
    dump_path = '/home/user/memory.dump'
    db_path = '/home/user/users.db'
    assert os.path.exists(dump_path), "Memory dump missing"
    assert os.path.exists(db_path), "Database file missing"

    with open(dump_path, 'rb') as f:
        dump = f.read()
    matches = re.findall(rb'FATAL_USER_ID=(\d+)', dump)
    assert matches, "FATAL_USER_ID not found in memory dump"
    user_id = int(matches[-1])
    assert user_id == 9942, "Unexpected fatal user ID in memory dump"

    conn = sqlite3.connect(db_path)
    try:
        row = conn.execute("SELECT metadata FROM users WHERE id = ?", (user_id,)).fetchone()
    finally:
        conn.close()
    assert row is not None, "User ID 9942 is missing from the database"
    return row[0]


def load_app():
    app_path = '/home/user/app.py'
    assert os.path.exists(app_path), "app.py is missing"
    sys.path.insert(0, '/home/user')
    sys.modules.pop('app', None)
    try:
        import app
    except Exception as e:
        assert False, f"Failed to import app.py: {e}"
    assert hasattr(app, 'validate_user_data'), "validate_user_data function is missing from app.py"
    return app


def test_app_logic_fixed():
    app = load_app()

    try:
        result = app.validate_user_data('{"status": "active", "points": 150}')
        assert result is True, "validate_user_data should return True for valid data"
    except Exception as e:
        assert False, f"validate_user_data raised an exception for valid data: {e}"

    try:
        app.validate_user_data('{"status": "active", "points": -50}')
        assert False, "validate_user_data did not raise ValueError for negative points"
    except ValueError as e:
        assert str(e) == "Invalid data", "Negative points must raise ValueError('Invalid data')"
    except Exception as e:
        assert False, f"validate_user_data raised unexpected exception for negative points: {type(e).__name__}"

    # Exercise unpredictable JSON documents so fixed-input special casing cannot pass.
    for _ in range(12):
        points = -1 - secrets.randbelow(10**9)
        data = {
            "nonce": secrets.token_hex(12),
            "points": points,
            "status": secrets.choice(["active", "inactive", "pending"]),
            "extra": {"value": secrets.randbelow(10**6)},
        }
        metadata = json.dumps(data, separators=secrets.choice([(',', ':'), (', ', ': ')]), sort_keys=bool(secrets.randbits(1)))
        try:
            app.validate_user_data(metadata)
            assert False, f"validate_user_data accepted negative points value {points}"
        except ValueError as e:
            assert str(e) == "Invalid data", "Negative points must raise ValueError('Invalid data')"

    for _ in range(8):
        points = secrets.randbelow(10**9)
        metadata = json.dumps({
            "nonce": secrets.token_hex(12),
            "status": "active",
            "points": points,
        }, sort_keys=bool(secrets.randbits(1)))
        assert app.validate_user_data(metadata) is True, "Non-negative points should return True"


def test_regression_test_file():
    test_file = '/home/user/test_regression.py'
    assert os.path.exists(test_file), "Regression test file missing"

    with open(test_file, 'r') as f:
        content = f.read()

    metadata_str = incident_metadata()
    assert metadata_str.replace(" ", "") in content.replace(" ", ""), "test_regression.py does not use the extracted metadata string"
    assert "ValueError" in content, "test_regression.py does not assert ValueError"
    assert "unittest" in content, "test_regression.py does not use the unittest framework"
    assert "TestUserValidation" in content, "test_regression.py is missing the TestUserValidation class"
    assert "test_negative_points_raises_error" in content, "test_regression.py is missing the test_negative_points_raises_error method"

    # Load and directly exercise the required test with a spy. This proves that the
    # named unittest method actually calls validate_user_data with the DB metadata
    # and expects the ValueError, rather than merely containing matching strings.
    app = load_app()
    spec = importlib.util.spec_from_file_location('submitted_regression', test_file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    cls = getattr(module, 'TestUserValidation', None)
    assert isinstance(cls, type) and issubclass(cls, unittest.TestCase), "TestUserValidation must be a unittest.TestCase"
    assert hasattr(cls, 'test_negative_points_raises_error'), "Required regression test method missing"

    calls = []
    def spy(value):
        calls.append(value)
        raise ValueError("Invalid data")

    old_app_fn = app.validate_user_data
    had_module_fn = hasattr(module, 'validate_user_data')
    old_module_fn = getattr(module, 'validate_user_data', None)
    app.validate_user_data = spy
    module.validate_user_data = spy
    try:
        suite = unittest.TestSuite([cls('test_negative_points_raises_error')])
        result = unittest.TextTestRunner(stream=io.StringIO(), verbosity=2).run(suite)
    finally:
        app.validate_user_data = old_app_fn
        if had_module_fn:
            module.validate_user_data = old_module_fn
        else:
            delattr(module, 'validate_user_data')

    assert result.wasSuccessful(), "Required regression test does not successfully assert the ValueError"
    assert calls == [metadata_str], "Regression test must call validate_user_data with the exact metadata retrieved from the database"

    # Actually run the submitted suite and create the requested log from its real output.
    log_file = '/home/user/test_result.log'
    with open(log_file, 'w') as log:
        completed = subprocess.run(
            [sys.executable, '-m', 'unittest', test_file],
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=20,
            cwd='/home/user',
        )
    assert completed.returncode == 0, "Submitted regression test suite failed"


def test_test_result_log():
    log_file = '/home/user/test_result.log'
    assert os.path.exists(log_file), "Test result log missing"

    with open(log_file, 'r') as f:
        content = f.read()

    assert "OK" in content, "Regression test log does not indicate success ('OK' not found)"
    assert "FAILED" not in content, "Regression test log indicates failure ('FAILED' found)"
    assert "Ran 1 test" in content or "Ran" in content, "Regression test log does not appear to be valid unittest output"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
