#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import string
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import pytest

ORACLE = "/home/user/oracle_transformer"
AGENT = "/home/user/app/transformer"
SOURCE = "/home/user/app/src/main.rs"


def expected_rle(data):
    out = bytearray()
    i = 0
    while i < len(data):
        c = data[i]
        if 65 <= c <= 90:
            j = i + 1
            while j < len(data) and data[j] == c:
                j += 1
            out.extend(str(j - i).encode("ascii"))
            out.append(c)
            i = j
        else:
            out.append(c)
            i += 1
    return bytes(out)


def user_systemctl(*args, check=True):
    user = pwd.getpwnam("user")
    env_args = [
        f"XDG_RUNTIME_DIR=/run/user/{user.pw_uid}",
        f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{user.pw_uid}/bus",
    ]
    return subprocess.run(
        ["runuser", "-u", "user", "--", "env", *env_args,
         "systemctl", "--user", *args],
        capture_output=True, text=True, check=check,
    )


def test_rust_source_and_compiled_artifact():
    assert os.path.isfile(SOURCE), f"Rust source missing at {SOURCE}"
    assert not os.path.islink(SOURCE), "Rust source must be a real source file"
    assert os.path.getsize(SOURCE) > 0, "Rust source is empty"

    assert os.path.isfile(AGENT), f"Agent binary missing at {AGENT}"
    assert not os.path.islink(AGENT), "Transformer must not be a link to another executable"
    assert os.access(AGENT, os.X_OK), f"Agent binary at {AGENT} is not executable"
    with open(AGENT, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Transformer is not a compiled ELF executable"

    assert os.path.isfile(ORACLE), f"Oracle binary missing at {ORACLE}"
    assert not os.path.samefile(AGENT, ORACLE), "Transformer is the supplied oracle via a hard link"
    with open(AGENT, "rb") as f:
        agent_bytes = f.read()
    with open(ORACLE, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Transformer is a byte-for-byte copy of the supplied oracle"

    rebuilt = tempfile.NamedTemporaryFile(prefix="rebuilt_transformer_", delete=False)
    rebuilt.close()
    try:
        compile_proc = subprocess.run(
            ["rustc", SOURCE, "-o", rebuilt.name], capture_output=True, text=True
        )
        assert compile_proc.returncode == 0, (
            "main.rs does not compile successfully with rustc:\n" + compile_proc.stderr
        )

        cases = [b"", b"AABBBC", b"XYZ", b"aAA!!ZZZ\n", bytes(range(256))]
        rng = random.Random(2026)
        for _ in range(200):
            cases.append(bytes(rng.randrange(256) for _ in range(rng.randrange(0, 512))))

        # Derive answers independently and temporarily remove the oracle pathname so
        # source code or wrappers that delegate to it cannot pass these checks.
        hidden = ORACLE + ".verifier-hidden"
        assert not os.path.exists(hidden), f"Unexpected file at {hidden}"
        os.rename(ORACLE, hidden)
        try:
            for binary in (rebuilt.name, AGENT):
                for data in cases:
                    proc = subprocess.run([binary], input=data, capture_output=True, timeout=5)
                    assert proc.returncode == 0, f"{binary} failed on input {data!r}"
                    assert proc.stdout == expected_rle(data), (
                        f"{binary} produced incorrect output for {data!r}: {proc.stdout!r}"
                    )
        finally:
            os.rename(hidden, ORACLE)
    finally:
        try:
            os.unlink(rebuilt.name)
        except FileNotFoundError:
            pass


def test_fuzz_transformer():
    oracle_path = ORACLE
    agent_path = AGENT

    assert os.path.isfile(oracle_path), f"Oracle binary missing at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent binary missing at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary at {agent_path} is not executable"

    random.seed(42)
    chars = string.ascii_letters + string.digits + string.punctuation + " \n\t"

    for _ in range(5000):
        length = random.randint(1, 1024)
        input_str = "".join(random.choices(chars, k=length))
        input_data = input_str.encode("utf-8")

        oracle_proc = subprocess.run([oracle_path], input=input_data, capture_output=True)
        agent_proc = subprocess.run([agent_path], input=input_data, capture_output=True)

        assert agent_proc.returncode == oracle_proc.returncode, (
            f"Return code mismatch on input {input_data!r}. "
            f"Expected {oracle_proc.returncode}, got {agent_proc.returncode}"
        )
        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Output mismatch on input {input_data!r}.\n"
            f"Expected: {oracle_proc.stdout!r}\nGot: {agent_proc.stdout!r}"
        )


def test_end_to_end_nginx():
    random.seed(1337)
    chars = string.ascii_letters + string.digits + string.punctuation + " \n\t"

    for _ in range(10):
        length = random.randint(1, 100)
        input_data = "".join(random.choices(chars, k=length)).encode("utf-8")
        oracle_proc = subprocess.run([ORACLE], input=input_data, capture_output=True)
        expected_output = oracle_proc.stdout

        req = urllib.request.Request(
            "http://127.0.0.1:9090/transform", data=input_data, method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                assert response.status == 200, f"Expected HTTP 200, got {response.status}"
                body = response.read()
                assert body == expected_output, (
                    f"End-to-end output mismatch on input {input_data!r}.\n"
                    f"Expected: {expected_output!r}\nGot: {body!r}"
                )
        except urllib.error.URLError as e:
            pytest.fail(f"Nginx end-to-end request failed: {e}")


def test_systemd_service():
    service_path = "/home/user/.config/systemd/user/backend.service"
    assert os.path.isfile(service_path), f"Systemd service file missing at {service_path}"

    with open(service_path) as f:
        content = f.read()

    assert "TRANSFORMER_PATH=/home/user/app/transformer" in content, (
        "Missing or incorrect TRANSFORMER_PATH environment variable in systemd service file"
    )
    assert re.search(r"(?mi)^\s*ExecStart\s*=.*python[^\n]*?/home/user/app/server\.py(?:\s|$)", content), (
        "backend.service does not start /home/user/app/server.py with Python"
    )
    restart = re.search(r"(?mi)^\s*Restart\s*=\s*([^\s#]+)", content)
    assert restart and restart.group(1).lower() in {
        "always", "on-failure", "on-abnormal", "on-abort", "on-watchdog"
    }, "backend.service must automatically restart after a crash"
    assert re.search(r"(?mi)^\s*WantedBy\s*=\s*.*default\.target", content), (
        "backend.service is not installable under the user default target"
    )

    enabled = user_systemctl("is-enabled", "backend.service", check=False)
    assert enabled.returncode == 0 and enabled.stdout.strip() in {"enabled", "enabled-runtime"}, (
        "backend.service is not enabled for user user: " + enabled.stderr
    )
    active = user_systemctl("is-active", "backend.service", check=False)
    assert active.returncode == 0 and active.stdout.strip() == "active", (
        "backend.service is not active: " + active.stderr
    )

    pid_result = user_systemctl("show", "backend.service", "-p", "MainPID", "--value")
    pid = int(pid_result.stdout.strip())
    assert pid > 0 and os.path.isdir(f"/proc/{pid}"), "backend.service has no running main process"
    st = os.stat(f"/proc/{pid}")
    assert st.st_uid == pwd.getpwnam("user").pw_uid, "Backend service is not running as user user"
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ")
    assert b"/home/user/app/server.py" in cmdline, "Systemd MainPID is not the Python backend"
    with open(f"/proc/{pid}/environ", "rb") as f:
        environment = f.read().split(b"\0")
    assert b"TRANSFORMER_PATH=/home/user/app/transformer" in environment, (
        "Running backend does not have the required TRANSFORMER_PATH"
    )


def test_nginx_config():
    conf_path = "/home/user/app/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx config missing at {conf_path}"
    with open(conf_path) as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:8080;" in content or "proxy_pass http://localhost:8080;" in content, (
        "Nginx config proxy_pass not updated to forward to port 8080"
    )
    checked = subprocess.run(
        ["/usr/sbin/nginx", "-t", "-c", conf_path, "-p", "/home/user/app/"],
        capture_output=True, text=True,
    )
    assert checked.returncode == 0, "Nginx configuration is invalid: " + checked.stderr


def test_healthcheck_script_and_cron():
    script_path = "/home/user/app/healthcheck.sh"
    status_path = "/home/user/app/status.log"
    assert os.path.isfile(script_path), f"Healthcheck script missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Healthcheck script at {script_path} is not executable"

    with open(script_path) as f:
        script = f.read()
    assert "http://127.0.0.1:9090/transform" in script, "Healthcheck does not request the Nginx endpoint"
    assert "XYZ" in script, "Healthcheck does not send the required XYZ body"
    assert "1X1Y1Z" in script, "Healthcheck does not validate the required response"
    assert status_path in script, "Healthcheck does not log to status.log"

    before = b""
    if os.path.exists(status_path):
        with open(status_path, "rb") as f:
            before = f.read()
    start = int(time.time())
    run = subprocess.run(
        ["runuser", "-u", "user", "--", script_path], capture_output=True, timeout=15
    )
    end = int(time.time())
    assert run.returncode == 0, f"Healthcheck failed: {run.stderr.decode(errors='replace')}"
    assert os.path.isfile(status_path), "Healthcheck did not create status.log"
    with open(status_path, "rb") as f:
        after = f.read()
    assert after.startswith(before) and len(after) > len(before), "Healthcheck did not append a status entry"
    added = after[len(before):].decode("utf-8", errors="replace")
    lines = [line for line in added.splitlines() if line.strip()]
    assert lines, "Healthcheck appended no complete status line"
    matching = []
    for line in lines:
        if "OK" in line:
            matching.extend(int(x) for x in re.findall(r"(?<!\d)\d{10}(?!\d)", line))
    assert any(start - 2 <= stamp <= end + 2 for stamp in matching), (
        "Healthcheck status entry must contain OK and the current Unix timestamp"
    )

    try:
        crontab_output = subprocess.check_output(
            ["crontab", "-l", "-u", "user"], stderr=subprocess.STDOUT
        ).decode("utf-8")
        assert "healthcheck.sh" in crontab_output, "Cron job for healthcheck.sh missing in user's crontab"
    except subprocess.CalledProcessError as e:
        pytest.fail("Failed to get crontab for user 'user' or no crontab exists: " + e.output.decode("utf-8"))

    valid_job = False
    for raw_line in crontab_output.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" in line.split()[0]:
            continue
        fields = line.split(None, 5)
        if len(fields) == 6 and fields[:5] == ["*", "*", "*", "*", "*"]:
            command = fields[5]
            if re.search(r"(^|\s)/home/user/app/healthcheck\.sh(?:\s|$)", command):
                valid_job = True
                break
    assert valid_job, "User crontab must run /home/user/app/healthcheck.sh every minute"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
