#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import urllib.request
import urllib.error
import subprocess
import glob
import hashlib
import base64
import secrets
import shlex
import socket
import time
import pytest

WAF_PATH = "/home/user/waf_service.py"
NGINX_CONF = "/app/testbed/nginx.conf"


def wait_for_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return True
        except OSError:
            time.sleep(0.1)
    return False


@pytest.fixture(scope="session", autouse=True)
def start_submitted_stack():
    assert os.path.isfile(WAF_PATH), f"WAF service missing at {WAF_PATH}"
    assert not os.path.islink(WAF_PATH), "WAF service must be a regular submitted source file"
    compile_result = subprocess.run(
        ["python3", "-m", "py_compile", WAF_PATH], capture_output=True, text=True
    )
    assert compile_result.returncode == 0, compile_result.stderr

    subprocess.run(["pkill", "-f", "^python3 /home/user/waf_service.py$"], check=False)
    waf_log = open("/tmp/submitted_waf.log", "w")
    waf = subprocess.Popen(
        ["python3", WAF_PATH], stdout=waf_log, stderr=subprocess.STDOUT
    )
    assert wait_for_port(9000), "Submitted WAF did not listen on 127.0.0.1:9000"

    # Ensure the backend is available, then start Nginx from the submitted config.
    if not wait_for_port(5000, timeout=1):
        backend_log = open("/tmp/testbed_backend.log", "w")
        backend = subprocess.Popen(
            ["python3", "/app/testbed/app.py"],
            stdout=backend_log,
            stderr=subprocess.STDOUT,
        )
        assert wait_for_port(5000), "Flask backend did not start"
    else:
        backend = None
        backend_log = None

    subprocess.run(["pkill", "nginx"], check=False)
    time.sleep(0.2)
    nginx_log = open("/tmp/submitted_nginx.log", "w")
    nginx = subprocess.Popen(
        ["nginx", "-c", NGINX_CONF], stdout=nginx_log, stderr=subprocess.STDOUT
    )
    assert wait_for_port(8080), "Nginx did not start on port 8080 with the submitted config"

    yield

    for proc in (nginx, waf, backend):
        if proc is not None and proc.poll() is None:
            proc.terminate()
    waf_log.close()
    nginx_log.close()
    if backend_log is not None:
        backend_log.close()


def post_json(port, obj):
    data = json.dumps(obj).encode("utf-8")
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.getcode()
    except urllib.error.HTTPError as exc:
        return exc.code


def encoded_request(text, checksum=None):
    raw = bytes(b ^ 0x5A for b in text.encode("utf-8"))
    return {
        "payload": base64.b64encode(raw).decode("ascii"),
        "checksum": checksum or hashlib.md5(text.encode("utf-8")).hexdigest(),
    }


def test_nginx_config_auth_request():
    nginx_conf_path = "/app/testbed/nginx.conf"
    assert os.path.isfile(nginx_conf_path), f"Nginx configuration file missing at {nginx_conf_path}"

    with open(nginx_conf_path, 'r') as f:
        content = f.read()

    assert "auth_request" in content, "Nginx configuration does not use auth_request directive"
    assert "9000" in content, "Nginx configuration does not reference the WAF port 9000"

    result = subprocess.run(
        ["nginx", "-t", "-c", nginx_conf_path], capture_output=True, text=True
    )
    assert result.returncode == 0, f"Invalid Nginx configuration: {result.stderr}"


def test_iptables_rules():
    result = subprocess.run(["iptables-save"], capture_output=True, text=True)
    output = result.stdout

    # Preserve the original assertions.
    assert "5000" in output and "6379" in output, "iptables rules for ports 5000 and 6379 are missing"
    assert "-j DROP" in output, "iptables rules do not contain a DROP policy for the exposed ports"
    assert "-i lo" in output and "-j ACCEPT" in output, "iptables rules do not contain an ACCEPT policy for the loopback interface"

    # Validate the policy and ordering rather than accepting unrelated strings.
    rules = []
    in_filter = False
    for line in output.splitlines():
        if line == "*filter":
            in_filter = True
            continue
        if in_filter and line == "COMMIT":
            break
        if in_filter and line.startswith("-A INPUT "):
            rules.append(shlex.split(line))

    def port_covered(tokens, port):
        proto = tokens[tokens.index("-p") + 1] if "-p" in tokens else "all"
        if proto not in ("tcp", "all"):
            return False
        option = None
        if "--dport" in tokens:
            option = tokens[tokens.index("--dport") + 1]
        elif "--dports" in tokens:
            option = tokens[tokens.index("--dports") + 1]
        if option is None:
            return True
        for item in option.split(","):
            if ":" in item:
                lo, hi = item.split(":", 1)
                if int(lo or 0) <= port <= int(hi or 65535):
                    return True
            elif int(item) == port:
                return True
        return False

    def iface_mode(tokens):
        if "-i" not in tokens:
            return "all", None
        pos = tokens.index("-i")
        negated = pos > 0 and tokens[pos - 1] == "!"
        return ("not" if negated else "only"), tokens[pos + 1]

    def applies_to_new(tokens):
        for flag in ("--ctstate", "--state"):
            if flag in tokens:
                states = tokens[tokens.index(flag) + 1].split(",")
                if "NEW" not in states:
                    return False
        return True

    for port in (5000, 6379):
        protecting_drop = None
        for index, tokens in enumerate(rules):
            if "-j" not in tokens or tokens[tokens.index("-j") + 1] != "DROP":
                continue
            if not port_covered(tokens, port) or not applies_to_new(tokens):
                continue
            mode, iface = iface_mode(tokens)
            if mode == "not" and iface == "lo":
                protecting_drop = (index, False)
                break
            if mode == "all":
                protecting_drop = (index, True)
                break

        assert protecting_drop is not None, (
            f"No INPUT DROP rule protects TCP port {port} on every non-loopback interface"
        )
        drop_index, drop_also_matches_lo = protecting_drop

        # No earlier broad ACCEPT may bypass the non-loopback DROP for a new connection.
        for tokens in rules[:drop_index]:
            if "-j" not in tokens or tokens[tokens.index("-j") + 1] != "ACCEPT":
                continue
            if not port_covered(tokens, port) or not applies_to_new(tokens):
                continue
            mode, iface = iface_mode(tokens)
            assert mode == "only" and iface == "lo", (
                f"An ACCEPT rule before the DROP can expose TCP port {port} off loopback"
            )

        if drop_also_matches_lo:
            loopback_allowed = False
            for tokens in rules[:drop_index]:
                if "-j" not in tokens or tokens[tokens.index("-j") + 1] != "ACCEPT":
                    continue
                mode, iface = iface_mode(tokens)
                if mode == "only" and iface == "lo" and port_covered(tokens, port):
                    loopback_allowed = True
                    break
            assert loopback_allowed, f"Loopback traffic to TCP port {port} is dropped"


def test_generated_waf_and_nginx_behavior():
    # Fresh random bodies prevent passing by recognizing the two shipped corpus files.
    cases = []
    for _ in range(8):
        token = secrets.token_hex(18)
        cases.append((f"request-{token}-operation=normal_read", 200))
        cases.append((f"request-{token}-operation=__import__('os')", 403))
        cases.append((f"request-{token}-operation=redis.call('GET','x')", 403))

    for text, expected in cases:
        body = encoded_request(text)
        assert post_json(9000, body) == expected, f"Direct WAF misclassified generated payload: {text}"
        assert post_json(8080, body) == expected, f"Nginx did not enforce WAF decision for: {text}"

    # A correctly encoded benign payload with an incorrect digest must not be authorized.
    text = "checksum-test-" + secrets.token_hex(24)
    bad = encoded_request(text, checksum=hashlib.md5((text + "tampered").encode()).hexdigest())
    assert post_json(9000, bad) != 200, "WAF accepted a payload with an invalid checksum"
    assert post_json(8080, bad) != 200, "Nginx authorized a payload with an invalid checksum"


def test_adversarial_corpus():
    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"

    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))

    assert len(evil_files) > 0, "No evil corpus files found"
    assert len(clean_files) > 0, "No clean corpus files found"

    evil_bypassed = []
    clean_modified = []
    url = "http://127.0.0.1:8080/"

    for filepath in evil_files:
        with open(filepath, 'rb') as f:
            data = f.read()
        req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'}, method='POST')
        try:
            urllib.request.urlopen(req, timeout=5)
            evil_bypassed.append(os.path.basename(filepath))
        except urllib.error.HTTPError as e:
            if e.code != 403:
                evil_bypassed.append(f"{os.path.basename(filepath)} (HTTP {e.code})")
        except Exception as e:
            evil_bypassed.append(f"{os.path.basename(filepath)} (Error: {e})")

    for filepath in clean_files:
        with open(filepath, 'rb') as f:
            data = f.read()
        req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'}, method='POST')
        try:
            response = urllib.request.urlopen(req, timeout=5)
            if response.getcode() != 200:
                clean_modified.append(f"{os.path.basename(filepath)} (HTTP {response.getcode()})")
        except urllib.error.HTTPError as e:
            clean_modified.append(f"{os.path.basename(filepath)} (HTTP {e.code})")
        except Exception as e:
            clean_modified.append(f"{os.path.basename(filepath)} (Error: {e})")

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/blocked: {', '.join(clean_modified)}")
    assert not evil_bypassed and not clean_modified, " | ".join(error_msgs)


def test_integration_test_log():
    path = "/home/user/integration_test.log"
    assert os.path.isfile(path), f"Manual integration test log missing at {path}"
    assert os.path.getsize(path) > 0, "Manual integration test log is empty"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
