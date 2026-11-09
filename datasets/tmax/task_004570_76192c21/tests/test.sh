#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import socket
import string
import subprocess
import tempfile
import urllib.error
import urllib.request

import pytest

STACK = "/home/user/monitoring_stack"
SCRIPT = "/home/user/sanitize_logs.sh"


def fetch(port, path):
    url = f"http://127.0.0.1:{port}{path}"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to {url}: {exc}")
    except json.JSONDecodeError:
        pytest.fail(f"Non-JSON response from {url}")


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        if int(fields[1].split(":")[1], 16) == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as handle:
            return handle.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def all_cmdlines():
    result = []
    for entry in os.listdir("/proc"):
        if entry.isdigit():
            command = cmdline(int(entry))
            if command:
                result.append(command)
    return result


def assert_listener(port, predicate, description):
    pids = listening_pids(port)
    assert pids, f"Nothing is listening on port {port}"
    commands = [cmdline(pid) for pid in pids]
    assert any(predicate(command) for command in commands), (
        f"Port {port} is not owned by {description}; listeners were {commands}"
    )


def test_monitoring_stack_tunnel():
    nginx_conf = os.path.join(STACK, "nginx.conf")
    env_file = os.path.join(STACK, "api", ".env")
    assert os.path.isfile(nginx_conf)
    assert os.path.isfile(env_file)

    with open(nginx_conf) as handle:
        nginx_text = re.sub(r"#.*", "", handle.read())
    assert re.search(r"\blisten\s+8080\s*;", nginx_text)
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:5000\s*;", nginx_text)

    with open(env_file) as handle:
        env_text = handle.read()
    assert re.search(r"(?m)^\s*REDIS_URL\s*=\s*redis://127\.0\.0\.1:6379(?:/0)?\s*$", env_text)

    assert_listener(6379, lambda c: "redis-server" in c, "redis-server")
    assert_listener(5000, lambda c: "python" in c and os.path.join(STACK, "api", "app.py") in c,
                    "the supplied Flask application")
    assert_listener(8080, lambda c: "nginx" in c, "nginx")
    assert_listener(9000, lambda c: re.search(r"(^|\s)ssh(\s|$)", c) is not None,
                    "an SSH client")

    commands = all_cmdlines()
    assert any("redis-server" in c and os.path.join(STACK, "redis.conf") in c for c in commands), \
        "Redis was not started with the supplied redis.conf"
    assert any("nginx" in c and "-c" in c and nginx_conf in c for c in commands), \
        "Nginx was not started with the supplied nginx.conf"

    tunnel_commands = [cmdline(pid) for pid in listening_pids(9000)]
    assert any(
        re.search(r"(^|\s)-L(?:\s+)?(?:127\.0\.0\.1:)?9000:(?:localhost|127\.0\.0\.1):8080(\s|$)", c)
        and re.search(r"user@(?:localhost|127\.0\.0\.1)", c)
        for c in tunnel_commands
    ), f"Port 9000 is not the required SSH local forward: {tunnel_commands}"

    status, health = fetch(5000, "/api/health")
    assert status == 200
    assert health.get("status") == "ok"
    assert health.get("redis") == "connected"

    for port in (8080, 9000):
        status, health = fetch(port, "/api/health")
        assert status == 200
        assert health.get("status") == "ok"
        assert health.get("redis") == "connected"

        status, metrics = fetch(port, "/api/metrics")
        assert status == 200
        assert metrics.get("metrics") == "sample"


def test_log_sanitization_script_executable():
    assert os.path.isfile(SCRIPT), f"Script not found at {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable"
    with open(SCRIPT, "rb") as handle:
        first_line = handle.readline().decode("utf-8", "replace")
    assert first_line.startswith("#!") and "bash" in first_line, "sanitize_logs.sh must be a Bash script"
    subprocess.run(["bash", "-n", SCRIPT], check=True)


def make_line(ip, timestamp, method, target, status, agent):
    return (f'{ip} - - [{timestamp}] "{method} {target} HTTP/1.1" '
            f'{status} 42 "-" "{agent}"\n')


def run_filter(path):
    return subprocess.run([SCRIPT, path], capture_output=True, text=True, timeout=5)


def test_log_sanitization_adversarial_generated_corpus():
    rng = random.SystemRandom()
    token = "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(18))
    second = rng.randrange(10, 55)
    timestamp = f"{rng.randrange(1, 28):02d}/Nov/2024:09:{rng.randrange(10, 50):02d}:{second:02d} +0000"
    ips = [f"10.{rng.randrange(1, 240)}.{rng.randrange(1, 240)}.{rng.randrange(1, 240)}" for _ in range(16)]

    clean = [
        make_line(ips[0], timestamp, "GET", "/api/health", "200", f"Prometheus/2.{rng.randrange(31, 60)}"),
        make_line(ips[1], timestamp, "GET", "/api/metrics", "200", "Datadog Agent"),
        make_line(ips[2], timestamp, "GET", "/api/health", "200", f"CustomMonitor/{rng.randrange(1, 10)}.0"),
        make_line(ips[3], timestamp, "GET", "/api/metrics", "200", f"Prometheus/3.{rng.randrange(0, 9)}"),
    ]
    evil = [
        make_line(ips[4], timestamp, "POST", "/api/health", "405", "Nmap Scripting Engine"),
        make_line(ips[5], timestamp, "PUT", "/api/metrics", "405", "Datadog Agent"),
        make_line(ips[6], timestamp, "DELETE", "/api/health", "200", "Prometheus/2.50"),
        make_line(ips[7], timestamp, "GET", f"/api/health?id={rng.randrange(2, 99)}%27%20OR%201=1--{token}", "200", "curl/8.0"),
        make_line(ips[8], timestamp, "GET", f"/api/metrics?q=<ScRiPt>{token}</ScRiPt>", "200", "Prometheus/2.50"),
        make_line(ips[9], timestamp, "GET", f"/api/health/../../etc/{token}", "400", "Mozilla/5.0"),
        make_line(ips[10], timestamp, "GET", f"/api/metrics/%2e%2e/%2e%2e/{token}", "200", "Datadog Agent"),
        make_line(ips[11], timestamp, "GET", "/api/health", "500", "Prometheus/2.50"),
        make_line(ips[12], timestamp, "GET", f"/api/{token}", "200", "Prometheus/2.50"),
        make_line(ips[13], timestamp, "GET", "/api/health", "200", f"sqlmap/{token}"),
        f"{token} malformed request without an HTTP access-log structure\n",
    ]

    rng.shuffle(clean)
    rng.shuffle(evil)
    mixed = clean + evil
    rng.shuffle(mixed)
    expected_mixed = "".join(line for line in mixed if line in clean)

    with tempfile.TemporaryDirectory(prefix="sanitizer-check-") as directory:
        cases = [
            ("legitimate-" + token, clean, "".join(clean)),
            ("hostile-" + token[::-1], evil, ""),
            ("combined-" + token[3:], mixed, expected_mixed),
        ]
        for name, lines, expected in cases:
            path = os.path.join(directory, name + ".log")
            with open(path, "w") as handle:
                handle.writelines(lines)
            result = run_filter(path)
            assert result.returncode == 0, f"Filter failed for generated {name} corpus: {result.stderr}"
            assert result.stdout == expected, f"Incorrect filtering for generated {name} corpus"

        alias = os.path.join(directory, "renamed-" + token + ".data")
        with open(alias, "w") as handle:
            handle.writelines(mixed)
        result = run_filter(alias)
        assert result.returncode == 0
        assert result.stdout == expected_mixed, "Filter behavior must not depend on the input path"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
