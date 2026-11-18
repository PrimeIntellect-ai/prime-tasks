#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import time
import urllib.request

import pytest
import yaml

COMPOSE_FILE = "/home/user/backend/docker-compose.yml"
RESULTS_FILE = "/home/user/bench_results.json"
EXPECTED_PORTS = {"app1": 8001, "app2": 8002, "app3": 8003}


def user_systemctl(*args):
    env = os.environ.copy()
    if "XDG_RUNTIME_DIR" not in env:
        env["XDG_RUNTIME_DIR"] = f"/run/user/{os.getuid()}"
    return subprocess.run(
        ["systemctl", "--user", *args],
        capture_output=True,
        text=True,
        env=env,
    )


def fetch(url, attempts=10):
    last_error = None
    for _ in range(attempts):
        try:
            with urllib.request.urlopen(url, timeout=3) as response:
                assert response.status == 200
                return response.read().decode("utf-8", errors="replace")
        except Exception as exc:
            last_error = exc
            time.sleep(0.25)
    pytest.fail(f"Unable to fetch {url}: {last_error}")


def hostname_from_whoami(body):
    match = re.search(r"^Hostname:\s*(\S+)\s*$", body, re.MULTILINE)
    assert match, f"Response was not a traefik/whoami response: {body[:300]!r}"
    return match.group(1)


def has_port_mapping(entries, expected_host):
    for entry in entries or []:
        if isinstance(entry, str):
            value = entry.split("/")[0]
            parts = value.split(":")
            if len(parts) >= 2 and parts[-2] == str(expected_host) and parts[-1] == "80":
                return True
        elif isinstance(entry, dict):
            target = str(entry.get("target", "")).split("/")[0]
            published = str(entry.get("published", "")).split("/")[0]
            if target == "80" and published == str(expected_host):
                return True
    return False


def test_compose_configuration_and_running_backends():
    assert os.path.isfile(COMPOSE_FILE), f"Missing {COMPOSE_FILE}"
    with open(COMPOSE_FILE, "r") as handle:
        compose = yaml.safe_load(handle)

    services = (compose or {}).get("services", {})
    for service, host_port in EXPECTED_PORTS.items():
        assert service in services, f"Compose service {service} is missing"
        assert has_port_mapping(services[service].get("ports"), host_port), (
            f"{service} must publish container port 80 on host port {host_port}"
        )

        listed = subprocess.run(
            ["docker", "ps", "-q", "--filter", f"label=com.docker.compose.service={service}"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.split()
        assert len(listed) == 1, f"Expected exactly one running compose container for {service}, got {len(listed)}"

        inspected = json.loads(subprocess.run(
            ["docker", "inspect", listed[0]],
            capture_output=True,
            text=True,
            check=True,
        ).stdout)[0]
        assert inspected["State"]["Running"], f"Container for {service} is not running"
        bindings = inspected["NetworkSettings"]["Ports"].get("80/tcp") or []
        assert any(int(binding["HostPort"]) == host_port for binding in bindings), (
            f"Running {service} container does not publish 80/tcp on {host_port}"
        )


def test_systemd_service_active():
    """Verify that the systemd user service is running."""
    result = user_systemctl("is-active", "local-proxy.service")
    status = result.stdout.strip()
    assert result.returncode == 0, f"local-proxy.service is not active. Current status: '{status}'"

    pid_result = user_systemctl("show", "local-proxy.service", "--property=MainPID", "--value")
    assert pid_result.returncode == 0, pid_result.stderr
    main_pid = int(pid_result.stdout.strip())
    assert main_pid > 0, "local-proxy.service has no running main process"
    executable = os.path.realpath(f"/proc/{main_pid}/exe")
    assert os.path.basename(executable).startswith("nginx"), (
        f"local-proxy.service is not managing Nginx; MainPID executable is {executable}"
    )

    syntax = subprocess.run(
        ["/usr/sbin/nginx", "-t", "-c", "/home/user/proxy/nginx.conf"],
        capture_output=True,
        text=True,
    )
    assert syntax.returncode == 0, f"nginx.conf is invalid: {syntax.stderr}"


def test_live_proxy_reaches_all_three_backends():
    direct_hostnames = {
        hostname_from_whoami(fetch(f"http://127.0.0.1:{port}/"))
        for port in EXPECTED_PORTS.values()
    }
    assert len(direct_hostnames) == 3, "The three published ports do not reach three distinct backends"

    proxy_hostnames = set()
    for _ in range(30):
        proxy_hostnames.add(hostname_from_whoami(fetch("http://127.0.0.1:8080/", attempts=2)))
        if proxy_hostnames == direct_hostnames:
            break
    assert proxy_hostnames == direct_hostnames, (
        f"Proxy reached backends {proxy_hostnames}, expected all of {direct_hostnames}"
    )


def test_benchmark_results_metric():
    """Verify the benchmark results meet the required metric threshold."""
    assert os.path.exists(RESULTS_FILE), f"Output file {RESULTS_FILE} not found. Ensure you saved the benchmark output."

    try:
        with open(RESULTS_FILE, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {RESULTS_FILE} does not contain valid JSON.")

    unique_backends = data.get("unique_backends", 0)
    errors = data.get("errors", -1)
    rps = data.get("rps", 0.0)

    assert unique_backends == 3, f"Expected traffic to be distributed across 3 unique backends, but got {unique_backends}."
    assert errors == 0, f"Expected 0 errors during benchmark, but got {errors}."

    metric = float(rps)
    threshold = 100.0
    assert metric >= threshold, f"Benchmark RPS {metric} is below the required threshold of {threshold}."


def test_live_benchmark_metric():
    result = subprocess.run(
        ["/app/lb_bench"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"/app/lb_bench failed: {result.stderr}"
    output = result.stdout.strip()
    assert output, "/app/lb_bench produced no JSON output"
    try:
        live = json.loads(output)
    except json.JSONDecodeError as exc:
        pytest.fail(f"/app/lb_bench did not produce valid JSON: {exc}: {output!r}")

    assert live.get("unique_backends") == 3, (
        f"Live benchmark saw {live.get('unique_backends')} unique backends instead of 3"
    )
    assert live.get("errors") == 0, f"Live benchmark reported {live.get('errors')} errors"
    assert float(live.get("rps", 0.0)) >= 100.0, (
        f"Live benchmark RPS {live.get('rps')} is below 100"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
