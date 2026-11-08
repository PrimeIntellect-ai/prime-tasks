#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import socket
import stat
import subprocess
import tarfile
import threading

CPP_PATH = "/home/user/watchdog.cpp"
EXE_PATH = "/home/user/watchdog"
REBUILT_PATH = "/tmp/watchdog_from_source"
ALERT_LOG = "/home/user/alert.log"
BACKUP_FILE = "/home/user/data_backup.tar.gz"
APP_DATA = "/home/user/app_data"


def clean_outputs():
    for path in (ALERT_LOG, BACKUP_FILE):
        if os.path.exists(path):
            os.remove(path)


def assert_port_down():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(0.5)
    try:
        assert sock.connect_ex(("127.0.0.1", 9090)) != 0, \
            "Port 9090 is unexpectedly open before the test."
    finally:
        sock.close()


def run_down_test(exe_path, marker_name=None, marker_value=None, clean=True):
    assert_port_down()
    if clean:
        clean_outputs()

    marker_path = None
    if marker_name is not None:
        marker_path = os.path.join(APP_DATA, marker_name)
        with open(marker_path, "w") as f:
            f.write(marker_value)

    try:
        result = subprocess.run([exe_path], capture_output=True, timeout=15)
        assert result.returncode == 1, \
            f"Expected exit code 1 when service is down, got {result.returncode}."

        assert os.path.isfile(ALERT_LOG), f"{ALERT_LOG} was not created."
        with open(ALERT_LOG, "r") as f:
            lines = f.readlines()
        assert len(lines) > 0, f"{ALERT_LOG} is empty."
        assert lines[-1] == "[ALERT] Port 9090 is unreachable\n", \
            f"Incorrect log message in {ALERT_LOG}."

        assert os.path.isfile(BACKUP_FILE), f"{BACKUP_FILE} was not created."
        try:
            with tarfile.open(BACKUP_FILE, "r:gz") as tar:
                names = tar.getnames()
                found = any("app_data/metrics.txt" in name for name in names) or \
                        any("metrics.txt" in name for name in names)
                assert found, "Backup archive does not contain the expected metrics.txt file."

                if marker_name is not None:
                    matches = [m for m in tar.getmembers()
                               if os.path.basename(m.name) == marker_name and m.isfile()]
                    assert matches, "Backup does not contain the verifier-created data file."
                    extracted = tar.extractfile(matches[0])
                    assert extracted is not None
                    assert extracted.read() == marker_value.encode(), \
                        "The archived verifier-created file has incorrect contents."
        except tarfile.TarError:
            assert False, f"{BACKUP_FILE} is not a valid gzip-compressed tar archive."
    finally:
        if marker_path and os.path.exists(marker_path):
            os.remove(marker_path)


def run_up_test(exe_path):
    clean_outputs()
    server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_sock.bind(("127.0.0.1", 9090))
    server_sock.listen(8)

    stop_event = threading.Event()

    def accept_connections():
        server_sock.settimeout(0.5)
        while not stop_event.is_set():
            try:
                conn, _ = server_sock.accept()
                conn.close()
            except socket.timeout:
                continue
            except OSError:
                break

    thread = threading.Thread(target=accept_connections)
    thread.start()
    try:
        result = subprocess.run([exe_path], capture_output=True, timeout=10)
        assert result.returncode == 0, \
            f"Expected exit code 0 when service is up, got {result.returncode}."
        assert result.stdout == b"" and result.stderr == b"", \
            "The watchdog must terminate silently when the service is reachable."
        assert not os.path.exists(ALERT_LOG), \
            f"{ALERT_LOG} should not be created when service is up."
        assert not os.path.exists(BACKUP_FILE), \
            f"{BACKUP_FILE} should not be created when service is up."
    finally:
        stop_event.set()
        server_sock.close()
        thread.join(timeout=2)


def dynamic_symbols(path):
    outputs = []
    for args in (["nm", "-D", "-C", path], ["nm", "-C", path]):
        result = subprocess.run(args, capture_output=True, text=True)
        outputs.append(result.stdout + result.stderr)
    return "\n".join(outputs)


def test_watchdog_files_exist_and_are_native():
    assert os.path.isfile(CPP_PATH), f"Source file {CPP_PATH} does not exist."
    assert os.path.isfile(EXE_PATH), f"Executable file {EXE_PATH} does not exist."

    st = os.stat(EXE_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", \
            "The submitted watchdog must be a native compiled executable, not a script."
    assert os.path.getmtime(EXE_PATH) >= os.path.getmtime(CPP_PATH), \
        "The executable is older than its submitted C++ source."


def test_source_compiles_and_uses_required_native_apis():
    result = subprocess.run(
        ["g++", "-std=c++17", CPP_PATH, "-o", REBUILT_PATH],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, \
        f"watchdog.cpp does not compile with g++:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(REBUILT_PATH) and os.access(REBUILT_PATH, os.X_OK)
    with open(REBUILT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    symbols = dynamic_symbols(REBUILT_PATH)
    assert re.search(r"\bsocket(@|\b)", symbols), \
        "The C++ implementation does not call the POSIX socket API."
    assert re.search(r"\bconnect(@|\b)", symbols), \
        "The C++ implementation does not call POSIX connect()."
    assert re.search(r"\b(system|popen)(@|\b)", symbols), \
        "The C++ implementation does not internally execute a shell command."


def test_submitted_executable_original_down_behavior():
    run_down_test(EXE_PATH)


def test_submitted_executable_original_up_behavior():
    run_up_test(EXE_PATH)


def test_compiled_source_and_submitted_binary_under_repeated_states():
    assert os.path.isfile(REBUILT_PATH), "The source compilation test did not produce an executable."

    for exe_path in (EXE_PATH, REBUILT_PATH):
        states = ["up", "down", "up", "down"]
        random.SystemRandom().shuffle(states)
        for state in states:
            if state == "up":
                run_up_test(exe_path)
            else:
                marker_name = "verify_" + secrets.token_hex(8) + ".txt"
                marker_value = "backup-challenge-" + secrets.token_hex(24)
                run_down_test(exe_path, marker_name, marker_value)

        clean_outputs()
        run_down_test(exe_path, clean=False)
        run_down_test(exe_path, clean=False)
        with open(ALERT_LOG, "r") as f:
            assert f.readlines() == [
                "[ALERT] Port 9090 is unreachable\n",
                "[ALERT] Port 9090 is unreachable\n",
            ], "Each failed check must append exactly one required alert line."

    clean_outputs()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
