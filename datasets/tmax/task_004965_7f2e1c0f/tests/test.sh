#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import socket
import stat
import subprocess
import time
import urllib.request

APP_DIR = "/home/user/app_data"
SOURCE = "/home/user/metrics_agent.cpp"
BINARY = "/home/user/metrics_agent"
LOG = "/home/user/dashboard_metrics.log"
SCRIPT = "/home/user/poll_metrics.sh"
CFG = "/home/user/haproxy.cfg"
MAX_DELTA = 50 * 1024 * 1024


def actual_available():
    s = os.statvfs(APP_DIR)
    return s.f_bavail * s.f_frsize


def validate_metric(data):
    assert isinstance(data, dict)
    assert data.get("directory") == APP_DIR
    assert "available_bytes" in data
    assert isinstance(data["available_bytes"], int) and not isinstance(data["available_bytes"], bool)
    actual = actual_available()
    assert abs(data["available_bytes"] - actual) < MAX_DELTA, (
        f"Reported available space ({data['available_bytes']}) differs significantly "
        f"from actual ({actual})."
    )


def get_json(port):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=4) as response:
        assert response.status == 200
        content_type = response.headers.get("Content-Type", "").lower()
        assert "application/json" in content_type
        return json.loads(response.read().decode("utf-8"))


def listening_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10:
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
    return result


def listener_pids(port):
    inodes = listening_inodes(port)
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
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def proc_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return ""


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace").strip()
    except OSError:
        return ""


def run_as_user_preexec():
    account = pwd.getpwnam("user")
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def exercise_program(path):
    probe = socket.socket()
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    process = subprocess.Popen(
        [path, str(port)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        preexec_fn=run_as_user_preexec
    )
    try:
        deadline = time.time() + 5
        last_error = None
        while time.time() < deadline:
            if process.poll() is not None:
                raise AssertionError(f"{path} exited before serving HTTP")
            try:
                data = get_json(port)
                validate_metric(data)
                return
            except Exception as exc:
                last_error = exc
                time.sleep(0.1)
        raise AssertionError(f"Could not obtain a valid response from {path}: {last_error}")
    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2)


def read_log_and_validate(path=LOG):
    assert os.path.exists(path), f"Log file {path} is missing."
    with open(path) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 6, f"Expected exactly 6 non-empty lines in {path}, found {len(lines)}."
    for number, line in enumerate(lines, 1):
        try:
            data = json.loads(line)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"Line {number} is not valid JSON: {line}") from exc
        validate_metric(data)
    return lines


def test_log_file_and_json_content():
    read_log_and_validate()


def test_available_bytes_correct():
    with open(LOG) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines, "Log file is empty."
    validate_metric(json.loads(lines[0]))


def test_fixed_source_and_compiled_executable():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    source = open(SOURCE).read()
    compact = re.sub(r"\s+", "", source)
    assert "std::filesystem::space(" in compact, "Source does not call std::filesystem::space."
    assert re.search(r"(?:\.available\b|\.available\(\))", compact), "Source does not use space_info.available."

    assert os.path.isfile(BINARY), f"Compiled executable {BINARY} is missing."
    mode = os.stat(BINARY).st_mode
    assert stat.S_ISREG(mode) and mode & 0o111, f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable."
    assert os.path.getmtime(BINARY) >= os.path.getmtime(SOURCE), "Executable is older than the fixed source."
    exercise_program(BINARY)

    rebuilt = "/tmp/verifier_metrics_agent"
    result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"The submitted C++ source does not compile:\n{result.stderr}"
    os.chown(rebuilt, pwd.getpwnam("user").pw_uid, pwd.getpwnam("user").pw_gid)
    exercise_program(rebuilt)


def test_backend_agents_running_and_serving():
    output = subprocess.check_output(["ps", "aux"], text=True)
    agent_lines = [line for line in output.splitlines() if "metrics_agent" in line and "grep" not in line]
    assert len(agent_lines) >= 3, "Expected at least 3 instances of metrics_agent running."

    distinct = set()
    for port in (8081, 8082, 8083):
        pids = listener_pids(port)
        matching = []
        for pid in pids:
            try:
                if os.path.samefile(f"/proc/{pid}/exe", BINARY):
                    matching.append(pid)
            except (FileNotFoundError, OSError):
                pass
        assert matching, f"The submitted metrics_agent is not listening on port {port}."
        distinct.add(matching[0])
        validate_metric(get_json(port))
    assert len(distinct) == 3, "Ports 8081, 8082, and 8083 must be served by three agent instances."


def test_haproxy_running_and_configured():
    output = subprocess.check_output(["ps", "aux"], text=True)
    assert "haproxy" in output, "HAProxy process is not running."
    assert os.path.isfile(CFG), f"HAProxy config {CFG} is missing."
    check = subprocess.run(["haproxy", "-c", "-f", CFG], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert check.returncode == 0, f"Invalid HAProxy configuration:\n{check.stdout}"

    cleaned = "\n".join(line.split("#", 1)[0] for line in open(CFG))
    assert re.search(r"(?im)^\s*balance\s+roundrobin\s*$", cleaned), "HAProxy is not configured for round-robin balancing."
    assert re.search(r"(?im)^\s*bind\s+(?:\*|0\.0\.0\.0|127\.0\.0\.1|localhost)?(?::)?8080\b", cleaned), "HAProxy does not bind port 8080."
    configured = set(int(p) for p in re.findall(r"(?im)^\s*server\s+\S+\s+127\.0\.0\.1:(808[123])\b", cleaned))
    assert configured == {8081, 8082, 8083}, "HAProxy must configure all three required backends."

    pids = listener_pids(8080)
    assert any(os.path.basename(proc_exe(pid)) == "haproxy" for pid in pids), "HAProxy is not actually listening on port 8080."
    haproxy_pids = [int(p) for p in os.listdir('/proc') if p.isdigit() and os.path.basename(proc_exe(int(p))) == 'haproxy']
    assert any(CFG in proc_cmdline(pid) for pid in haproxy_pids), "Running HAProxy was not started with /home/user/haproxy.cfg."
    validate_metric(get_json(8080))


def test_ssh_tunnel_running_and_forwarding():
    output = subprocess.check_output(["ps", "aux"], text=True)
    ssh_running = any("ssh" in line and "9090" in line for line in output.splitlines())
    assert ssh_running, "SSH tunnel process for port 9090 is not running."

    ssh_pids = [pid for pid in listener_pids(9090) if os.path.basename(proc_exe(pid)) == "ssh"]
    assert ssh_pids, "Port 9090 is not being listened on by an SSH client."
    tunnel_pattern = re.compile(r"(?:^|\s)-L\s*(?:(?:localhost|127\.0\.0\.1):)?9090:(?:localhost|127\.0\.0\.1):8080(?:\s|$)")
    assert any(tunnel_pattern.search(proc_cmdline(pid)) for pid in ssh_pids), "The SSH process does not forward local 9090 to localhost:8080."
    validate_metric(get_json(9090))


def test_poll_metrics_script_exists_and_works():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK) or os.access(SCRIPT, os.R_OK), f"Script {SCRIPT} is not readable/executable."

    if os.path.exists(LOG):
        os.remove(LOG)
    start = time.monotonic()
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", "-x", SCRIPT],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    elapsed = time.monotonic() - start
    assert result.returncode == 0, f"poll_metrics.sh failed:\n{result.stderr}"

    traced = [line.lstrip("+").strip() for line in result.stderr.splitlines() if line.startswith("+")]
    curl_commands = [line for line in traced if re.match(r"^curl(?:\s|$)", line)]
    assert len(curl_commands) == 6, f"poll_metrics.sh executed {len(curl_commands)} curl commands instead of exactly 6."
    for command in curl_commands:
        assert "http://localhost:9090" in command, f"Incorrect curl target: {command}"
        assert re.search(r"(?:^|\s)(?:-s\S*|--silent)(?:\s|$)", command), f"curl progress is not suppressed: {command}"
    sleeps = [line for line in traced if re.fullmatch(r"sleep\s+1(?:\.0+)?", line)]
    assert len(sleeps) in (5, 6), "Requests are not separated by one-second sleeps."
    assert elapsed >= 4.5, "poll_metrics.sh did not wait between requests."
    read_log_and_validate()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
