#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import subprocess
import time
import urllib.error
import urllib.request
from urllib.parse import urlparse

import psycopg2
import pytest

AGENT_SCRIPT = "/home/user/compute_stats.sh"
ORACLE_SCRIPT = "/tests/oracle_stats"


def read_database_url():
    env_path = "/app/.env"
    assert os.path.isfile(env_path), f"Configuration file {env_path} is missing."
    values = {}
    with open(env_path, encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    return values.get("DATABASE_URL")


@pytest.fixture(scope="session", autouse=True)
def start_declared_services():
    subprocess.run(["service", "postgresql", "start"], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.run(["fuser", "-k", "8080/tcp"], check=False,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    env = os.environ.copy()
    database_url = read_database_url()
    if database_url is not None:
        env["DATABASE_URL"] = database_url
    else:
        env.pop("DATABASE_URL", None)

    api_proc = subprocess.Popen(
        ["python3", "/app/app.py"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )

    deadline = time.time() + 10
    while time.time() < deadline:
        if api_proc.poll() is not None:
            stdout, stderr = api_proc.communicate()
            pytest.fail(
                f"The configured data-api exited before serving requests. "
                f"stdout={stdout!r}, stderr={stderr!r}"
            )
        try:
            urllib.request.urlopen("http://localhost:8080/health", timeout=0.5)
            break
        except urllib.error.HTTPError:
            # An HTTP response proves the configured Flask process is listening;
            # the health assertion below still requires status 200.
            break
        except Exception:
            time.sleep(0.1)
    else:
        api_proc.terminate()
        pytest.fail("The configured data-api did not start listening on port 8080.")

    yield

    api_proc.terminate()
    try:
        api_proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        api_proc.kill()
        api_proc.wait()


def test_database_configuration_and_connectivity():
    """Verify the configured URL targets the db service and reaches PostgreSQL."""
    database_url = read_database_url()
    assert database_url, "DATABASE_URL is missing from /app/.env."

    parsed = urlparse(database_url)
    assert parsed.scheme in ("postgres", "postgresql")
    assert parsed.username == "postgres"
    assert parsed.password == "secret"
    assert parsed.hostname == "db", "The data-api must use the Compose service name 'db'."
    assert parsed.port == 5432
    assert parsed.path.lstrip("/") == "postgres"

    with psycopg2.connect(database_url, connect_timeout=5) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            assert cursor.fetchone() == (1,)


def test_api_health_check():
    """Check if the API can connect to the database."""
    url = "http://localhost:8080/health"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected 200 OK, got {response.status}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to {url} or API health check failed: {e}")
    except Exception as e:
        pytest.fail(f"Unexpected error when checking {url}: {e}")


def run_agent(csv_bytes):
    user = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    return subprocess.run(
        [AGENT_SCRIPT],
        input=csv_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=2,
        preexec_fn=demote,
    )


def test_compute_stats_fuzz_equivalence():
    """Fuzz equivalence test for compute_stats.sh against oracle_stats."""
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is missing."
    assert not os.path.islink(AGENT_SCRIPT), "compute_stats.sh must be a real Bash script."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."
    with open(AGENT_SCRIPT, "rb") as handle:
        first_line = handle.readline().strip()
    assert first_line in (b"#!/bin/bash", b"#!/usr/bin/bash", b"#!/usr/bin/env bash"), \
        "compute_stats.sh must be a Bash script with a Bash shebang."

    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script {ORACLE_SCRIPT} is missing."
    assert os.access(ORACLE_SCRIPT, os.X_OK), f"Oracle script {ORACLE_SCRIPT} is not executable."

    # The oracle is available only to the root verifier. Agent code is executed
    # as the unprivileged task user and therefore cannot delegate to it.
    os.chown(ORACLE_SCRIPT, 0, 0)
    os.chmod(ORACLE_SCRIPT, 0o700)

    random.seed(42)
    for i in range(500):
        num_lines = random.randint(0, 50)
        csv_lines = ["id,val1,val2"]
        for _ in range(num_lines):
            id_val = random.randint(1, 100)
            val1 = random.uniform(-1000.0, 1000.0)
            val2 = random.uniform(-1000.0, 1000.0)
            csv_lines.append(f"{id_val},{val1:.5f},{val2:.5f}")

        csv_data = "\n".join(csv_lines) + "\n"
        csv_bytes = csv_data.encode("utf-8")

        try:
            agent_proc = run_agent(csv_bytes)
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on fuzz iteration {i}.")

        try:
            oracle_proc = subprocess.run(
                [ORACLE_SCRIPT], input=csv_bytes, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=2
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle script timed out on fuzz iteration {i}.")

        assert agent_proc.returncode == 0, (
            f"Agent script exited with {agent_proc.returncode} on fuzz iteration {i}. "
            f"stderr: {agent_proc.stderr!r}"
        )
        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Mismatch on fuzz iteration {i}.\nInput:\n{csv_data}\n"
            f"Oracle output: {oracle_proc.stdout!r}\n"
            f"Agent output: {agent_proc.stdout!r}\n"
            f"Agent stderr: {agent_proc.stderr!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
