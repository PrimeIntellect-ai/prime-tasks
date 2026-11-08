#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import signal
import subprocess
import time


def test_directories_exist():
    """Test that all required directories have been created."""
    dirs = [
        "/home/user/src",
        "/home/user/bin",
        "/home/user/logs",
        "/home/user/scripts",
        "/home/user/config",
        "/home/user/.config/systemd/user"
    ]
    for d in dirs:
        assert os.path.isdir(d), f"Directory {d} does not exist."


def test_c_source_code():
    """Test that the C source exists, retains the required elements, and compiles."""
    src_file = "/home/user/src/microservice.c"
    assert os.path.isfile(src_file), f"Source file {src_file} does not exist."

    with open(src_file, "r") as f:
        content = f.read()

    required_strings = [
        "SERVICE_OK\\n",
        "/home/user/logs/micro.log",
        "fopen",
        "fprintf",
        "fflush",
        "sleep"
    ]
    for req in required_strings:
        assert req in content, f"Expected '{req}' to be in {src_file}"

    result = subprocess.run(
        ["gcc", src_file, "-o", "/tmp/microservice-from-source"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"C source does not compile:\n{result.stderr}"


def test_executable_exists():
    """Test that the compiled executable exists, is executable, and is a native binary."""
    bin_file = "/home/user/bin/microservice"
    assert os.path.isfile(bin_file), f"Executable {bin_file} does not exist."
    assert os.access(bin_file, os.X_OK), f"File {bin_file} is not executable."
    with open(bin_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", "microservice is not a compiled ELF executable"


def _stop_existing_microservices():
    target = os.path.realpath("/home/user/bin/microservice")
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            exe = os.path.realpath(f"/proc/{entry}/exe")
            if exe == target:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.2)


def _run_as_user_preexec():
    account = pwd.getpwnam("user")
    os.setsid()
    os.initgroups(account.pw_name, account.pw_gid)
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def _check_periodic_logging(executable):
    log_file = "/home/user/logs/micro.log"
    _stop_existing_microservices()
    try:
        os.unlink(log_file)
    except FileNotFoundError:
        pass

    proc = subprocess.Popen(
        [executable],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        preexec_fn=_run_as_user_preexec,
    )
    changes = []
    last_count = 0
    start = time.monotonic()
    try:
        while time.monotonic() - start < 4.2:
            assert proc.poll() is None, "microservice exited instead of running indefinitely"
            if os.path.exists(log_file):
                with open(log_file, "rb") as f:
                    data = f.read()
                assert data == b"SERVICE_OK\n" * (len(data) // len(b"SERVICE_OK\n")), \
                    "microservice wrote data other than complete SERVICE_OK lines"
                count = len(data) // len(b"SERVICE_OK\n")
                if count != last_count:
                    assert count == last_count + 1, "multiple log lines appeared at once"
                    changes.append(time.monotonic())
                    last_count = count
            time.sleep(0.08)

        assert proc.poll() is None, "microservice did not remain running"
        assert 3 <= last_count <= 5, f"expected about one line per second, got {last_count} lines"
        assert len(changes) >= 3, "too few observable periodic writes"
        for earlier, later in zip(changes, changes[1:]):
            interval = later - earlier
            assert 0.65 <= interval <= 1.45, f"writes were not one second apart ({interval:.2f}s)"
    finally:
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=2)


def test_compiled_microservice_behavior():
    """Execute both the submitted binary and a fresh build of the submitted source."""
    _check_periodic_logging("/home/user/bin/microservice")
    _check_periodic_logging("/tmp/microservice-from-source")


def _active_unit_values(path):
    values = {}
    section = None
    with open(path, "r") as f:
        for number, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("#") or line.startswith(";"):
                continue
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1].strip()
                assert section, f"Empty section at line {number}"
                continue
            assert section is not None and "=" in line, f"Malformed unit line {number}: {raw.rstrip()}"
            key, value = line.split("=", 1)
            key = key.strip()
            assert key, f"Missing key at line {number}"
            values.setdefault((section, key), []).append(value.strip())
    return values


def test_systemd_service_file():
    """Test that systemd parses the unit and that required settings are active directives."""
    service_file = "/home/user/.config/systemd/user/micro.service"
    assert os.path.isfile(service_file), f"Service file {service_file} does not exist."

    with open(service_file, "r") as f:
        content = f.read()

    assert "Description=Microservice Daemon" in content, "Missing correct Description in service file."
    assert "ExecStart=/home/user/bin/microservice" in content, "Missing correct ExecStart in service file."
    assert "Restart=always" in content, "Missing Restart=always in service file."

    values = _active_unit_values(service_file)
    assert values.get(("Unit", "Description")) == ["Microservice Daemon"]
    assert values.get(("Service", "ExecStart")) == ["/home/user/bin/microservice"]
    assert values.get(("Service", "Restart")) == ["always"]

    checked = subprocess.run(
        ["systemd-analyze", "verify", service_file],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert checked.returncode == 0, f"Invalid systemd unit:\n{checked.stdout}{checked.stderr}"


def test_required_systemctl_operations_are_exercised():
    """Attempt the required user daemon reload and start; container bus failures are allowed."""
    account = pwd.getpwnam("user")
    env = os.environ.copy()
    env.update({
        "HOME": account.pw_dir,
        "USER": account.pw_name,
        "LOGNAME": account.pw_name,
        "XDG_RUNTIME_DIR": f"/run/user/{account.pw_uid}",
    })
    commands = [
        ["runuser", "-u", "user", "--", "systemctl", "--user", "daemon-reload"],
        ["runuser", "-u", "user", "--", "systemctl", "--user", "start", "micro.service"],
    ]
    results = []
    for command in commands:
        results.append(subprocess.run(command, env=env, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, text=True, timeout=10))
    if results[1].returncode == 0:
        status = subprocess.run(
            ["runuser", "-u", "user", "--", "systemctl", "--user", "is-active", "micro.service"],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10,
        )
        assert status.returncode == 0 and status.stdout.strip() == "active"
        subprocess.run(
            ["runuser", "-u", "user", "--", "systemctl", "--user", "stop", "micro.service"],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10,
        )


def _parse_logrotate_target(path):
    blocks = []
    current_target = None
    directives = []
    with open(path, "r") as f:
        for number, raw in enumerate(f, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            if current_target is None:
                assert line.endswith("{"), f"Malformed logrotate line {number}: {raw.rstrip()}"
                current_target = line[:-1].strip().strip('"')
                directives = []
            elif line == "}":
                blocks.append((current_target, directives))
                current_target = None
            else:
                assert "{" not in line and "}" not in line, f"Malformed directive at line {number}"
                directives.append(line.split())
    assert current_target is None, "Unclosed logrotate block"
    matches = [rules for target, rules in blocks if target == "/home/user/logs/micro.log"]
    assert len(matches) == 1, "Config must contain one active block for /home/user/logs/micro.log"
    return matches[0]


def test_logrotate_script_and_config():
    """Test script execution, byte-for-byte idempotency, syntax, and active rules."""
    script_file = "/home/user/scripts/setup_logrotate.sh"
    config_file = "/home/user/config/micro-logrotate.conf"

    assert os.path.isfile(script_file), f"Script {script_file} does not exist."
    assert os.access(script_file, os.X_OK), f"Script {script_file} is not executable."

    subprocess.run([script_file], check=True)
    assert os.path.isfile(config_file), f"Config file {config_file} was not created."
    with open(config_file, "rb") as f:
        first_output = f.read()

    subprocess.run([script_file], check=True)
    with open(config_file, "rb") as f:
        second_output = f.read()
    assert first_output == second_output, "Script is not idempotent: config changed on the second run"

    with open(config_file, "r") as f:
        lines = f.readlines()
    assert len(lines) < 25, "Config file is too long, script might not be idempotent."

    content = "".join(lines)
    assert "/home/user/logs/micro.log" in content, "Config does not target /home/user/logs/micro.log"
    assert "hourly" in content, "Config missing 'hourly'"
    assert "rotate 5" in content, "Config missing 'rotate 5'"
    assert "missingok" in content, "Config missing 'missingok'"
    assert "compress" in content, "Config missing 'compress'"
    assert "copytruncate" in content, "Config missing 'copytruncate'"

    rules = _parse_logrotate_target(config_file)
    for required in [["hourly"], ["rotate", "5"], ["missingok"], ["compress"], ["copytruncate"]]:
        assert required in rules, f"Missing active logrotate directive: {' '.join(required)}"

    syntax = subprocess.run(
        ["logrotate", "--debug", "--state", "/tmp/micro-logrotate.state", config_file],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert syntax.returncode == 0, f"Invalid logrotate configuration:\n{syntax.stdout}{syntax.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
