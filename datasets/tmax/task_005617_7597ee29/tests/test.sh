#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import http.client
import os
import random
import re
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

WAF_DIR = "/home/user/waf"
BACKEND_LOG = "/tmp/waf_verifier_backend.log"
BACKEND_NONCE = os.urandom(16).hex()
PROXY_BIN = "/tmp/submitted_waf_proxy"


def kill_listener(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(pid))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_port(port, process, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"Process for port {port} exited with status {process.returncode}")
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.15)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.1)
    raise AssertionError(f"Timed out waiting for port {port}")


# Compile the submitted C implementation independently and load it for direct tests.
subprocess.run(
    ["gcc", "-std=c11", "-shared", "-fPIC", "-Wall", "-o", "/tmp/libsubmitted_waf.so", "waf.c"],
    cwd=WAF_DIR,
    check=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
C_WAF = ctypes.CDLL("/tmp/libsubmitted_waf.so")
C_WAF.detect_sqli.argtypes = [ctypes.c_char_p]
C_WAF.detect_sqli.restype = ctypes.c_int

# Building the complete directory ensures waf.c is compiled as part of the cgo package.
build_env = os.environ.copy()
build_env["CGO_ENABLED"] = "1"
build_env["GO111MODULE"] = "off"
subprocess.run(
    ["go", "build", "-o", PROXY_BIN, "."],
    cwd=WAF_DIR,
    env=build_env,
    check=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)

# Replace both pre-existing listeners, then exercise the binary built from the submission.
kill_listener(8080)
kill_listener(9090)
open(BACKEND_LOG, "w").close()
backend_program = r'''
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os

nonce = os.environ["BACKEND_NONCE"]
log_path = os.environ["BACKEND_LOG"]

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        with open(log_path, "a") as f:
            f.write(self.path + "\\n")
            f.flush()
        body = ("BACKEND:" + self.path).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("X-Backend-Nonce", nonce)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", 9090), Handler).serve_forever()
'''
backend_env = os.environ.copy()
backend_env["BACKEND_NONCE"] = BACKEND_NONCE
backend_env["BACKEND_LOG"] = BACKEND_LOG
BACKEND_PROCESS = subprocess.Popen(
    [sys.executable, "-c", backend_program], env=backend_env,
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
)
wait_for_port(9090, BACKEND_PROCESS)
PROXY_PROCESS = subprocess.Popen(
    [PROXY_BIN], cwd=WAF_DIR,
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
)
wait_for_port(8080, PROXY_PROCESS)


def test_files_exist():
    """Test that all required files have been created."""
    required_files = [
        "/home/user/waf/waf.h",
        "/home/user/waf/waf.c",
        "/home/user/waf/proxy.go",
        "/home/user/test_waf.sh",
        "/home/user/waf_test.log"
    ]
    for file_path in required_files:
        assert os.path.exists(file_path), f"Required file {file_path} is missing."
        assert os.path.isfile(file_path), f"Path {file_path} exists but is not a regular file."


def test_c_source_and_cgo_integration():
    with open("/home/user/waf/waf.h", encoding="utf-8", errors="replace") as f:
        header = f.read()
    with open("/home/user/waf/waf.c", encoding="utf-8", errors="replace") as f:
        c_source = f.read()
    with open("/home/user/waf/proxy.go", encoding="utf-8", errors="replace") as f:
        go_source = f.read()

    assert re.search(r"\bint\s+detect_sqli\s*\(\s*const\s+char\s*\*\s*\w+\s*\)\s*;", header), \
        "waf.h does not declare int detect_sqli(const char *input)."
    lowered_c = c_source.lower()
    for forbidden in ("strstr", "strcasestr", "memmem", "regex.h"):
        assert forbidden not in lowered_c, f"waf.c uses forbidden search/regex facility {forbidden}."
    assert re.search(r'import\s+"C"', go_source), "proxy.go does not use cgo."
    assert re.search(r"\bC\s*\.\s*detect_sqli\s*\(", go_source), \
        "proxy.go does not call the C detect_sqli function."
    assert "RequestURI" in go_source, "proxy.go does not extract the full request URI."


def expected_detect(value):
    value = value.lower()
    for i in range(len(value) - 5):
        if value[i:i + 5] != "union":
            continue
        j = i + 5
        if j >= len(value) or value[j] != " ":
            continue
        while j < len(value) and value[j] == " ":
            j += 1
        if value[j:j + 6] == "select":
            return 1
    return 0


def test_c_detector_directly_on_generated_inputs():
    rng = random.Random(0x51A1)
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ _+-/?=&0123456789"
    samples = [
        "", "union select", "xxUNION SELECTyy", "union_select", "union+select",
        "union\tselect", "union  select", "union selected", "reunion select",
        "union     SeLeCt", "select union select", "UNION %20SELECT"
    ]
    for _ in range(100):
        samples.append("".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 90))))
    for _ in range(50):
        prefix = "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 25)))
        suffix = "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 25)))
        union = "".join(ch.upper() if rng.randrange(2) else ch for ch in "union")
        select = "".join(ch.upper() if rng.randrange(2) else ch for ch in "select")
        samples.append(prefix + union + (" " * rng.randrange(1, 9)) + select + suffix)

    for sample in samples:
        actual = C_WAF.detect_sqli(sample.encode("ascii"))
        expected = expected_detect(sample)
        assert actual == expected, f"detect_sqli({sample!r}) returned {actual}, expected {expected}."


def test_ports_listening():
    """Test that the proxy is listening on port 8080 and backend on 9090."""
    def is_port_open(port):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            return s.connect_ex(('127.0.0.1', port)) == 0

    assert is_port_open(8080), "Proxy is not listening on port 8080."
    assert is_port_open(9090), "Backend server is not listening on port 9090."


def get_http_response(url):
    """Helper to get HTTP response status and body."""
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            return response.getcode(), response.read().decode('utf-8')
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8')
    except urllib.error.URLError as e:
        return None, str(e)


def raw_request(target):
    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=4)
    conn.request("GET", target)
    response = conn.getresponse()
    body = response.read()
    result = response.status, dict(response.getheaders()), body
    conn.close()
    return result


def backend_requests():
    with open(BACKEND_LOG) as f:
        return [line.rstrip("\n") for line in f]


def test_proxy_forwards_arbitrary_safe_requests_to_real_backend():
    rng = random.Random(int(BACKEND_NONCE[:12], 16))
    targets = []
    for _ in range(6):
        token = "".join(rng.choice("abcdef0123456789") for _ in range(22))
        targets.append(f"/verify-{token}/union_and_select?q={token}&literal=union%2Bselect")

    before = len(backend_requests())
    for target in targets:
        status, headers, body = raw_request(target)
        normalized_headers = {k.lower(): v for k, v in headers.items()}
        assert status == 200, f"Safe request {target} was not forwarded: status {status}."
        assert normalized_headers.get("x-backend-nonce") == BACKEND_NONCE, \
            "Response did not come from the verifier-controlled backend on port 9090."
        assert body == ("BACKEND:" + target).encode(), "Proxy did not preserve the backend response."
    recorded = backend_requests()[before:]
    assert recorded == targets, "Backend did not receive the forwarded request URIs in order."


def test_proxy_blocks_generated_malicious_requests_without_forwarding():
    rng = random.Random(int(BACKEND_NONCE[-12:], 16))
    targets = []
    for _ in range(10):
        token = "".join(rng.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(18))
        union = "".join(ch.upper() if rng.randrange(2) else ch for ch in "union")
        select = "".join(ch.upper() if rng.randrange(2) else ch for ch in "select")
        spaces = "%20" * rng.randrange(1, 7)
        targets.append(f"/dynamic-{token}?value=pre{union}{spaces}{select}post&n={token}")

    before = len(backend_requests())
    for target in targets:
        status, _, body = raw_request(target)
        assert status == 403, f"Generated malicious request {target} was not blocked."
        assert body == b"Blocked by WAF\n", f"Incorrect exact block body for {target}: {body!r}."
    time.sleep(0.2)
    assert len(backend_requests()) == before, "A blocked SQLi request was forwarded to the backend."


def test_proxy_behavior_safe_requests():
    """Test that safe requests are forwarded and not blocked."""
    safe_urls = [
        "http://127.0.0.1:8080/",
        "http://127.0.0.1:8080/union_select",
        "http://127.0.0.1:8080/products?search=apple",
        "http://127.0.0.1:8080/union_and_select"
    ]
    for url in safe_urls:
        status, _ = get_http_response(url)
        assert status is not None, f"Failed to connect to proxy for URL: {url}"
        assert status != 403, f"Safe URL {url} was incorrectly blocked with status 403."


def test_proxy_behavior_malicious_requests():
    """Test that malicious requests are blocked with 403 and correct body."""
    malicious_urls = [
        "http://127.0.0.1:8080/?q=union%20select",
        "http://127.0.0.1:8080/?q=UnIoN%20%20%20sElEcT",
        "http://127.0.0.1:8080/items?q=UnIoN%20%20%20sElEcT%20*",
        "http://127.0.0.1:8080/?test=union%20select"
    ]
    for url in malicious_urls:
        status, body = get_http_response(url)
        assert status is not None, f"Failed to connect to proxy for URL: {url}"
        assert status == 403, f"Malicious URL {url} was not blocked. Expected 403, got {status}."
        assert body.strip() == "Blocked by WAF", f"Incorrect block body for URL {url}. Expected 'Blocked by WAF', got '{body.strip()}'."


def test_waf_test_log_contents():
    """Run the required script and test the generated log's status sequence."""
    script = "/home/user/test_waf.sh"
    with open(script, encoding="utf-8", errors="replace") as f:
        script_source = f.read()
    assert "curl" in script_source, "test_waf.sh does not use curl."
    subprocess.run(["bash", script], check=True, timeout=20)

    log_file = "/home/user/waf_test.log"
    with open(log_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected 4 lines in {log_file}, found {len(lines)}."
    assert lines[0] != "403", f"Line 1 in {log_file} should not be 403, got {lines[0]}."
    assert lines[1] == "403", f"Line 2 in {log_file} should be 403, got {lines[1]}."
    assert lines[2] != "403", f"Line 3 in {log_file} should not be 403, got {lines[2]}."
    assert lines[3] == "403", f"Line 4 in {log_file} should be 403, got {lines[3]}."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
