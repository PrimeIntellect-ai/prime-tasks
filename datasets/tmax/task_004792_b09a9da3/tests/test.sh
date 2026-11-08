#!/bin/bash
mkdir -p /logs/verifier

cd /home/user/pr_review
(timeout 180 python3 -m pytest test_api.py > /home/user/pr_review/test_results.log 2>&1)
printf '%s\n' "$?" > /tmp/agent_pytest_status

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import urllib.error
import urllib.request

ROOT = "/home/user/pr_review"


def request_limit(limit):
    req = urllib.request.Request("http://localhost:8080/resolve")
    req.add_header("Constraint_Limit", str(limit))
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.status, json.loads(response.read().decode())


def test_test_results_log():
    log_path = "/home/user/pr_review/test_results.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist. Did you run pytest and redirect the output?"

    with open(log_path, "r") as f:
        content = f.read()

    # Retain the original log assertions, but only after the verifier itself ran pytest.
    assert "failed" not in content.lower() or "0 failed" in content.lower(), "pytest output indicates test failures."
    assert "passed" in content.lower(), "pytest output does not indicate that tests passed."

    with open("/tmp/agent_pytest_status", "r") as f:
        status = int(f.read().strip())
    assert status == 0, f"The real pytest invocation exited with status {status}. Output:\n{content}"


def test_nginx_conf_updated():
    conf_path = "/home/user/pr_review/nginx.conf"
    assert os.path.isfile(conf_path), f"{conf_path} is missing."

    with open(conf_path, "r") as f:
        content = f.read()

    assert "underscores_in_headers on;" in content, "nginx.conf does not contain 'underscores_in_headers on;'."
    assert re.search(r"^\s*underscores_in_headers\s+on\s*;", content, re.MULTILINE), \
        "nginx.conf only mentions the directive in a comment; it must be enabled."

    checked = subprocess.run(
        ["nginx", "-t", "-c", conf_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert checked.returncode == 0, f"nginx.conf is invalid:\n{checked.stdout}"


def test_port_8080_is_served_by_nginx():
    listening_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        with open(table, "r") as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9:
                    local_port = int(fields[1].rsplit(":", 1)[1], 16)
                    state = fields[3]
                    if local_port == 8080 and state == "0A":
                        listening_inodes.add(fields[9])

    assert listening_inodes, "Nothing is listening on port 8080."
    nginx_owns_listener = False
    for pid in (p for p in os.listdir("/proc") if p.isdigit()):
        fd_dir = f"/proc/{pid}/fd"
        try:
            with open(f"/proc/{pid}/comm", "r") as f:
                comm = f.read().strip()
            if comm != "nginx":
                continue
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if any(target == f"socket:[{inode}]" for inode in listening_inodes):
                    nginx_owns_listener = True
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if nginx_owns_listener:
            break

    assert nginx_owns_listener, "Port 8080 is not being served by an Nginx process."


def test_resolver_implementation_directly():
    probe = r'''
import importlib.util
spec = importlib.util.spec_from_file_location("submitted_resolver", "/home/user/pr_review/resolver.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
for limit in range(0, 101):
    resolver = module.ConstraintResolver()
    resolver.add_item(5)
    resolver.add_item(10)
    actual = resolver.resolve(limit)
    expected = [value for value in (5, 10) if value <= limit]
    assert actual == expected, (limit, actual, expected)
assert module.ConstraintResolver().resolve(0) == []
'''
    result = subprocess.run(
        ["python3", "-c", probe],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=15,
        cwd=ROOT,
    )
    assert result.returncode == 0, f"resolver.py failed direct behavioral checks:\n{result.stdout}"


def test_api_via_proxy_limit_10():
    req = urllib.request.Request("http://localhost:8080/resolve")
    req.add_header("Constraint_Limit", "10")

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected status 200, got {response.status}"
            data = json.loads(response.read().decode())
            assert "result" in data, "Response JSON missing 'result' key"
            assert data["result"] == [5, 10], f"Unexpected result for limit 10: {data['result']!r}"
    except urllib.error.HTTPError as e:
        assert False, f"HTTP request failed with status {e.code}. Is Nginx stripping the header?"
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to Nginx proxy: {e.reason}. Are the services running?"


def test_api_via_proxy_limit_0():
    req = urllib.request.Request("http://localhost:8080/resolve")
    req.add_header("Constraint_Limit", "0")

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected status 200, got {response.status}"
            data = json.loads(response.read().decode())
            assert "result" in data, "Response JSON missing 'result' key"
            assert data["result"] == [], f"A zero constraint limit must return [], got {data['result']!r}"
    except urllib.error.HTTPError as e:
        assert False, f"HTTP request failed with status {e.code}. Did resolver.py fail on limit=0?"
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to Nginx proxy: {e.reason}. Are the services running?"


def test_api_via_proxy_across_constraint_domain():
    for limit in range(0, 101):
        status, data = request_limit(limit)
        expected = [value for value in (5, 10) if value <= limit]
        assert status == 200, f"Expected status 200 for limit {limit}, got {status}"
        assert isinstance(data, dict) and "result" in data, f"Invalid response for limit {limit}: {data!r}"
        assert data["result"] == expected, \
            f"Incorrect result for limit {limit}: expected {expected!r}, got {data['result']!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
