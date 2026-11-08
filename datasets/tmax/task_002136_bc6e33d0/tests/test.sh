#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import os
import pwd
import random
import shutil
import socket
import subprocess
import time


def test_makefile_modified_for_user_install():
    """Verify the vendored Makefile was changed to install into the user's bin directory."""
    package_dir = "/app/port-monitor-1.0"
    makefile_path = os.path.join(package_dir, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile {makefile_path} does not exist."

    original_makefile = """PREFIX=/usr/local

install:
\tmkdir -p $(PREFIX)/bin
\tcp port-monitor.sh $(PREFIX)/bin/port-monitor.sh
\tchmod +x $(PREFIX)/bin/port-monitor.sh
"""
    with open(makefile_path, "r") as f:
        content = f.read()
    assert content != original_makefile, "The vendored Makefile was not modified."

    dry_run = subprocess.run(
        ["make", "-n", "install"],
        cwd=package_dir,
        capture_output=True,
        text=True,
    )
    assert dry_run.returncode == 0, (
        f"The Makefile install target is invalid. Stderr: {dry_run.stderr}"
    )
    commands = dry_run.stdout + dry_run.stderr
    assert "/home/user/bin" in commands, (
        "The Makefile install target does not resolve to /home/user/bin. "
        f"Dry-run output:\n{commands}"
    )
    assert "/usr/local/bin" not in commands, (
        "The Makefile install target still writes to /usr/local/bin. "
        f"Dry-run output:\n{commands}"
    )


def test_systemd_service_file():
    """Verify the systemd service file exists and is a structured valid unit."""
    service_path = "/home/user/.config/systemd/user/port-monitor.service"
    assert os.path.isfile(service_path), f"Service file {service_path} does not exist."

    with open(service_path, "r") as f:
        content = f.read()

    expected_exec = "ExecStart=/home/user/bin/port-monitor.sh /home/user/ports.txt /home/user/alerts.log"
    assert expected_exec in content, f"Service file missing expected ExecStart line. Found:\n{content}"

    parser = configparser.ConfigParser(interpolation=None, strict=True)
    parser.optionxform = str
    try:
        parser.read_string(content)
    except configparser.Error as exc:
        raise AssertionError(f"Service file is not a valid sectioned unit file: {exc}")

    assert parser.has_section("Service"), "Service file is missing a [Service] section."
    assert parser.has_option("Service", "ExecStart"), "[Service] is missing ExecStart."
    assert parser.get("Service", "ExecStart").strip() == (
        "/home/user/bin/port-monitor.sh /home/user/ports.txt /home/user/alerts.log"
    ), "The [Service] ExecStart command is incorrect."

    analyzer = shutil.which("systemd-analyze")
    if analyzer:
        verified = subprocess.run(
            [analyzer, "verify", service_path], capture_output=True, text=True
        )
        assert verified.returncode == 0, (
            "systemd-analyze rejected the service file:\n"
            f"{verified.stdout}{verified.stderr}"
        )


def test_script_installed_and_executable():
    """Verify the script was installed to the correct user bin directory and is executable."""
    script_path = "/home/user/bin/port-monitor.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist. Did you modify the Makefile and run make install?"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_user_bin_is_in_path():
    """Verify a login shell for the target user includes /home/user/bin in PATH."""
    user = pwd.getpwnam("user")

    def become_user():
        os.initgroups(user.pw_name, user.pw_gid)
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    env = os.environ.copy()
    env.update({"HOME": user.pw_dir, "USER": user.pw_name, "LOGNAME": user.pw_name})
    proc = subprocess.run(
        ["/bin/bash", "-lc", "printf '%s' \"$PATH\""],
        capture_output=True,
        text=True,
        env=env,
        preexec_fn=become_user,
    )
    assert proc.returncode == 0, f"Could not inspect the user's login PATH: {proc.stderr}"
    assert "/home/user/bin" in proc.stdout.split(":"), (
        f"/home/user/bin is not in the user login PATH: {proc.stdout}"
    )


def test_script_execution_time_and_correctness():
    """Verify the optimized script detects correct ports and runs within the 1.5s threshold."""
    script_path = "/home/user/bin/port-monitor.sh"
    ports_file = "/home/user/test_ports.txt"
    log_file = "/home/user/test_alerts.log"

    open_ports = []
    sockets = []

    try:
        for _ in range(10):
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.bind(("127.0.0.1", 0))
            s.listen(1)
            open_ports.append(s.getsockname()[1])
            sockets.append(s)

        closed_ports = []
        while len(closed_ports) < 190:
            p = random.randint(20000, 60000)
            if p not in open_ports and p not in closed_ports:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as check_sock:
                    if check_sock.connect_ex(("127.0.0.1", p)) != 0:
                        closed_ports.append(p)

        all_ports = open_ports + closed_ports
        random.shuffle(all_ports)

        with open(ports_file, "w") as f:
            for p in all_ports:
                f.write(f"{p}\n")

        if os.path.exists(log_file):
            os.remove(log_file)

        start_time = time.time()
        proc = subprocess.run([script_path, ports_file, log_file], capture_output=True, text=True)
        duration = time.time() - start_time

        assert proc.returncode == 0, f"Script failed with return code {proc.returncode}. Stderr: {proc.stderr}"
        assert os.path.isfile(log_file), f"Log file {log_file} was not created by the script."
        with open(log_file, "r") as f:
            lines = f.read().splitlines()

        reported_down = []
        for line in lines:
            if line.startswith("Port ") and line.endswith(" is DOWN"):
                try:
                    reported_down.append(int(line.split()[1]))
                except ValueError:
                    pass

        reported_down_set = set(reported_down)
        expected_down_set = set(closed_ports)
        missing = expected_down_set - reported_down_set
        extra = reported_down_set - expected_down_set

        assert not missing, f"Script failed to report these closed ports as DOWN: {missing}"
        assert not extra, f"Script incorrectly reported these open ports as DOWN: {extra}"
        assert duration <= 1.5, f"Execution time metric failed: duration was {duration:.2f}s, which is > 1.5s threshold."

    finally:
        for s in sockets:
            s.close()
        if os.path.exists(ports_file):
            os.remove(ports_file)
        if os.path.exists(log_file):
            os.remove(log_file)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
