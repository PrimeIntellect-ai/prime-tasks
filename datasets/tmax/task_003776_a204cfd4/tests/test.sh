#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shutil
import signal
import subprocess
import tempfile
import time
from pathlib import Path

FILTER_BIN = Path("/home/user/alert_filter")
FILTER_SOURCE = Path("/home/user/alert_filter.c")
SUPERVISOR = Path("/home/user/supervise.sh")


def run_filter(content):
    return subprocess.run(
        [str(FILTER_BIN)], input=content, text=True, capture_output=True, timeout=5
    )


def test_alert_filter_exists_and_executable():
    filter_path = FILTER_BIN
    assert filter_path.exists(), f"Expected compiled binary {filter_path} does not exist."
    assert filter_path.is_file(), f"Expected {filter_path} to be a file."
    assert os.access(filter_path, os.X_OK), f"Expected {filter_path} to be executable."
    assert FILTER_SOURCE.exists() and FILTER_SOURCE.is_file(), \
        f"Expected C source file {FILTER_SOURCE} does not exist."
    assert filter_path.read_bytes()[:4] == b"\x7fELF", \
        f"Expected {filter_path} to be a compiled executable."


def test_alert_filter_corpus():
    clean_dir = Path("/app/corpus/clean")
    evil_dir = Path("/app/corpus/evil")
    filter_bin = str(FILTER_BIN)

    clean_fails = []
    clean_total = 0
    if clean_dir.exists():
        for file_path in clean_dir.iterdir():
            if file_path.is_file():
                clean_total += 1
                with open(file_path, "r") as f:
                    content = f.read()
                proc = subprocess.run([filter_bin], input=content, text=True, capture_output=True)
                if proc.stdout != content:
                    clean_fails.append(file_path.name)

    evil_fails = []
    evil_total = 0
    if evil_dir.exists():
        for file_path in evil_dir.iterdir():
            if file_path.is_file():
                evil_total += 1
                with open(file_path, "r") as f:
                    content = f.read()
                proc = subprocess.run([filter_bin], input=content, text=True, capture_output=True)
                if proc.stdout != "":
                    evil_fails.append(file_path.name)

    error_messages = []
    if clean_fails:
        error_messages.append(f"{len(clean_fails)} of {clean_total} clean modified/rejected. Offending: {', '.join(clean_fails)}")
    if evil_fails:
        error_messages.append(f"{len(evil_fails)} of {evil_total} evil bypassed. Offending: {', '.join(evil_fails)}")

    assert not error_messages, "Corpus validation failed: " + "; ".join(error_messages)


def test_alert_filter_generated_stream_and_long_lines():
    nonce = secrets.token_hex(18)
    needle = "connect() to unix:/app/run/upstream.sock failed (111: Connection refused)"

    valid = [
        f"2026/09/11 01:02:03 [error] 91#91: *{nonce[:5]} {needle}, client: 10.2.3.4, server: local\n",
        f"1999/01/02 23:59:58 [error] 7#0: *42 upstream-{nonce} {needle}\n",
        f"2037/12/31 00:00:00 [error] 876#2: {needle}; marker={nonce}\n",
        f"2024/02/29 12:34:56 [error] 1#1: *8 {needle}, context: " + (nonce * 7000) + "\n",
    ]

    invalid = [
        f"2026/09/11 01:02:03 [info] 91#91: *1 {needle} marker={nonce}\n",
        f"2026/09/11 01:02:03 [warn] 91#91: *1 {needle} marker={nonce}\n",
        f"2026/09/11 01:02:03 [error] 91#91: *1 connect() to unix:/app/run/other-{nonce}.sock failed (111: Connection refused)\n",
        f"2026/09/11 01:02:03 [error] 91#91: *1 connect() to unix:/app/run/upstream.sock failed (13: Permission denied) marker={nonce}\n",
        f"2026/09/11 01:02:03 [error] 91#91: unrelated upstream failure marker={nonce}\n",
        f"127.0.0.1 - - [11/Sep/2026:01:02:03 +0000] \"GET /{nonce}/[error]/{needle} HTTP/1.1\" 404 12 \"-\" \"browser\"\n",
        f"192.0.2.44 - user [11/Sep/2026:01:02:04 +0000] \"GET / HTTP/1.1\" 200 3 \"-\" \"agent-{nonce} [error] {needle}\"\n",
    ]

    records = [(line, line) for line in valid] + [(line, "") for line in invalid]
    random.SystemRandom().shuffle(records)
    content = "".join(line for line, _ in records)
    expected = "".join(output for _, output in records)

    proc = run_filter(content)
    assert proc.returncode == 0, f"Filter exited with status {proc.returncode}: {proc.stderr}"
    assert proc.stdout == expected, "Filter failed generated mixed-stream validation."

    final_valid = f"2028/03/04 05:06:07 [error] 3#4: *9 {needle}, eof={nonce}"
    proc = run_filter(final_valid)
    assert proc.returncode == 0, f"Filter failed at EOF without newline: {proc.stderr}"
    assert proc.stdout == final_valid, "Filter did not preserve a valid final line without a newline."


def test_supervise_script_contents():
    script_path = SUPERVISOR
    assert script_path.exists(), f"Expected script {script_path} does not exist."
    assert script_path.is_file(), f"Expected {script_path} to be a file."

    with open(script_path, "r") as f:
        content = f.read()

    # Keep the original static assertions in addition to behavioral testing.
    assert "/app/run" in content, "Script does not appear to reference /app/run directory."
    assert "ln -s" in content and "/app/run/upstream.sock" in content and "/home/user/active_socket" in content, \
        "Script does not contain the required symlink command for active_socket."
    assert "ssh " in content and "-L" in content and "8080:localhost:80" in content, \
        "Script does not contain the required SSH tunnel command."
    assert re.search(r"while\s+(true|:)", content) is not None, \
        "Script does not contain an infinite while loop."
    assert "/app/upstream_daemon" in content, "Script does not invoke /app/upstream_daemon."


def test_supervise_script_behavior():
    daemon = Path("/app/upstream_daemon")
    run_dir = Path("/app/run")
    active_socket = Path("/home/user/active_socket")
    proc = None

    with tempfile.TemporaryDirectory(prefix="supervise-test-") as td:
        td = Path(td)
        backup = td / "upstream_daemon.original"
        events_path = td / "daemon-events.jsonl"
        tunnel_path = td / "tunnel-events.jsonl"
        fake_bin = td / "bin"
        fake_bin.mkdir()
        shutil.copy2(daemon, backup)

        fake_ssh = fake_bin / "ssh"
        fake_ssh.write_text("""#!/usr/bin/env python3
import json, os, sys, time
with open(os.environ['TUNNEL_EVENTS'], 'a') as f:
    f.write(json.dumps({'time': time.monotonic_ns(), 'args': sys.argv[1:]}) + '\\n')
""")
        fake_ssh.chmod(0o755)

        instrumented_daemon = """#!/usr/bin/env python3
import json, os, time
p = os.environ['SUPERVISE_EVENTS']
def emit(kind):
    target = '/home/user/active_socket'
    rec = {
        'kind': kind,
        'time': time.monotonic_ns(),
        'pid': os.getpid(),
        'run_dir': os.path.isdir('/app/run'),
        'is_link': os.path.islink(target),
        'link_target': os.readlink(target) if os.path.islink(target) else None,
    }
    with open(p, 'a') as f:
        f.write(json.dumps(rec) + '\\n')
        f.flush()
        os.fsync(f.fileno())
emit('start')
time.sleep(0.20)
emit('end')
"""

        try:
            if active_socket.is_symlink() or active_socket.exists():
                if active_socket.is_dir() and not active_socket.is_symlink():
                    shutil.rmtree(active_socket)
                else:
                    active_socket.unlink()
            if run_dir.exists():
                if run_dir.is_dir() and not run_dir.is_symlink():
                    shutil.rmtree(run_dir)
                else:
                    run_dir.unlink()

            daemon.write_text(instrumented_daemon)
            daemon.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = str(fake_bin) + os.pathsep + env.get("PATH", "")
            env["SUPERVISE_EVENTS"] = str(events_path)
            env["TUNNEL_EVENTS"] = str(tunnel_path)
            proc = subprocess.Popen(
                ["/bin/bash", str(SUPERVISOR)],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )

            deadline = time.monotonic() + 4.0
            while time.monotonic() < deadline:
                if events_path.exists():
                    events = [json.loads(x) for x in events_path.read_text().splitlines() if x]
                    if sum(e["kind"] == "start" for e in events) >= 3:
                        break
                if proc.poll() is not None:
                    break
                time.sleep(0.05)

            events = []
            if events_path.exists():
                events = [json.loads(x) for x in events_path.read_text().splitlines() if x]
            starts = [e for e in events if e["kind"] == "start"]
            assert len(starts) >= 3, \
                "Supervisor did not keep running and immediately restart the daemon after exits."

            first = starts[0]
            assert first["run_dir"], "Supervisor did not create /app/run before starting the daemon."
            assert first["is_link"] and first["link_target"] == "/app/run/upstream.sock", \
                "Supervisor did not create the required active_socket symlink before starting the daemon."
            assert run_dir.is_dir(), "Expected /app/run to exist as a directory."
            assert active_socket.is_symlink(), "Expected /home/user/active_socket to be a symbolic link."
            assert os.readlink(active_socket) == "/app/run/upstream.sock", \
                "active_socket points to the wrong target."

            active = 0
            max_active = 0
            for event in events:
                if event["kind"] == "start":
                    active += 1
                    max_active = max(max_active, active)
                elif event["kind"] == "end":
                    active -= 1
            assert max_active == 1, \
                "Supervisor launched overlapping daemon instances instead of running it in the foreground."

            tunnels = []
            if tunnel_path.exists():
                tunnels = [json.loads(x) for x in tunnel_path.read_text().splitlines() if x]
            assert len(tunnels) == 1, "Supervisor must establish one SSH tunnel before entering the daemon loop."
            assert tunnels[0]["args"] == ["-N", "-f", "-L", "8080:localhost:80", "localhost"], \
                f"SSH tunnel used incorrect arguments: {tunnels[0]['args']}"
            assert tunnels[0]["time"] <= first["time"], \
                "SSH tunnel was not established before the daemon loop started."
        finally:
            if proc is not None and proc.poll() is None:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                    proc.wait(timeout=1)
                except Exception:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    try:
                        proc.wait(timeout=1)
                    except Exception:
                        pass
            if backup.exists():
                os.replace(backup, daemon)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
