#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import subprocess
import time


def listener_pids(port):
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

    result = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def proc_info(pid):
    try:
        exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
        return exe, cmdline
    except (OSError, FileNotFoundError, ProcessLookupError):
        return "", ""


def kill_matching_processes(needles):
    victims = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        _, cmdline = proc_info(int(entry))
        if cmdline and any(needle in cmdline for needle in needles):
            victims.append(int(entry))
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in victims:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.3)


def stop_group(proc):
    if proc is None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_nginx_config_fixed():
    nginx_conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(nginx_conf_path), f"Missing Nginx config: {nginx_conf_path}"
    with open(nginx_conf_path, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:8081;" in content or "proxy_pass http://localhost:8081;" in content, \
        "Nginx config does not have the corrected proxy_pass port 8081."


def test_expect_script_exists():
    path = "/home/user/start_backend.exp"
    assert os.path.isfile(path), f"Missing expect script: {path}"
    assert os.path.getsize(path) > 0, "Expect script is empty."


def test_supervisor_script_exists():
    path = "/home/user/supervisor.sh"
    assert os.path.isfile(path), f"Missing supervisor script: {path}"
    assert os.path.getsize(path) > 0, "Supervisor script is empty."


def test_verification_log_content():
    log_path = "/home/user/verification.log"
    assert os.path.isfile(log_path), f"Missing verification log: {log_path}"
    with open(log_path, "r") as f:
        content = f.read()
    occurrences = content.count("OK_BACKEND_ACTIVE")
    assert occurrences >= 5, f"Expected at least 5 occurrences of 'OK_BACKEND_ACTIVE' in {log_path}, found {occurrences}."


def test_nginx_listening():
    try:
        output = subprocess.check_output(["ss", "-tln"], text=True)
        assert ":8080 " in output, "Nginx does not appear to be listening on port 8080."
    except FileNotFoundError:
        pass


def test_socat_listening():
    try:
        output = subprocess.check_output(["ss", "-tln"], text=True)
        assert ":9000 " in output, "socat does not appear to be listening on port 9000."
    except FileNotFoundError:
        pass


def test_socat_process_running():
    try:
        output = subprocess.check_output(["ps", "aux"], text=True)
        assert "socat" in output, "socat process is not running."
    except Exception:
        pass


def test_zz_artifacts_and_stack_behave_end_to_end():
    expect_path = "/home/user/start_backend.exp"
    supervisor_path = "/home/user/supervisor.sh"

    # The listeners left by the agent must really be nginx and a correctly
    # directed socat process, rather than arbitrary processes bound to the ports.
    nginx_owners = [proc_info(pid) for pid in listener_pids(8080)]
    assert any(exe.startswith("nginx") for exe, _ in nginx_owners), \
        f"Port 8080 is not owned by nginx: {nginx_owners}"

    socat_owners = [proc_info(pid) for pid in listener_pids(9000)]
    assert any(exe == "socat" and "9000" in cmd and "8080" in cmd
               for exe, cmd in socat_owners), \
        f"Port 9000 is not a socat forward to port 8080: {socat_owners}"

    with open(expect_path, errors="replace") as f:
        expect_source = f.read()
    assert re.search(r"\bspawn\s+(?:--\s+)?/home/user/backend\.sh\b", expect_source), \
        "Expect script does not spawn /home/user/backend.sh."
    assert "Enter passphrase to unlock server: " in expect_source, \
        "Expect script does not wait for the required prompt."
    assert "admin_secret_99" in expect_source, \
        "Expect script does not contain the required passphrase."

    # Stop old copies so they cannot satisfy the behavioral probes.
    kill_matching_processes([supervisor_path, expect_path, "/home/user/backend.sh"])

    # Execute the submitted expect program against an instrumented backend.
    backend_path = "/home/user/backend.sh"
    backend_backup = "/tmp/backend.sh.verifier-backup"
    proof = "/tmp/expect-proof"
    if os.path.exists(proof):
        os.unlink(proof)
    os.replace(backend_path, backend_backup)
    expect_proc = None
    try:
        with open(backend_path, "w") as f:
            f.write("#!/bin/bash\n"
                    "sleep 0.3\n"
                    "printf 'Enter passphrase to unlock server: '\n"
                    "IFS= read -r pass\n"
                    "if [ \"$pass\" = 'admin_secret_99' ]; then echo accepted > /tmp/expect-proof; else exit 41; fi\n"
                    "sleep 30\n")
        os.chmod(backend_path, 0o755)
        expect_proc = subprocess.Popen(
            ["expect", expect_path], stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True)
        deadline = time.time() + 5
        while time.time() < deadline and not os.path.exists(proof) and expect_proc.poll() is None:
            time.sleep(0.05)
        assert os.path.exists(proof), \
            "Executing the expect script did not answer the backend prompt correctly."
        assert expect_proc.poll() is None, \
            "The expect script did not retain control of the running backend."
    finally:
        stop_group(expect_proc)
        try:
            os.unlink(backend_path)
        except FileNotFoundError:
            pass
        os.replace(backend_backup, backend_path)

    # Replace only the expect target temporarily and execute the submitted
    # supervisor. A real infinite restart loop must invoke it repeatedly.
    expect_backup = "/tmp/start_backend.exp.verifier-backup"
    counter = "/tmp/supervisor-restarts"
    if os.path.exists(counter):
        os.unlink(counter)
    os.replace(expect_path, expect_backup)
    supervisor_proc = None
    try:
        with open(expect_path, "w") as f:
            f.write("#!/usr/bin/expect -f\n"
                    "set out [open /tmp/supervisor-restarts a]\n"
                    "puts $out restart\n"
                    "close $out\n"
                    "after 100\n"
                    "exit 1\n")
        os.chmod(expect_path, 0o755)
        supervisor_proc = subprocess.Popen(
            ["bash", supervisor_path], stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True)
        deadline = time.time() + 5
        restarts = 0
        while time.time() < deadline:
            try:
                with open(counter) as f:
                    restarts = len(f.readlines())
            except FileNotFoundError:
                restarts = 0
            if restarts >= 3:
                break
            if supervisor_proc.poll() is not None:
                break
            time.sleep(0.05)
        assert supervisor_proc.poll() is None, "Supervisor exited instead of running continuously."
        assert restarts >= 3, f"Supervisor did not restart the expect script repeatedly (saw {restarts} starts)."
    finally:
        stop_group(supervisor_proc)
        try:
            os.unlink(expect_path)
        except FileNotFoundError:
            pass
        os.replace(expect_backup, expect_path)

    # Rebuild the complete stack from the submitted artifacts, then make five
    # successful requests. This crosses the backend's two-request crash limit.
    subprocess.run(["nginx", "-c", "/home/user/nginx.conf", "-p", "/home/user/", "-s", "stop"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    kill_matching_processes(["nginx", "socat", supervisor_path, expect_path, backend_path])

    supervisor_proc = subprocess.Popen(
        ["bash", supervisor_path], stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True)
    socat_proc = None
    try:
        nginx_start = subprocess.run(
            ["nginx", "-c", "/home/user/nginx.conf", "-p", "/home/user/"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert nginx_start.returncode == 0, f"Nginx failed to start: {nginx_start.stderr}"

        socat_proc = subprocess.Popen(
            ["socat", "TCP-LISTEN:9000,reuseaddr,fork", "TCP:127.0.0.1:8080"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

        responses = []
        for request_number in range(5):
            deadline = time.time() + 10
            response = ""
            while time.time() < deadline:
                run = subprocess.run(
                    ["curl", "-sS", "--max-time", "2", "http://127.0.0.1:9000"],
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                if run.returncode == 0 and run.stdout == "OK_BACKEND_ACTIVE":
                    response = run.stdout
                    break
                time.sleep(0.15)
            assert response == "OK_BACKEND_ACTIVE", \
                f"End-to-end request {request_number + 1} did not reach the backend."
            responses.append(response)

        assert responses == ["OK_BACKEND_ACTIVE"] * 5
        assert supervisor_proc.poll() is None, "Supervisor stopped during end-to-end requests."
        assert socat_proc.poll() is None, "Socat stopped during end-to-end requests."
    except Exception:
        stop_group(socat_proc)
        stop_group(supervisor_proc)
        raise

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
