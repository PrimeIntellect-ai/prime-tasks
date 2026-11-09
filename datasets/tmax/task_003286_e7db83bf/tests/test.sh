#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import signal
import stat
import subprocess
import time
import urllib.request
import uuid
import pytest

SOURCE = "/home/user/health_server.c"
BINARY = "/home/user/health_server"
SUPERVISOR = "/home/user/supervisor.sh"
DEPLOY = "/home/user/deploy.sh"
SUPERVISOR_PID = "/home/user/supervisor.pid"
SERVER_PID = "/home/user/server.pid"
SERVER_LOG = "/home/user/server.log"


def read_pid(path):
    with open(path, "r") as f:
        value = f.read().strip()
    assert value.isdigit(), f"{path} does not contain a valid PID"
    return int(value)


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def wait_for_pid(path, different_from=None, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            pid = read_pid(path)
            if pid != different_from and alive(pid):
                return pid
        except (OSError, AssertionError):
            pass
        time.sleep(0.05)
    pytest.fail(f"Timed out waiting for a live PID in {path}")


def assert_server_is_deployed_binary(pid, supervisor_pid):
    assert alive(pid), "PID in server.pid is not running"
    proc_exe = f"/proc/{pid}/exe"
    assert os.path.exists(proc_exe), "PID in server.pid has no executable"
    assert os.stat(proc_exe).st_dev == os.stat(BINARY).st_dev
    assert os.stat(proc_exe).st_ino == os.stat(BINARY).st_ino, \
        "PID in server.pid is not the deployed /home/user/health_server binary"
    with open(f"/proc/{pid}/status", "r") as f:
        status = f.read()
    match = re.search(r"^PPid:\s*(\d+)\s*$", status, re.MULTILINE)
    assert match and int(match.group(1)) == supervisor_pid, \
        "health_server is not a direct child of the supervisor"


def request_ok():
    req = urllib.request.Request("http://127.0.0.1:9090")
    with urllib.request.urlopen(req, timeout=2) as response:
        assert response.status == 200
        assert response.read().decode().strip() == "OK"


def traced_commands(stderr):
    commands = []
    for line in stderr.splitlines():
        stripped = line.lstrip()
        if not stripped.startswith("+"):
            continue
        text = stripped.lstrip("+").strip()
        try:
            words = shlex.split(text)
        except ValueError:
            continue
        if words:
            commands.append(words)
    return commands


def command_name(words):
    index = 0
    while index < len(words) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[index]):
        index += 1
    if index < len(words) and words[index] == "command":
        index += 1
    return (os.path.basename(words[index]), words[index + 1:]) if index < len(words) else ("", [])


def compile_output(args):
    for i, arg in enumerate(args):
        if arg == "-o" and i + 1 < len(args):
            return args[i + 1]
        if arg.startswith("-o") and len(arg) > 2:
            return arg[2:]
    return None


def mv_operands(args):
    result = []
    options_done = False
    for arg in args:
        if not options_done and arg == "--":
            options_done = True
        elif not options_done and arg.startswith("-"):
            continue
        else:
            result.append(arg)
    return result


def has_sigterm_to(commands, pid):
    for words in commands:
        name, args = command_name(words)
        if name != "kill" or str(pid) not in args:
            continue
        joined = " ".join(args).upper()
        if "-TERM" in joined or "-SIGTERM" in joined or "-15" in args:
            return True
        for i, arg in enumerate(args[:-1]):
            if arg == "-s" and args[i + 1].upper() in ("TERM", "SIGTERM"):
                return True
    return False


def test_files_exist_and_executable():
    assert os.path.isfile(SUPERVISOR), f"{SUPERVISOR} does not exist"
    assert os.access(SUPERVISOR, os.X_OK), f"{SUPERVISOR} is not executable"
    assert os.path.isfile(DEPLOY), f"{DEPLOY} does not exist"
    assert os.access(DEPLOY, os.X_OK), f"{DEPLOY} is not executable"


def test_health_server_c_has_loop():
    with open(SOURCE, "r") as f:
        content = f.read()
    assert any(keyword in content for keyword in ["while", "for", "goto"]), \
        "health_server.c does not appear to contain a loop"


def test_supervisor_and_deploy():
    with open(SOURCE, "r") as f:
        original_source = f.read()

    compile_proc = subprocess.run(
        ["gcc", SOURCE, "-o", BINARY], capture_output=True, text=True
    )
    assert compile_proc.returncode == 0, \
        f"Failed to compile health_server.c: {compile_proc.stderr}"

    for path in (SUPERVISOR_PID, SERVER_PID, SERVER_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    supervisor_proc = subprocess.Popen(
        [SUPERVISOR], preexec_fn=os.setsid,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )

    try:
        supervisor_pid = wait_for_pid(SUPERVISOR_PID, timeout=3)
        assert supervisor_pid == supervisor_proc.pid, \
            "supervisor.pid does not contain the running supervisor's PID"
        assert alive(supervisor_pid), "Supervisor exited"

        server_pid_1 = wait_for_pid(SERVER_PID, timeout=3)
        deadline = time.monotonic() + 2
        while not os.path.exists(SERVER_LOG) and time.monotonic() < deadline:
            time.sleep(0.05)
        assert os.path.isfile(SERVER_LOG), "/home/user/server.log was not created"
        assert stat.S_ISREG(os.stat(SERVER_LOG).st_mode), "server.log is not a regular file"
        assert_server_is_deployed_binary(server_pid_1, supervisor_pid)

        for _ in range(3):
            try:
                request_ok()
            except Exception as exc:
                pytest.fail(f"Failed to connect to health_server: {exc}")

        server_pid_after_requests = read_pid(SERVER_PID)
        assert server_pid_1 == server_pid_after_requests, \
            "Server PID changed after connections. It may have exited after a request."
        assert_server_is_deployed_binary(server_pid_after_requests, supervisor_pid)

        # Independently exercise automatic restart and the required delay.
        killed_at = time.monotonic()
        os.kill(server_pid_after_requests, signal.SIGKILL)
        time.sleep(0.55)
        assert read_pid(SERVER_PID) == server_pid_after_requests, \
            "Supervisor restarted the server without the required 1-second delay"
        server_pid_2 = wait_for_pid(SERVER_PID, different_from=server_pid_after_requests, timeout=4)
        assert time.monotonic() - killed_at >= 0.8, \
            "Supervisor restart delay is shorter than one second"
        assert_server_is_deployed_binary(server_pid_2, supervisor_pid)
        request_ok()

        # Add unpredictable startup output without changing the HTTP response. A valid
        # deploy must compile this updated source, replace the binary, and restart it.
        marker = "DEPLOY_" + uuid.uuid4().hex
        main_match = re.search(r"\bint\s+main\s*\([^)]*\)\s*\{", original_source)
        assert main_match, "Could not locate main() in health_server.c"
        injected = (
            original_source[:main_match.end()] +
            f'\n    fprintf(stdout, "{marker}_OUT\\n"); fflush(stdout);\n'
            f'    fprintf(stderr, "{marker}_ERR\\n"); fflush(stderr);\n' +
            original_source[main_match.end():]
        )
        with open(SOURCE, "w") as f:
            f.write(injected)

        old_binary_stat = os.stat(BINARY)
        deploy_res = subprocess.run(
            ["bash", "-x", DEPLOY], capture_output=True, text=True, timeout=15
        )
        assert deploy_res.returncode == 0, f"{DEPLOY} failed: {deploy_res.stderr}"

        commands = traced_commands(deploy_res.stderr)
        compile_temps = []
        for words in commands:
            name, args = command_name(words)
            if name in ("gcc", "cc") and SOURCE in args:
                output = compile_output(args)
                if output and os.path.abspath(output) != BINARY:
                    compile_temps.append(os.path.abspath(output))
        assert compile_temps, \
            "deploy.sh did not compile health_server.c to a temporary binary"

        used_atomic_mv = False
        for words in commands:
            name, args = command_name(words)
            if name != "mv":
                continue
            operands = mv_operands(args)
            if len(operands) >= 2:
                src = os.path.abspath(operands[-2])
                dst = os.path.abspath(operands[-1])
                if src in compile_temps and dst == BINARY:
                    used_atomic_mv = True
                    break
        assert used_atomic_mv, \
            "deploy.sh did not use mv to atomically replace health_server with its temporary binary"
        assert has_sigterm_to(commands, server_pid_2), \
            "deploy.sh did not send SIGTERM to the PID read from server.pid"

        new_binary_stat = os.stat(BINARY)
        assert (new_binary_stat.st_dev, new_binary_stat.st_ino) != \
               (old_binary_stat.st_dev, old_binary_stat.st_ino), \
            "Deployment did not replace the health_server file"

        server_pid_3 = wait_for_pid(SERVER_PID, different_from=server_pid_2, timeout=5)
        assert_server_is_deployed_binary(server_pid_3, supervisor_pid)

        deadline = time.monotonic() + 3
        log_content = ""
        while time.monotonic() < deadline:
            try:
                with open(SERVER_LOG, "r") as f:
                    log_content = f.read()
            except OSError:
                pass
            if marker + "_OUT" in log_content and marker + "_ERR" in log_content:
                break
            time.sleep(0.05)
        assert marker + "_OUT" in log_content, \
            "Server standard output was not forwarded to server.log"
        assert marker + "_ERR" in log_content, \
            "Server standard error was not forwarded to server.log"

        try:
            request_ok()
        except Exception as exc:
            pytest.fail(f"Failed to connect to health_server after deployment: {exc}")
        assert read_pid(SERVER_PID) == server_pid_3, \
            "Deployed server did not continue handling connections"

    finally:
        try:
            with open(SOURCE, "w") as f:
                f.write(original_source)
        except Exception:
            pass
        try:
            os.killpg(os.getpgid(supervisor_proc.pid), signal.SIGKILL)
        except Exception:
            pass
        try:
            if os.path.isfile(SERVER_PID):
                pid = read_pid(SERVER_PID)
                os.kill(pid, signal.SIGKILL)
        except Exception:
            pass

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
