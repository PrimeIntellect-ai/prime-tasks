#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import ssl
import subprocess
import time
import urllib.request


def supervisorctl(conf_path, *args):
    return subprocess.run(
        ["supervisorctl", "-c", conf_path, *args],
        capture_output=True,
        text=True,
    )


def assert_services_running(status_output):
    for service in ["cert-generator", "dashboard-web"]:
        assert service in status_output, f"Service {service} not found in supervisorctl status."
        line = next(l for l in status_output.splitlines() if service in l)
        assert "RUNNING" in line, f"Service {service} is not RUNNING. Status line: {line}"


def assert_https_works():
    context = ssl._create_unverified_context()
    with urllib.request.urlopen(
        "https://localhost:8443/", context=context, timeout=3
    ) as response:
        assert 200 <= response.status < 400, f"HTTPS server returned status {response.status}"
        response.read(1)


def test_supervisord_services_running():
    conf_path = "/home/user/supervisord.conf"
    assert os.path.isfile(conf_path), f"supervisord.conf missing: {conf_path}"

    result = supervisorctl(conf_path, "status")
    assert result.returncode == 0, (
        "supervisorctl status failed. Is supervisord running? "
        f"Error: {result.stderr}"
    )

    status_output = result.stdout
    assert_services_running(status_output)

    assert os.path.isfile("/home/user/cert.pem"), "/home/user/cert.pem was not generated."
    assert os.path.isfile("/home/user/key.pem"), "/home/user/key.pem was not generated."
    assert_https_works()


def test_clean_supervisor_startup_waits_for_certificates():
    conf_path = "/home/user/supervisord.conf"

    shutdown = supervisorctl(conf_path, "shutdown")
    assert shutdown.returncode == 0, f"Could not shut down supervisord: {shutdown.stderr}"

    deadline = time.time() + 10
    while time.time() < deadline:
        if supervisorctl(conf_path, "status").returncode != 0:
            break
        time.sleep(0.2)
    else:
        raise AssertionError("Existing supervisord did not shut down")

    for path in ["/home/user/cert.pem", "/home/user/key.pem"]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    daemon = subprocess.Popen(
        ["supervisord", "-c", conf_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    last_status = ""
    deadline = time.time() + 45
    while time.time() < deadline:
        assert daemon.poll() is None, "supervisord exited during clean startup"
        result = supervisorctl(conf_path, "status")
        last_status = result.stdout + result.stderr
        if result.returncode == 0:
            try:
                assert_services_running(result.stdout)
                assert os.path.isfile("/home/user/cert.pem")
                assert os.path.isfile("/home/user/key.pem")
                assert_https_works()
                return
            except (AssertionError, OSError, urllib.error.URLError):
                pass
        time.sleep(0.5)

    raise AssertionError(
        "Services did not reach a working HTTPS state after a clean startup. "
        f"Last supervisor status: {last_status}"
    )


def test_analyze_link_fuzz():
    agent_script = "/home/user/analyze_link.py"
    oracle_script = "/tests/oracle_analyze_link.py"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing: {oracle_script}"

    random.seed(42)
    num_fuzz_inputs_N = 50

    for _ in range(num_fuzz_inputs_N):
        arg1 = random.randint(0, 299)
        arg2 = random.randint(0, 255)

        oracle_cmd = ["python3", oracle_script, str(arg1), str(arg2)]
        agent_cmd = ["python3", agent_script, str(arg1), str(arg2)]

        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

        assert oracle_res.returncode == 0, f"Oracle failed on args {arg1} {arg2}: {oracle_res.stderr}"
        assert agent_res.returncode == 0, f"Agent script failed on args {arg1} {arg2}: {agent_res.stderr}"

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on frame {arg1}, threshold {arg2}.\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
