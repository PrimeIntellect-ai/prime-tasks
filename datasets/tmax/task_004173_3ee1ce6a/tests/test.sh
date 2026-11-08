#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import socket
import stat
import subprocess
import threading
import uuid

import pytest

PIPELINE = '/home/user/pipeline.sh'
MIGRATOR = '/home/user/migrate_config.py'
CHECKER = '/home/user/check_endpoints.py'
INI = '/home/user/legacy/app.conf'
CONFIG = '/home/user/cloud/config.json'
LOG = '/home/user/deploy_success.log'


@pytest.fixture(scope="session", autouse=True)
def run_pipeline():
    """Run the pipeline before tests to ensure the normal state is generated."""
    if os.path.isfile(PIPELINE):
        st = os.stat(PIPELINE)
        if not bool(st.st_mode & stat.S_IXUSR):
            os.chmod(PIPELINE, st.st_mode | stat.S_IXUSR)
        subprocess.run([PIPELINE], capture_output=True, text=True)


def run(path):
    return subprocess.run([path], capture_output=True, text=True, timeout=15)


def test_scripts_exist_and_executable():
    """Test that all required scripts exist and have executable permissions."""
    for script in (MIGRATOR, CHECKER, PIPELINE):
        assert os.path.isfile(script), f"Script {script} is missing."
        st = os.stat(script)
        assert bool(st.st_mode & stat.S_IXUSR), f"Script {script} is not executable."


def test_pipeline_execution_success():
    """Test that pipeline.sh executes successfully."""
    result = run(PIPELINE)
    assert result.returncode == 0, (
        f"pipeline.sh failed with exit code {result.returncode}. Stderr: {result.stderr}"
    )


def test_config_json_content():
    """Test that config.json contains the correct structure and values."""
    assert os.path.isfile(CONFIG), f"{CONFIG} does not exist."
    with open(CONFIG, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{CONFIG} does not contain valid JSON.")

    assert data.get('cloud_region') == 'us-east-1', "cloud_region is incorrect or missing."

    db = data.get('database', {})
    assert db.get('host') == 'localhost', "database host is incorrect."
    assert db.get('port') in (33060, "33060"), "database port is incorrect."
    assert int(db.get('port')) == 33060, "database port should be 33060."
    assert db.get('user') == 'admin', "database user is incorrect."

    cache = data.get('cache', {})
    assert cache.get('host') == 'localhost', "cache host is incorrect."
    assert cache.get('port') in (63790, "63790"), "cache port is incorrect."
    assert int(cache.get('port')) == 63790, "cache port should be 63790."


def test_migrate_config_idempotency():
    """Test that migrate_config.py is idempotent."""
    result = run(MIGRATOR)
    assert result.returncode == 0, (
        f"migrate_config.py failed on subsequent run. Stderr: {result.stderr}"
    )
    test_config_json_content()


def test_migration_reads_current_ini_and_is_byte_idempotent():
    """Change the INI user and require migration to derive the new output from it."""
    with open(INI, 'rb') as f:
        original_ini = f.read()
    dynamic_user = 'audit_' + uuid.uuid4().hex
    changed_ini = f"""[database]
host = db.local
port = 3306
user = {dynamic_user}

[cache]
host = redis.local
port = 6379
"""
    try:
        with open(INI, 'w') as f:
            f.write(changed_ini)
        if os.path.exists(CONFIG):
            os.remove(CONFIG)

        first = run(MIGRATOR)
        assert first.returncode == 0, first.stderr
        with open(CONFIG, 'r') as f:
            data = json.load(f)
        assert data.get('cloud_region') == 'us-east-1'
        assert data.get('database', {}).get('host') == 'localhost'
        assert int(data.get('database', {}).get('port')) == 33060
        assert data.get('database', {}).get('user') == dynamic_user
        assert data.get('cache', {}).get('host') == 'localhost'
        assert int(data.get('cache', {}).get('port')) == 63790

        with open(CONFIG, 'rb') as f:
            first_bytes = f.read()
        second = run(MIGRATOR)
        assert second.returncode == 0, second.stderr
        with open(CONFIG, 'rb') as f:
            assert f.read() == first_bytes, "Repeated migration changed config.json bytes."
    finally:
        with open(INI, 'wb') as f:
            f.write(original_ini)
        run(MIGRATOR)


def test_check_endpoints_execution():
    """Test that check_endpoints.py executes successfully and exits with 0."""
    result = run(CHECKER)
    assert result.returncode == 0, (
        f"check_endpoints.py failed with exit code {result.returncode}. Stderr: {result.stderr}"
    )


def make_probe_listener():
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(('127.0.0.1', 0))
    listener.listen(2)
    listener.settimeout(10)
    accepted = threading.Event()

    def accept_one():
        try:
            connection, _ = listener.accept()
            connection.close()
            accepted.set()
        finally:
            listener.close()

    threading.Thread(target=accept_one, daemon=True).start()
    return listener.getsockname()[1], accepted


def test_checker_connects_to_endpoints_from_json_and_reports_failure():
    """Use unpredictable ports to prove the checker reads JSON and opens both sockets."""
    db_port, db_accepted = make_probe_listener()
    cache_port, cache_accepted = make_probe_listener()
    probe_config = {
        'cloud_region': 'us-east-1',
        'database': {'host': '127.0.0.1', 'port': db_port, 'user': 'probe'},
        'cache': {'host': '127.0.0.1', 'port': cache_port},
    }
    try:
        os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
        with open(CONFIG, 'w') as f:
            json.dump(probe_config, f)
        result = run(CHECKER)
        assert result.returncode == 0, result.stderr
        assert db_accepted.wait(2), "No TCP connection reached the configured database endpoint."
        assert cache_accepted.wait(2), "No TCP connection reached the configured cache endpoint."

        probe_config['database']['port'] = 1
        probe_config['cache']['port'] = 1
        with open(CONFIG, 'w') as f:
            json.dump(probe_config, f)
        result = run(CHECKER)
        assert result.returncode == 1, "Checker did not fail when configured endpoints were unreachable."
        assert (result.stdout + result.stderr).strip(), "Checker did not print an error on failure."
    finally:
        run(MIGRATOR)


def test_pipeline_stops_when_migration_fails():
    """The pipeline must execute the migrator and must not create the success log on failure."""
    with open(MIGRATOR, 'rb') as f:
        original = f.read()
    mode = stat.S_IMODE(os.stat(MIGRATOR).st_mode)
    try:
        with open(MIGRATOR, 'wb') as f:
            f.write(b'#!/bin/sh\nexit 23\n')
        os.chmod(MIGRATOR, mode | stat.S_IXUSR)
        if os.path.exists(LOG):
            os.remove(LOG)
        result = run(PIPELINE)
        assert result.returncode != 0, "Pipeline ignored a failed migration step."
        assert not os.path.exists(LOG), "Pipeline created the success log after migration failed."
    finally:
        with open(MIGRATOR, 'wb') as f:
            f.write(original)
        os.chmod(MIGRATOR, mode)
        run(PIPELINE)


def test_pipeline_stops_when_connectivity_check_fails():
    """The pipeline must execute the checker and suppress success on checker failure."""
    with open(CHECKER, 'rb') as f:
        original = f.read()
    mode = stat.S_IMODE(os.stat(CHECKER).st_mode)
    try:
        with open(CHECKER, 'wb') as f:
            f.write(b'#!/bin/sh\necho endpoint failure >&2\nexit 19\n')
        os.chmod(CHECKER, mode | stat.S_IXUSR)
        if os.path.exists(LOG):
            os.remove(LOG)
        result = run(PIPELINE)
        assert result.returncode != 0, "Pipeline ignored a failed connectivity check."
        assert not os.path.exists(LOG), "Pipeline created the success log after connectivity failed."
    finally:
        with open(CHECKER, 'wb') as f:
            f.write(original)
        os.chmod(CHECKER, mode)
        run(PIPELINE)


def test_deploy_success_log():
    """Test that the deployment success log contains the expected string."""
    result = run(PIPELINE)
    assert result.returncode == 0, result.stderr
    assert os.path.isfile(LOG), f"{LOG} does not exist. Pipeline may have failed."
    with open(LOG, 'r') as f:
        content = f.read().strip()
    assert content == "DEPLOYMENT_READY", (
        f"Expected 'DEPLOYMENT_READY' in {LOG}, got '{content}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
