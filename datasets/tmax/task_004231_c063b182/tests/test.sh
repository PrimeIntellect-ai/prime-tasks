#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import runpy
import shutil
import signal
import socket
import subprocess
import time

import pytest
import requests

APP_DIR = "/app/metrics-aggregator-1.2.0"
SETUP_SCRIPT = "/home/user/setup_and_run.py"
DB_SCRIPT = "/home/user/db_service.py"
BACKUP = "/home/user/backups/data_backup.db"
DB_FILE = "/home/user/data.db"


def proc_info(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        cwd = os.readlink(f"/proc/{pid}/cwd")
        with open(f"/proc/{pid}/stat") as f:
            ppid = int(f.read().split()[3])
        return argv, cwd, ppid
    except (OSError, ValueError, IndexError):
        return None


def all_processes():
    result = {}
    for name in os.listdir("/proc"):
        if name.isdigit():
            info = proc_info(int(name))
            if info:
                result[int(name)] = info
    return result


def socket_owners(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    owners = set()
    if not inodes:
        return owners
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(name))
                    break
        except OSError:
            pass
    return owners


def terminate(pids):
    pids = {p for p in pids if p not in (1, os.getpid(), os.getppid())}
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.3)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def clean_old_services():
    victims = socket_owners(8080) | socket_owners(9090)
    for pid, (argv, cwd, ppid) in all_processes().items():
        joined = " ".join(argv)
        if (SETUP_SCRIPT in argv or DB_SCRIPT in argv or
                os.path.join(APP_DIR, "server.py") in argv or
                (cwd == APP_DIR and ("make run" in joined or "server.py" in joined))):
            victims.add(pid)
    terminate(victims)


def is_descendant(pid, ancestor, processes):
    seen = set()
    while pid in processes and pid not in seen:
        if pid == ancestor:
            return True
        seen.add(pid)
        pid = processes[pid][2]
    return False


def test_makefile_fixed():
    path = os.path.join(APP_DIR, "Makefile")
    assert os.path.isfile(path), f"Makefile not found at {path}"

    with open(path, "r") as f:
        lines = f.readlines()

    run_target_idx = -1
    for i, line in enumerate(lines):
        if line.startswith("run:"):
            run_target_idx = i
            break

    assert run_target_idx != -1, f"Makefile at {path} is missing the 'run:' target."

    found_command = False
    for i in range(run_target_idx + 1, len(lines)):
        line = lines[i]
        if line.strip():
            assert line.startswith("\t"), "Makefile 'run:' target commands must be indented with a tab, found spaces."
            found_command = True
            break
    assert found_command, "Makefile 'run:' target has no command."

    result = subprocess.run(["make", "-n", "run"], cwd=APP_DIR, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert result.returncode == 0, f"The run target is not valid: {result.stderr}"
    assert "server.py" in result.stdout, "The run target does not run the vendored metrics server."


def test_config_fixed():
    path = os.path.join(APP_DIR, "config.py")
    assert os.path.isfile(path), f"Config file not found at {path}"

    with open(path, "r") as f:
        content = f.read()

    assert "8080" in content, f"Expected DB_PORT to be set to 8080 in {path}."
    assert "8081" not in content, f"Incorrect port 8081 is still present in {path}."
    values = runpy.run_path(path)
    assert values.get("DB_PORT") == 8080, "config.py does not actually define DB_PORT as integer 8080."


def test_setup_script_starts_ordered_real_services():
    assert os.path.isfile(SETUP_SCRIPT), f"Required startup script {SETUP_SCRIPT} does not exist."
    with open(SETUP_SCRIPT, "rb") as f:
        compile(f.read(), SETUP_SCRIPT, "exec")

    clean_old_services()
    shutil.rmtree("/home/user/backups", ignore_errors=True)

    # The real vendored run target must fail when its required backend is absent.
    probe = subprocess.Popen(["make", "run"], cwd=APP_DIR, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        rc = probe.wait(timeout=3)
        assert rc != 0, "make run stayed healthy without the required database backend."
    except subprocess.TimeoutExpired:
        os.killpg(probe.pid, signal.SIGKILL)
        probe.wait()
        pytest.fail("make run did not exit when the database backend was unavailable.")

    with open(DB_SCRIPT, "rb") as f:
        original_db = f.read()
    # Delay the supplied backend so a script that starts make immediately is exposed.
    delayed_db = b"import time as _verifier_time\n_verifier_time.sleep(1.5)\n" + original_db
    with open(DB_SCRIPT, "wb") as f:
        f.write(delayed_db)

    launcher = None
    try:
        launcher = subprocess.Popen(["python3", SETUP_SCRIPT], cwd="/home/user",
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 12
        saw_db = False
        saw_make = False
        saw_server = False
        make_pids = set()
        server_pids = set()

        while time.time() < deadline:
            processes = all_processes()
            db_pids = {pid for pid, (argv, cwd, ppid) in processes.items() if DB_SCRIPT in argv}
            current_make = {
                pid for pid, (argv, cwd, ppid) in processes.items()
                if cwd == APP_DIR and argv and os.path.basename(argv[0]) == "make" and "run" in argv[1:]
            }
            current_server = {
                pid for pid, (argv, cwd, ppid) in processes.items()
                if cwd == APP_DIR and os.path.join(APP_DIR, "server.py") in argv
            }
            db_owners = socket_owners(8080)

            # A make process observed before the delayed supplied DB owns its socket
            # proves the required TCP-health-check ordering was not implemented.
            if current_make and not (db_pids & db_owners):
                pytest.fail("make run was started before db_service.py was listening on TCP port 8080.")

            if db_pids & db_owners:
                saw_db = True
            make_pids |= current_make
            server_pids |= current_server
            saw_make = saw_make or bool(current_make)
            saw_server = saw_server or bool(current_server)

            if saw_db and saw_make and saw_server and socket_owners(9090):
                break
            time.sleep(0.05)

        processes = all_processes()
        db_pids = {pid for pid, (argv, cwd, ppid) in processes.items() if DB_SCRIPT in argv}
        make_pids |= {
            pid for pid, (argv, cwd, ppid) in processes.items()
            if cwd == APP_DIR and argv and os.path.basename(argv[0]) == "make" and "run" in argv[1:]
        }
        server_pids |= {
            pid for pid, (argv, cwd, ppid) in processes.items()
            if cwd == APP_DIR and os.path.join(APP_DIR, "server.py") in argv
        }

        assert os.path.isdir("/home/user/backups"), "setup_and_run.py did not create the backups directory."
        assert db_pids & socket_owners(8080), "The supplied db_service.py is not the process listening on port 8080."
        assert make_pids, "setup_and_run.py did not execute 'make run' in the vendored package."
        assert server_pids & socket_owners(9090), "The vendored server.py is not the process listening on port 9090."
        assert any(is_descendant(server, make, processes) for server in server_pids for make in make_pids), \
            "The running metrics server was not launched by the required make run process."
    finally:
        with open(DB_SCRIPT, "wb") as f:
            f.write(original_db)


def test_health_endpoint():
    url = "http://127.0.0.1:9090/health"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to health endpoint at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {url} is not valid JSON. Content: {response.text}")
    assert data == {"status": "ok"}, f"Expected JSON {{'status': 'ok'}}, got {data}"

    missing = requests.get("http://127.0.0.1:9090/verifier-missing", timeout=5)
    assert missing.status_code == 404, "The vendored server must return 404 for unknown paths."


def test_metrics_endpoint():
    url = "http://127.0.0.1:9090/metrics"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to metrics endpoint at {url}: {e}")
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"


def wait_for_backup(expected, previous_mtime=None, timeout=3.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open(BACKUP, "rb") as f:
                data = f.read()
            mtime = os.path.getmtime(BACKUP)
            if data == expected and (previous_mtime is None or mtime > previous_mtime):
                return mtime
        except OSError:
            pass
        time.sleep(0.05)
    pytest.fail("The periodic backup did not copy the current database contents within 3 seconds.")


def test_backup_exists_and_updates():
    assert os.path.isfile(BACKUP), f"Backup file {BACKUP} does not exist."
    mtime1 = os.path.getmtime(BACKUP)

    first = os.urandom(97)
    with open(DB_FILE, "wb") as f:
        f.write(first)
    os.utime(DB_FILE, None)
    mtime2 = wait_for_backup(first, mtime1)
    assert mtime2 > mtime1, f"Backup file {BACKUP} was not updated within 3 seconds. Ensure the backup task runs every 2 seconds."

    second = os.urandom(131)
    with open(DB_FILE, "wb") as f:
        f.write(second)
    os.utime(DB_FILE, None)
    mtime3 = wait_for_backup(second, mtime2)
    assert mtime3 > mtime2, "The backup task did not continue running periodically."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
