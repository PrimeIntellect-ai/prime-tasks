#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import time
import socket
import secrets
import shutil
import signal
import subprocess
import threading
from pathlib import Path

import pytest


def kill_net_sim():
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmdline = (entry / 'cmdline').read_bytes().replace(b'\x00', b' ')
            if b'/home/user/net_sim.py' in cmdline:
                os.kill(int(entry.name), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.2)


def test_config_symlink():
    symlink_path = "/home/user/config"
    target_path = "/home/user/capacity-config"

    assert os.path.islink(symlink_path), f"'{symlink_path}' is not a symbolic link."
    actual_target = os.readlink(symlink_path)
    resolved_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), actual_target))
    assert resolved_target == target_path, (
        f"Symlink '{symlink_path}' points to '{actual_target}', expected it to resolve to '{target_path}'."
    )


def test_planner_executable():
    planner_bin = "/home/user/planner"
    assert os.path.isfile(planner_bin), f"Compiled binary '{planner_bin}' is missing."
    st = os.stat(planner_bin)
    assert bool(st.st_mode & stat.S_IXUSR), f"'{planner_bin}' is not executable."
    with open(planner_bin, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"'{planner_bin}' is not a compiled ELF executable."


def test_start_services_script():
    script_path = "/home/user/start_services.sh"
    assert os.path.isfile(script_path), f"Script '{script_path}' is missing."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"'{script_path}' is not executable."

    text = Path(script_path).read_text()
    assert re.search(r'(^|\n)\s*set\s+[^\n]*(?:-e|errexit)', text), "Supervisor does not enable robust error handling."
    assert re.search(r'python3\s+/home/user/net_sim\.py\s*&', text), "Supervisor does not start the required daemon in the background."
    assert re.search(r'\b(?:while|until)\b', text), "Supervisor does not contain an active polling loop."
    assert '8888' in text and '127.0.0.1' in text, "Supervisor does not poll the required address and port."
    assert re.search(r'(?:\bnc\b|/dev/tcp|socket|connect)', text), "Supervisor does not appear to perform a port-availability check."
    assert re.search(r'/home/user/planner[^\n]*>\s*/home/user/planner_output\.log', text), (
        "Supervisor does not execute planner with stdout redirected to planner_output.log."
    )


def test_planner_output_log():
    log_path = "/home/user/planner_output.log"
    assert os.path.isfile(log_path), f"Log file '{log_path}' is missing. Did you run the start_services.sh script?"
    with open(log_path, "r") as f:
        content = f.read()
    expected_content = "Connection successful. Configuration loaded: CAPACITY_LIMIT=8500\n"
    assert content == expected_content, (
        f"Log file '{log_path}' content does not match expected output.\n"
        f"Expected: {expected_content!r}\nGot: {content!r}"
    )


def test_source_is_fixed_and_compiles():
    source_path = Path('/home/user/planner.c')
    assert source_path.is_file(), "planner.c is missing."
    source = source_path.read_text()
    uncommented = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    assert re.search(r'#\s*include\s*<sys/socket\.h>', uncommented), "sys/socket.h was not added."
    assert re.search(r'#\s*include\s*<arpa/inet\.h>', uncommented), "arpa/inet.h was not added."
    assert re.search(r'\breturn\s+0\s*;', uncommented), "main does not contain the required successful return statement."
    result = subprocess.run(
        ['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', str(source_path), '-o', '/tmp/planner_rebuilt'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert result.returncode == 0, f"planner.c does not compile cleanly:\n{result.stderr}"


def test_compiled_planner_really_reads_config_and_connects():
    kill_net_sim()
    config = Path('/home/user/capacity-config/settings.conf')
    original = config.read_bytes()
    value = 'CAPACITY_LIMIT=' + str(100000 + secrets.randbelow(800000))
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(('127.0.0.1', 8888))
    listener.listen(1)

    accepted = []
    def accept_once():
        conn, _ = listener.accept()
        accepted.append(True)
        conn.close()

    thread = threading.Thread(target=accept_once, daemon=True)
    thread.start()
    try:
        config.write_text(value + '\n')
        result = subprocess.run(
            ['/home/user/planner'], text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=5
        )
        assert result.returncode == 0, f"planner failed when a daemon was available: {result.stderr}"
        assert result.stdout == f"Connection successful. Configuration loaded: {value}\n"
        thread.join(timeout=2)
        assert accepted, "planner did not connect to port 8888."
    finally:
        config.write_bytes(original)
        listener.close()


def test_supervisor_waits_for_readiness_and_runs_planner_with_redirection():
    planner = Path('/home/user/planner')
    daemon = Path('/home/user/net_sim.py')
    log = Path('/home/user/planner_output.log')
    planner_bytes, planner_mode = planner.read_bytes(), planner.stat().st_mode
    daemon_bytes, daemon_mode = daemon.read_bytes(), daemon.stat().st_mode
    log_existed = log.exists()
    log_bytes = log.read_bytes() if log_existed else b''
    token = 'SUPERVISOR_' + secrets.token_hex(12)

    helper_source = f'''#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
int main(void) {{
    int s = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in a = {{0}};
    a.sin_family = AF_INET; a.sin_port = htons(8888);
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    if (s < 0 || connect(s, (struct sockaddr *)&a, sizeof(a)) != 0) return 41;
    puts("{token}"); close(s); return 0;
}}
'''
    Path('/tmp/verifier_planner.c').write_text(helper_source)
    subprocess.run(['gcc', '/tmp/verifier_planner.c', '-o', '/tmp/verifier_planner'], check=True)

    instrumented_daemon = '''import socket, time
with open('/tmp/verifier_delay') as f:
    delay = float(f.read())
time.sleep(delay)
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 8888))
s.listen(1)
c, _ = s.accept()
c.close()
s.close()
'''

    try:
        kill_net_sim()
        shutil.copyfile('/tmp/verifier_planner', planner)
        os.chmod(planner, 0o755)
        daemon.write_text(instrumented_daemon)
        os.chmod(daemon, 0o755)

        timings = []
        for delay in (2.4, 0.2):
            Path('/tmp/verifier_delay').write_text(str(delay))
            if log.exists():
                log.unlink()
            start = time.monotonic()
            result = subprocess.run(
                ['/home/user/start_services.sh'], text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=7
            )
            elapsed = time.monotonic() - start
            timings.append(elapsed)
            assert result.returncode == 0, f"Supervisor failed: {result.stderr}"
            assert log.is_file(), "Supervisor did not create planner_output.log."
            assert log.read_text() == token + '\n', "Supervisor did not redirect the executed planner's stdout to the log."

        assert timings[0] >= 2.0, "Supervisor started planner before the delayed daemon was ready."
        assert timings[1] < 1.8, "Supervisor appears to use a fixed startup sleep instead of active port polling."
    finally:
        kill_net_sim()
        planner.write_bytes(planner_bytes)
        os.chmod(planner, stat.S_IMODE(planner_mode))
        daemon.write_bytes(daemon_bytes)
        os.chmod(daemon, stat.S_IMODE(daemon_mode))
        if log_existed:
            log.write_bytes(log_bytes)
        elif log.exists():
            log.unlink()

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
