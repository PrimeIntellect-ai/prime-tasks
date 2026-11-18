#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import subprocess
import textwrap

import pytest


def run_as_user(args, timeout=30, cwd="/home/user"):
    return subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "PYTHONPATH=/home/user"] + args,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def test_bug_fixed():
    """Test that the deliberate performance perturbation is removed."""
    consumer_path = "/app/huey-src/huey/consumer.py"
    assert os.path.isfile(consumer_path), f"{consumer_path} is missing."
    with open(consumer_path, "r") as f:
        content = f.read()
    assert "time.sleep(0.1)" not in content, "The deliberate performance perturbation 'time.sleep(0.1)' is still present in consumer.py."


def test_fixed_package_is_installed():
    """The importable Huey consumer must be the repaired vendored source."""
    code = textwrap.dedent(r'''
        import json
        import os
        import huey
        import huey.consumer

        installed = os.path.realpath(huey.consumer.__file__)
        if installed.endswith('.pyc'):
            installed = installed[:-1]
        with open(installed, 'rb') as f:
            installed_content = f.read()
        with open('/app/huey-src/huey/consumer.py', 'rb') as f:
            vendored_content = f.read()
        print(json.dumps({
            'version': getattr(huey, '__version__', None),
            'installed': installed,
            'same_source': installed_content == vendored_content,
            'has_perturbation': b'time.sleep(0.1)' in installed_content,
        }))
    ''')
    result = run_as_user(["python3", "-c", code])
    assert result.returncode == 0, result.stderr
    info = json.loads(result.stdout.strip().splitlines()[-1])
    assert info["version"] == "2.4.4", f"Wrong Huey version installed: {info['version']}"
    assert not info["has_perturbation"], "The installed Huey package still contains the perturbation."
    assert info["same_source"], "The repaired vendored consumer.py is not the version installed in Python."


def test_app_py_exists():
    """Test that app.py is created and contains expected definitions."""
    app_path = "/home/user/app.py"
    assert os.path.isfile(app_path), f"{app_path} is missing."
    with open(app_path, "r") as f:
        content = f.read()
    assert "SqliteHuey" in content, "SqliteHuey is not used in app.py."
    assert "process_data" in content, "process_data task is not defined in app.py."
    assert "huey.db" in content, "huey.db is not referenced in app.py."


def test_application_behavior():
    """Import the application and exercise the real task implementation locally."""
    code = textwrap.dedent(r'''
        import hashlib
        import json
        import os
        from huey import SqliteHuey
        import app

        assert isinstance(app.huey, SqliteHuey)
        filename = getattr(app.huey.storage, 'filename', None)
        assert filename is not None
        assert os.path.realpath(filename) == '/home/user/huey.db', filename
        assert hasattr(app.process_data, 'call_local')

        answers = {}
        for n in (-17, 0, 42, 987654321):
            value = str(n)
            for _ in range(100):
                value = hashlib.sha256(value.encode()).hexdigest()
            actual = app.process_data.call_local(n)
            assert actual == value, (n, actual, value)
            answers[str(n)] = actual
        print(json.dumps(answers))
    ''')
    result = run_as_user(["python3", "-c", code])
    assert result.returncode == 0, f"app.py failed behavioral validation:\n{result.stdout}\n{result.stderr}"


def test_systemd_service_file():
    """Test that the systemd service file is created with correct configurations."""
    service_path = "/home/user/.config/systemd/user/huey-worker.service"
    assert os.path.isfile(service_path), f"Systemd service file {service_path} is missing."
    with open(service_path, "r") as f:
        content = f.read()
    assert "huey_consumer.py" in content, "huey_consumer.py is not executed in the service file."
    assert "app.huey" in content, "app.huey is not targeted in the service file."
    assert "Restart=always" in content, "Restart policy is not set to always."
    assert "RestartSec=3" in content or "RestartSec=3s" in content, "Restart delay is not set to 3 seconds."
    assert re.search(r'(-w\s*4|--workers\s*=?\s*4)', content), "Worker count is not set to 4."


def test_systemd_service_active():
    """Test that the systemd service is active, running, and enabled."""
    try:
        result = subprocess.run(
            ["systemctl", "--user", "is-active", "huey-worker.service"],
            capture_output=True,
            text=True,
        )
        assert result.stdout.strip() == "active", f"huey-worker.service is not active. Output: {result.stdout.strip()}"
        enabled = subprocess.run(
            ["systemctl", "--user", "is-enabled", "huey-worker.service"],
            capture_output=True,
            text=True,
        )
        assert enabled.stdout.strip() == "enabled", f"huey-worker.service is not enabled. Output: {enabled.stdout.strip()}"
    except Exception as e:
        pytest.fail(f"Failed to check systemd service status: {e}")


def test_benchmark_result():
    """Test that the requested benchmark output is present and meets the threshold."""
    result_path = "/home/user/benchmark_result.txt"
    assert os.path.isfile(result_path), f"{result_path} is missing."
    with open(result_path, "r") as f:
        content = f.read()
    match = re.search(r"Total time:\s*([0-9.]+)\s*seconds", content)
    if match:
        processing_time = float(match.group(1))
        assert processing_time <= 4.0, f"Processing time {processing_time} exceeded 4.0 seconds threshold."
    else:
        raise AssertionError(f"Could not find 'Total time:' metric in {result_path}")


def test_real_consumer_throughput_and_results():
    """Queue independently-derived work and require the supervised consumer to finish it."""
    code = textwrap.dedent(r'''
        import hashlib
        import json
        import time
        from app import huey, process_data

        huey.storage.flush_queue()
        huey.storage.flush_results()
        started = time.monotonic()
        pending = [process_data(i) for i in range(5000)]
        values = [result.get(blocking=True, timeout=20) for result in pending]
        elapsed = time.monotonic() - started

        for i, actual in enumerate(values):
            expected = str(i)
            for _ in range(100):
                expected = hashlib.sha256(expected.encode()).hexdigest()
            assert actual == expected, (i, actual, expected)
        print(json.dumps({'elapsed': elapsed, 'count': len(values)}))
    ''')
    result = run_as_user(["python3", "-c", code], timeout=30)
    assert result.returncode == 0, f"The consumer did not correctly process queued tasks:\n{result.stdout}\n{result.stderr}"
    metrics = json.loads(result.stdout.strip().splitlines()[-1])
    assert metrics["count"] == 5000
    assert metrics["elapsed"] <= 4.0, f"Independent processing time {metrics['elapsed']:.3f} exceeded 4.0 seconds."


def test_execute_provided_benchmark():
    """Actually execute the supplied benchmark and redirect its stdout as instructed."""
    command = "cd /home/user && python3 /app/benchmark.py > /home/user/benchmark_result.txt"
    result = run_as_user(["bash", "-c", command], timeout=30)
    assert result.returncode == 0, f"/app/benchmark.py failed:\n{result.stdout}\n{result.stderr}"

    with open("/home/user/benchmark_result.txt", "r") as f:
        content = f.read()
    match = re.search(r"Total time:\s*([0-9.]+)\s*seconds", content)
    assert match, "The executed benchmark did not emit a Total time metric."
    processing_time = float(match.group(1))
    assert processing_time <= 4.0, f"Executed benchmark time {processing_time} exceeded 4.0 seconds."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
