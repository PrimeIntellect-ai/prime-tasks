#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import signal
import socket
import string
import subprocess
import tempfile
import time
import urllib.request


def expected_output(value):
    return " ".join(str((ord(ch) ^ 42) + 15) for ch in value)


def run_processor(path, value):
    return subprocess.run([path, value], capture_output=True, text=True, timeout=5)


def test_migrated_processor_cpp_exists():
    path = "/home/user/migrated_processor.cpp"
    assert os.path.isfile(path), f"Missing C++ source file at {path}"


def test_deploy_script_exists_and_executable():
    path = "/home/user/deploy.sh"
    assert os.path.isfile(path), f"Missing deployment script at {path}"
    assert os.access(path, os.X_OK), f"Deployment script at {path} is not executable"


def test_deploy_script_contents():
    path = "/home/user/deploy.sh"
    with open(path, "r") as f:
        content = f.read()

    assert "ssh" in content and "-L" in content and "8080:localhost:9090" in content, \
        "Deployment script does not contain the correct SSH port forwarding command."
    assert "python3" in content and "http.server" in content and "9090" in content, \
        "Deployment script does not contain the python http.server command."
    assert "health.log" in content, \
        "Deployment script does not write to health.log."


def _kill_port(port):
    subprocess.run(["fuser", "-k", f"{port}/tcp"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)


def _http_through_tunnel():
    try:
        with urllib.request.urlopen("http://127.0.0.1:8080/", timeout=1) as response:
            return 200 <= response.status < 500
    except Exception:
        return False


def _ssh_forward_process_exists():
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        except (OSError, PermissionError):
            continue
        if exe == "ssh" and "8080:localhost:9090" in " ".join(args) and any(
                arg == "-L" or arg.startswith("-L") for arg in args):
            return True
    return False


def _start_test_sshd():
    os.makedirs("/run/sshd", exist_ok=True)
    subprocess.run(["ssh-keygen", "-A"], check=True, stdout=subprocess.DEVNULL)

    key = "/root/.ssh/id_ed25519"
    os.makedirs("/root/.ssh", mode=0o700, exist_ok=True)
    if not os.path.exists(key):
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", key], check=True)
    with open(key + ".pub") as f:
        public_key = f.read()

    for ssh_dir in ("/root/.ssh", "/home/user/.ssh"):
        os.makedirs(ssh_dir, mode=0o700, exist_ok=True)
        auth = os.path.join(ssh_dir, "authorized_keys")
        with open(auth, "w") as f:
            f.write(public_key)
        os.chmod(auth, 0o600)
    os.chown("/home/user/.ssh", 1000, 1000)
    os.chown("/home/user/.ssh/authorized_keys", 1000, 1000)

    config = "/tmp/verifier_sshd_config"
    with open(config, "w") as f:
        f.write("""Port 22
ListenAddress 127.0.0.1
ListenAddress ::1
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
AllowTcpForwarding yes
PidFile /tmp/verifier_sshd.pid
LogLevel ERROR
""")
    proc = subprocess.Popen(["/usr/sbin/sshd", "-D", "-f", config],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)
    assert proc.poll() is None, "Could not start the verifier's local SSH endpoint"

    scan = subprocess.run(["ssh-keyscan", "-T", "2", "localhost"], capture_output=True, text=True)
    assert scan.returncode == 0 and scan.stdout, "Could not obtain the local SSH host key"
    with open("/root/.ssh/known_hosts", "w") as f:
        f.write(scan.stdout)
    os.chmod("/root/.ssh/known_hosts", 0o600)
    return proc


def test_deploy_script_operates_tunnel_monitor_and_health_checks():
    _kill_port(8080)
    _kill_port(9090)
    _kill_port(22)
    health = "/home/user/health.log"
    try:
        os.remove(health)
    except FileNotFoundError:
        pass

    sshd = _start_test_sshd()
    deploy = None
    deploy_group = None
    try:
        env = os.environ.copy()
        env["HOME"] = "/root"
        deploy = subprocess.Popen(["/home/user/deploy.sh"], cwd="/home/user", env=env,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                  preexec_fn=os.setsid)
        deploy_group = os.getpgid(deploy.pid)

        deadline = time.monotonic() + 12
        while time.monotonic() < deadline and not _http_through_tunnel():
            if deploy.poll() not in (None, 0):
                raise AssertionError(f"deploy.sh exited with status {deploy.returncode}")
            time.sleep(0.2)
        assert _http_through_tunnel(), \
            "deploy.sh did not start the HTTP service and make it reachable through localhost:8080"
        assert _ssh_forward_process_exists(), \
            "No live ssh process with the required -L 8080:localhost:9090 forwarding was found"

        observations = []
        seen_count = 0
        deadline = time.monotonic() + 13
        while time.monotonic() < deadline and len(observations) < 2:
            try:
                with open(health) as f:
                    lines = [line.strip() for line in f if line.strip()]
            except FileNotFoundError:
                lines = []
            if len(lines) > seen_count:
                observations.append((time.monotonic(), lines[-1]))
                seen_count = len(lines)
            time.sleep(0.1)

        assert len(observations) >= 2, "health.log was not updated continuously"
        assert observations[1][0] - observations[0][0] >= 4.0, \
            "Health checks were written more frequently than the required five-second interval"
        status_re = re.compile(r"(status|running|healthy|active|online|available|success|\bok\b|\bup\b|\b200\b)", re.I)
        timestamp_re = re.compile(r"(20\d\d|\b\d{10}(?:\.\d+)?\b)")
        for _, line in observations[:2]:
            assert timestamp_re.search(line), f"Health entry lacks a recognizable timestamp: {line!r}"
            assert status_re.search(line), f"Health entry lacks a service status: {line!r}"

        subprocess.run(["pkill", "-f", "python3 -m http.server 9090"], check=False)
        went_down = False
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if not _http_through_tunnel():
                went_down = True
                break
            time.sleep(0.1)
        assert went_down, "The test HTTP service could not be stopped"

        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and not _http_through_tunnel():
            time.sleep(0.2)
        assert _http_through_tunnel(), \
            "The monitoring loop did not restart the stopped HTTP service"
    finally:
        if deploy_group is not None:
            try:
                os.killpg(deploy_group, signal.SIGTERM)
            except ProcessLookupError:
                pass
        _kill_port(8080)
        _kill_port(9090)
        if sshd.poll() is None:
            sshd.terminate()
            try:
                sshd.wait(timeout=2)
            except subprocess.TimeoutExpired:
                sshd.kill()


def test_fuzz_equivalence():
    source_path = "/home/user/migrated_processor.cpp"
    agent_path = "/home/user/migrated_processor"

    assert os.path.isfile(agent_path), f"Missing compiled binary at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Binary at {agent_path} is not executable"
    with open(agent_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "migrated_processor is not a compiled native executable"

    with tempfile.TemporaryDirectory() as tmp:
        rebuilt_path = os.path.join(tmp, "rebuilt_processor")
        build = subprocess.run(["g++", "-std=c++17", source_path, "-o", rebuilt_path],
                               capture_output=True, text=True, timeout=30)
        assert build.returncode == 0, f"C++ source does not compile:\n{build.stderr}"

        random.seed(42)
        chars = string.ascii_letters + string.digits
        cases = ["A", "0", "z9A0"]
        for _ in range(5000):
            length = random.randint(5, 50)
            cases.append("".join(random.choices(chars, k=length)))

        for test_input in cases:
            expected = expected_output(test_input)
            for path in (agent_path, rebuilt_path):
                proc = run_processor(path, test_input)
                assert proc.returncode == 0, \
                    f"Processor {path} returned {proc.returncode} on input {test_input!r}"
                assert proc.stdout.strip() == expected, \
                    f"Output mismatch from {path} on input {test_input!r}.\nExpected: {expected}\nActual: {proc.stdout.strip()}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
