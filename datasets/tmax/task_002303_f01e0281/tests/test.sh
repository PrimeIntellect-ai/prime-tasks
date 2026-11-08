#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import time
import urllib.request
import pytest


def _http_get(url):
    with urllib.request.urlopen(url, timeout=2) as req:
        return req.status, req.read().decode('utf-8')


def _ssh_listener_ports():
    """Return TCP listen ports whose socket FDs are owned by an ssh process."""
    socket_inodes = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        proc = f'/proc/{entry}'
        try:
            exe = os.path.basename(os.readlink(f'{proc}/exe'))
            if exe != 'ssh':
                continue
            for fd in os.listdir(f'{proc}/fd'):
                try:
                    target = os.readlink(f'{proc}/fd/{fd}')
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match:
                    socket_inodes.add(match.group(1))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue

    ports = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == '0A' and fields[9] in socket_inodes:
                        ports.add(int(fields[1].rsplit(':', 1)[1], 16))
        except FileNotFoundError:
            pass
    return ports


def test_port_forwarding():
    """Check that SSH owns both forwarding listeners and the complete chain works."""
    ports = _ssh_listener_ports()
    assert {8001, 8002}.issubset(ports), \
        f"Ports 8001 and 8002 are not both listening sockets owned by SSH processes: {ports}"

    try:
        status, body = _http_get('http://127.0.0.1:8001/')
        assert status == 200 and body == 'DB_OK', f"Unexpected DB tunnel response: {status} {body!r}"

        status, body = _http_get('http://127.0.0.1:8002/')
        assert status == 200 and body == 'Backend->DB_OK', \
            f"Unexpected backend tunnel response: {status} {body!r}"

        status, body = _http_get('http://127.0.0.1:9003/')
        assert status == 200
        assert body == 'Frontend->Backend->DB_OK', f"Unexpected response from frontend: {body}"
    except Exception as e:
        pytest.fail(f"Failed to validate SSH forwarding and service communication: {e}")


def test_tmpfs_mount():
    """Check if /app/logs is a tmpfs mount with a maximum size of 50M."""
    try:
        out = subprocess.check_output('mount', shell=True).decode('utf-8')
        mount_lines = [l for l in out.splitlines() if '/app/logs' in l and 'tmpfs' in l]
        assert len(mount_lines) > 0, "tmpfs is not mounted at /app/logs"

        mount_line = mount_lines[0]
        assert 'size=50M' in mount_line or 'size=51200k' in mount_line or 'size=52428800' in mount_line, \
            f"Size 50M constraint not found in mount options: {mount_line}"
    except subprocess.CalledProcessError:
        pytest.fail("Failed to execute mount command")


def _git_as_user(*args, check=True):
    return subprocess.run(
        ['sudo', '-u', 'user', '-H', 'git', '-C', '/home/user/workspace', *args],
        check=check, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )


def test_git_automation():
    """Push a fresh source revision and prove the post-receive hook rebuilds it."""
    repo = '/home/user/monitor.git'
    workspace = '/home/user/workspace'
    source = f'{workspace}/alert_parser.c'
    hook_path = f'{repo}/hooks/post-receive'
    exe_path = '/app/bin/alert_parser'

    assert subprocess.check_output(
        ['git', '--git-dir', repo, 'rev-parse', '--is-bare-repository'], text=True
    ).strip() == 'true', f"{repo} is not a bare Git repository"
    assert os.path.isfile(hook_path), f"Git hook not found at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"Git hook at {hook_path} is not executable"
    assert os.path.isfile(source), f"C source not found at {source}"
    assert os.path.isfile(exe_path), f"Compiled executable not found at {exe_path}"
    assert os.access(exe_path, os.X_OK), f"File at {exe_path} is not executable"

    marker = f"VERIFIER_BUILD_{secrets.token_hex(16)}"
    with open(source, 'a') as f:
        f.write(
            '\n#if defined(__GNUC__)\n'
            '__attribute__((used))\n'
            '#endif\n'
            f'static const char verifier_build_marker[] = "{marker}";\n'
        )

    _git_as_user('config', 'user.name', 'Verifier')
    _git_as_user('config', 'user.email', 'verifier@localhost')
    _git_as_user('add', 'alert_parser.c')
    committed = _git_as_user('commit', '-m', marker, '--', 'alert_parser.c', check=False)
    assert committed.returncode == 0, f"Could not commit verifier source change: {committed.stderr}"
    branch = _git_as_user('branch', '--show-current').stdout.strip()
    assert branch, "Workspace is not on a branch"

    backup = f'/tmp/alert_parser.pre_push.{secrets.token_hex(8)}'
    os.replace(exe_path, backup)
    pushed = _git_as_user('push', 'origin', f'HEAD:refs/heads/{branch}', check=False)
    assert pushed.returncode == 0, f"Push failed or post-receive hook failed: {pushed.stderr}"

    deadline = time.monotonic() + 5
    while time.monotonic() < deadline and not os.path.isfile(exe_path):
        time.sleep(0.05)
    assert os.path.isfile(exe_path), "The post-receive hook did not create /app/bin/alert_parser"
    assert os.access(exe_path, os.X_OK), f"File at {exe_path} is not executable"
    with open(exe_path, 'rb') as f:
        binary = f.read()
    assert binary.startswith(b'\x7fELF'), "Hook output is not a compiled ELF executable"
    assert marker.encode() in binary, "Hook output was not rebuilt from the newly pushed C source"


def test_final_output_exists_and_is_correct():
    """Check that the historical log was processed into the requested output file."""
    output_path = '/app/logs/alerts.txt'
    assert os.path.isfile(output_path), "Final output /app/logs/alerts.txt is missing"
    with open(output_path) as f:
        actual = f.read().split()
    assert actual == ['D4E5F6', 'G7H8I9'], f"Incorrect historical alerts output: {actual}"


def test_c_parser_performance_and_accuracy():
    """Evaluate the C parser on a runtime-randomized one-million-line log."""
    exe_path = '/app/bin/alert_parser'
    assert os.path.isfile(exe_path), f"Executable missing at {exe_path}"

    nonce = secrets.token_hex(12)
    state = secrets.randbits(64)
    test_log = f'/tmp/massive_test_{secrets.token_hex(8)}.log'
    expected_txids = set()

    with open(test_log, 'w') as f:
        for i in range(1_000_000):
            state = (state * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
            txid = f'T{nonce}_{i:06x}_{state & 0xffff:04x}'
            if ((state >> 17) % 20) == 0:
                time_ms = 501 + ((state >> 32) % 5000)
                expected_txids.add(txid)
            else:
                time_ms = (state >> 32) % 501
            status = 200 + ((state >> 8) % 5)
            f.write(f'[2023-10-12T10:00:00] txid={txid} status={status} time={time_ms}ms\n')

    start_time = time.time()
    try:
        out = subprocess.check_output([exe_path, test_log]).decode('utf-8')
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Executable failed to run: {e}")
    exec_time = time.time() - start_time

    output_items = out.split()
    actual_txids = set(output_items)
    missing = expected_txids - actual_txids
    extra = actual_txids - expected_txids
    assert not missing and not extra, "Precision and recall are not exactly 1.0 (missing or extra txids found)"
    assert len(output_items) == len(expected_txids), "Parser emitted duplicate or malformed output entries"
    assert exec_time <= 0.2, f"Execution time {exec_time:.3f}s exceeds the threshold of 0.2s"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
