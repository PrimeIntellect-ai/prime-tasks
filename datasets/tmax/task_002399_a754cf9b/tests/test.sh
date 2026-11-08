#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import shutil
import signal
import stat
import string
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ORACLE_PATH = "/app/email_router_oracle"
AGENT_PATH = "/home/user/email_router"
SOURCE_PATH = "/home/user/email_router.cpp"
SCRIPT_PATH = "/home/user/start_backend.sh"
NGINX_CONFIG = "/home/user/nginx/nginx.conf"


def generate_fuzz_inputs(n=1000, seed=42):
    random.seed(seed)
    inputs = [
        b"",
        b"Subject: URGENT",
        b"To: dev@",
        b"From: spammer@",
        b"From: spammer@x\nTo: dev@x\nSubject: URGENT",
        b"subject: urgent\nto: dev@",
        b"Subject: URGEN",
        b"To: dev",
        b"From: spammer",
        b"\x00Subject: URGENT\x00",
    ]
    keywords = ["Subject: URGENT", "To: dev@", "From: spammer@"]
    chars = string.ascii_letters + string.digits + string.punctuation + " \n\t"
    for _ in range(n):
        length = random.randint(10, 500)
        base_str = "".join(random.choice(chars) for _ in range(length))
        if random.random() < 0.5:
            kw = random.choice(keywords)
            insert_pos = random.randint(0, len(base_str))
            base_str = base_str[:insert_pos] + kw + base_str[insert_pos:]
        inputs.append(base_str[:500].encode("utf-8"))
    return inputs


def run_binary(command, input_bytes):
    try:
        result = subprocess.run(
            command,
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2,
        )
        return result.returncode, result.stdout
    except subprocess.TimeoutExpired:
        return -1, b"<TIMEOUT>"
    except Exception as exc:
        return -1, f"<ERROR: {exc}>".encode()


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.digest()


def listener_pids(port):
    wanted = set()
    port_hex = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].rsplit(":", 1)[-1].upper() == port_hex and fields[3] == "0A":
                        wanted.add(fields[9])
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
                if target.startswith("socket:[") and target[8:-1] in wanted:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def stop_listeners(*ports):
    own = os.getpid()
    pids = set()
    for port in ports:
        pids.update(listener_pids(port))
    for pid in pids:
        if pid != own:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    time.sleep(0.3)
    for pid in pids:
        if pid != own:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def wait_for_listener(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_pids(port):
            return
        time.sleep(0.05)
    raise AssertionError(f"No service began listening on port {port}")


def test_agent_binary_exists():
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"
    st = os.lstat(AGENT_PATH)
    assert stat.S_ISREG(st.st_mode), "Agent binary must be a regular file, not a link or wrapper"
    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Agent executable must be a compiled ELF binary"
    assert not os.path.samefile(AGENT_PATH, ORACLE_PATH), "Agent binary aliases the oracle"
    assert sha256(AGENT_PATH) != sha256(ORACLE_PATH), "Agent binary is a byte-for-byte oracle copy"


def test_source_exists_and_builds_independently():
    assert os.path.isfile(SOURCE_PATH) and not os.path.islink(SOURCE_PATH), \
        f"C++ source not found as a regular file at {SOURCE_PATH}"
    assert os.path.getsize(SOURCE_PATH) > 0, "C++ source is empty"

    build_dir = tempfile.mkdtemp(prefix="router-build-")
    sandbox = tempfile.mkdtemp(prefix="router-root-")
    try:
        built = os.path.join(build_dir, "email_router")
        result = subprocess.run(
            ["g++", "-std=c++17", "-O2", "-static", SOURCE_PATH, "-o", built],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, f"Source did not compile:\n{result.stderr.decode(errors='replace')}"

        shutil.copy2(built, os.path.join(sandbox, "email_router"))
        os.chmod(os.path.join(sandbox, "email_router"), 0o755)
        inputs = generate_fuzz_inputs(1000)
        for i, inp in enumerate(inputs):
            oracle_rc, oracle_out = run_binary([ORACLE_PATH], inp)
            built_rc, built_out = run_binary(["chroot", sandbox, "/email_router"], inp)
            assert oracle_rc == 0, f"Oracle failed on input {i}"
            assert built_rc == 0, f"Freshly compiled source failed in an oracle-free sandbox on input {i}"
            assert oracle_out == built_out, (
                f"Freshly compiled source mismatched oracle on input {i}:\n"
                f"Input: {inp!r}\nOracle: {oracle_out!r}\nSource build: {built_out!r}"
            )
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)
        shutil.rmtree(sandbox, ignore_errors=True)


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    for i, inp in enumerate(generate_fuzz_inputs(1000)):
        oracle_rc, oracle_out = run_binary([ORACLE_PATH], inp)
        agent_rc, agent_out = run_binary([AGENT_PATH], inp)
        assert oracle_rc == 0, f"Oracle failed on input {i}"
        assert agent_rc == 0, f"Agent binary failed on input {i}"
        assert oracle_out == agent_out, (
            f"Mismatch on input {i}:\nInput: {inp!r}\n"
            f"Oracle output: {oracle_out!r}\nAgent output: {agent_out!r}"
        )


def test_script_exists_and_handles_missing_binary():
    assert os.path.exists(SCRIPT_PATH), f"Backend script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Backend script at {SCRIPT_PATH} is not executable"
    assert stat.S_ISREG(os.lstat(SCRIPT_PATH).st_mode), "Backend script must be a regular file"
    syntax = subprocess.run(["bash", "-n", SCRIPT_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert syntax.returncode == 0, f"Backend script has invalid syntax: {syntax.stderr!r}"

    text = open(SCRIPT_PATH, errors="replace").read()
    assert "/home/user/email_router" in text, "Backend script does not launch the required binary"
    assert "9000" in text, "Backend script does not serve on port 9000"
    assert re.search(r"\b(socat|nc|netcat)\b", text), "Backend script does not use socat or nc"

    stop_listeners(9000)
    hidden = AGENT_PATH + ".verifier-hidden"
    os.rename(AGENT_PATH, hidden)
    try:
        proc = subprocess.Popen([SCRIPT_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            rc = proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
            raise AssertionError("Backend script did not fail promptly when its router binary was missing")
        assert rc != 0, "Backend script reported success despite a missing router binary"
        assert not listener_pids(9000), "Backend script left a listener running after startup failure"
    finally:
        if os.path.exists(hidden):
            os.rename(hidden, AGENT_PATH)
        stop_listeners(9000)


def test_nginx_configuration_and_routing_fixed():
    assert os.path.isfile(NGINX_CONFIG) and not os.path.islink(NGINX_CONFIG), \
        f"Nginx config not found as a regular file at {NGINX_CONFIG}"
    config = open(NGINX_CONFIG, errors="replace").read()
    assert re.search(r"location\s+(?:=\s*)?/route\s*\{[^}]*proxy_pass\s+http://127\.0\.0\.1:9000\s*;", config, re.S), \
        "The /route location must proxy to http://127.0.0.1:9000"
    checked = subprocess.run(["nginx", "-t", "-c", NGINX_CONFIG], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert checked.returncode == 0, f"Invalid Nginx configuration: {checked.stderr!r}"

    stop_listeners(8080, 9000)
    backend = subprocess.Popen([SCRIPT_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    nginx = None
    try:
        wait_for_listener(9000)
        started = subprocess.run(["nginx", "-c", NGINX_CONFIG], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert started.returncode == 0, f"Nginx failed to start: {started.stderr!r}"
        wait_for_listener(8080)

        cases = [
            (b"From: someuser@example.com\nTo: dev@example.com\nSubject: Hello\n\nBody text", b"dev-list"),
            (b"From: spammer@example.com\nSubject: ordinary\n\nBody", b"drop"),
            (b"To: dev@example.com\nSubject: URGENT maintenance\n\nBody", b"admin-list"),
            (b"From: normal@example.com\nTo: sales@example.com\nSubject: Hello\n\nBody", b"general-inbox"),
        ]
        for payload, expected in cases:
            req = urllib.request.Request("http://127.0.0.1:8080/route", method="POST", data=payload)
            try:
                with urllib.request.urlopen(req, timeout=4) as response:
                    status = response.getcode()
                    body = response.read()
            except urllib.error.HTTPError as exc:
                raise AssertionError(f"HTTP request failed with status {exc.code}: {exc.read()!r}")
            assert status == 200, f"Expected HTTP 200, got {status}"
            assert expected in body, f"Expected {expected!r} in response, got {body!r}"
    finally:
        subprocess.run(["nginx", "-s", "stop", "-c", NGINX_CONFIG], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if backend.poll() is None:
            backend.terminate()
            try:
                backend.wait(timeout=2)
            except subprocess.TimeoutExpired:
                backend.kill()
                backend.wait()
        stop_listeners(8080, 9000)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
