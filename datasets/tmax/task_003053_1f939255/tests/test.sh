#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SMTP_EOF' > /tmp/raw_smtp_server.py
#!/usr/bin/env python3
import json
import socketserver
import threading

OUTPUT = "/tmp/raw_smtp_sessions.jsonl"
lock = threading.Lock()

class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        lines = []
        self.wfile.write(b"220 test.local ESMTP\r\n")
        self.wfile.flush()
        in_data = False
        while True:
            line = self.rfile.readline()
            if not line:
                break
            lines.append(line.hex())
            upper = line.rstrip(b"\r\n").upper()
            if in_data:
                if line == b".\r\n":
                    in_data = False
                    self.wfile.write(b"250 Message accepted\r\n")
                    self.wfile.flush()
                continue
            if upper.startswith(b"DATA"):
                in_data = True
                self.wfile.write(b"354 End data with <CR><LF>.<CR><LF>\r\n")
            elif upper.startswith(b"QUIT"):
                self.wfile.write(b"221 Bye\r\n")
                self.wfile.flush()
                break
            else:
                self.wfile.write(b"250 OK\r\n")
            self.wfile.flush()
        with lock:
            with open(OUTPUT, "a") as f:
                f.write(json.dumps(lines) + "\n")

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with Server(("127.0.0.1", 8025), Handler) as server:
    server.serve_forever()
SMTP_EOF
chmod +x /tmp/raw_smtp_server.py

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import subprocess
import time
from pathlib import Path

HOME = Path("/home/user")
USAGE = HOME / "usage.csv"
LOG = HOME / "alert_emails.log"
CAPTURE = Path("/tmp/raw_smtp_sessions.jsonl")


def get_pids(process_name):
    try:
        output = subprocess.check_output(["pgrep", "-f", process_name], text=True)
        return [int(pid) for pid in output.strip().splitlines() if pid]
    except subprocess.CalledProcessError:
        return []


def proc_cmdline(pid):
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
        return [x.decode(errors="replace") for x in raw.split(b"\0") if x]
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return []


def exact_executable_pids(path):
    wanted = os.path.realpath(path)
    result = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            actual = os.path.realpath(f"/proc/{entry.name}/exe")
            if actual == wanted:
                result.append(int(entry.name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return result


def matching_pids(predicate):
    result = []
    for entry in Path("/proc").iterdir():
        if entry.name.isdigit():
            pid = int(entry.name)
            if predicate(proc_cmdline(pid)):
                result.append(pid)
    return result


def stop_pids(pids):
    pids = [p for p in set(pids) if p != os.getpid()]
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and any(Path(f"/proc/{p}").exists() for p in pids):
        time.sleep(0.05)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for(predicate, timeout, message):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError(message)


def write_usage(lines):
    tmp = HOME / ".usage.csv.testtmp"
    tmp.write_text("".join(lines))
    os.replace(tmp, USAGE)


def sessions():
    if not CAPTURE.exists():
        return []
    result = []
    for line in CAPTURE.read_text().splitlines():
        if line.strip():
            result.append([bytes.fromhex(x) for x in json.loads(line)])
    return result


def expected_smtp(total):
    return [
        b"HELO finops\r\n",
        b"MAIL FROM:<finops@local>\r\n",
        b"RCPT TO:<alerts@local>\r\n",
        b"DATA\r\n",
        b"Subject: Cost Alert\r\n",
        f"Total cost is ${total:.2f}\r\n".encode(),
        b".\r\n",
        b"QUIT\r\n",
    ]


def process_parent(pid):
    try:
        for line in Path(f"/proc/{pid}/status").read_text().splitlines():
            if line.startswith("PPid:"):
                return int(line.split()[1])
    except FileNotFoundError:
        pass
    return 0


def has_ancestor(pid, ancestors):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid in ancestors:
            return True
        seen.add(pid)
        pid = process_parent(pid)
    return False


def test_complete_system():
    # Preserve the original running-process assertions.
    assert get_pids("socat"), "socat is not running. Did start_all.sh start it?"
    assert get_pids("mock_smtp.py"), "mock_smtp.py is not running."
    assert get_pids("supervisor.sh"), "supervisor.sh is not running."
    assert get_pids("finops_alert"), "finops_alert is not running."

    for path in [HOME / "finops_alert.cpp", HOME / "supervisor.sh", HOME / "start_all.sh"]:
        assert path.is_file(), f"Required artifact {path} is missing"
    assert os.access(HOME / "supervisor.sh", os.X_OK), "supervisor.sh is not executable"
    assert os.access(HOME / "start_all.sh", os.X_OK), "start_all.sh is not executable"

    # Stop the submitted startup instance so the scripts can be exercised from a clean state.
    stop_pids(exact_executable_pids(HOME / "finops_alert"))
    stop_pids(matching_pids(lambda c: any(x == str(HOME / "supervisor.sh") for x in c)))
    stop_pids(matching_pids(lambda c: any(x == str(HOME / "mock_smtp.py") for x in c)))
    stop_pids(matching_pids(lambda c: c and os.path.basename(c[0]) == "socat" and
                            any("2525" in x for x in c) and any("8025" in x for x in c)))

    # Independently compile and execute the submitted C++ source, including exact crash status.
    compile_result = subprocess.run(
        ["g++", "-std=c++17", str(HOME / "finops_alert.cpp"), "-o", str(HOME / "finops_alert")],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
    assert compile_result.returncode == 0, "finops_alert.cpp does not compile:\n" + compile_result.stderr
    binary = HOME / "finops_alert"
    assert binary.read_bytes()[:4] == b"\x7fELF", "Compiled monitor is not an ELF executable"
    assert os.access(binary, os.X_OK), "Compiled monitor is not executable"

    write_usage(["CRASH_TEST,0,0\n"])
    direct = subprocess.Popen([str(binary)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert direct.wait(timeout=4) == 1, "CRASH_TEST must make the monitor exit with status code 1"

    # Removing the executable ensures supervisor.sh itself performs the required compilation.
    binary.unlink()
    write_usage(["idle,1,1.00\n"])
    started = subprocess.run([str(HOME / "start_all.sh")], stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, timeout=5)
    assert started.returncode == 0, "start_all.sh did not exit with status 0"

    wait_for(lambda: binary.exists() and os.access(binary, os.X_OK), 12,
             "supervisor.sh did not compile /home/user/finops_alert")
    monitor_pids = wait_for(lambda: exact_executable_pids(binary), 8,
                            "The compiled finops_alert is not running")
    supervisor_pids = wait_for(
        lambda: matching_pids(lambda c: any(x == str(HOME / "supervisor.sh") for x in c)),
        5, "supervisor.sh is not running")
    assert any(has_ancestor(pid, set(supervisor_pids)) for pid in monitor_pids), \
        "finops_alert is not actually a child supervised by supervisor.sh"

    socat_pids = matching_pids(
        lambda c: c and os.path.basename(c[0]) == "socat" and
                  any("2525" in x and "LISTEN" in x.upper() for x in c) and
                  any("8025" in x and "127.0.0.1" in x for x in c))
    assert socat_pids, "No real socat forwarding 127.0.0.1:2525 to 127.0.0.1:8025 was started"

    # Preserve the original fixed billing/log assertions through the provided SMTP server.
    if LOG.exists():
        LOG.unlink()
    write_usage(["i-123,10,50.0\n", "i-456,10,51.0\n"])
    wait_for(lambda: LOG.exists() and "Total cost is $1010.00" in LOG.read_text(errors="replace"),
             7, "The fixed $1010.00 alert was not delivered")
    content = LOG.read_text(errors="replace")
    assert "Subject: Cost Alert" in content, "Email subject is incorrect or missing."
    assert "Total cost is $1010.00" in content, "Total cost calculation or formatting is incorrect."

    # Replace only the backend with a raw SMTP recorder. Traffic must still pass through socat:2525.
    stop_pids(matching_pids(lambda c: any(x == str(HOME / "mock_smtp.py") for x in c)))
    if CAPTURE.exists():
        CAPTURE.unlink()
    raw = subprocess.Popen(["python3", "/tmp/raw_smtp_server.py"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.4)
    assert raw.poll() is None, "Could not start controlled SMTP backend on port 8025"

    # Exactly 1000 is not strictly greater than the threshold and must not send an alert.
    write_usage(["settle,1,1.00\n"])
    time.sleep(2.7)
    baseline = len(sessions())
    write_usage(["edge-a,20,25.00\n", "edge-b,10,50.00\n"])
    time.sleep(3.0)
    assert len(sessions()) == baseline, "An alert was sent when total cost was exactly $1000.00"

    # Exercise derived, non-hardcoded totals and require the exact SMTP commands and CRLF endings.
    rng = secrets.SystemRandom()
    cases = []
    for case_no in range(2):
        hours = [17, 23, 11]
        cents = [rng.randrange(1900, 2600), rng.randrange(2100, 2900), rng.randrange(1800, 2700)]
        total_cents = sum(h * c for h, c in zip(hours, cents))
        token = secrets.token_hex(5)
        lines = [f"i-{token}-{case_no}-{i},{h},{c / 100:.2f}\n"
                 for i, (h, c) in enumerate(zip(hours, cents))]
        cases.append((lines, total_cents / 100.0))

    for lines, total in cases:
        assert total > 1000.0
        before = len(sessions())
        write_usage(lines)
        expected = expected_smtp(total)
        def matching_session():
            current = sessions()[before:]
            return current if any(s == expected for s in current) else None
        observed = wait_for(matching_session, 7,
                            f"No exact SMTP transaction received for derived total ${total:.2f}")
        assert any(s == expected for s in observed), "SMTP sequence, values, or CRLF endings are incorrect"

    # Preserve and strengthen the original crash/restart assertion without leaving CRASH_TEST behind.
    initial_pids = exact_executable_pids(binary)
    assert initial_pids, "finops_alert is not running before crash test."
    initial_pid = initial_pids[0]
    write_usage(["CRASH_TEST,0,0\n"])
    wait_for(lambda: not Path(f"/proc/{initial_pid}").exists(), 5,
             "finops_alert did not crash on CRASH_TEST")
    write_usage(["post-crash,1,1.00\n"])
    new_pids = wait_for(lambda: [p for p in exact_executable_pids(binary) if p != initial_pid],
                        5, "finops_alert did not restart after crashing.")
    new_pid = new_pids[0]
    assert new_pid != initial_pid, \
        "finops_alert PID did not change. It either didn't crash, or the supervisor didn't restart it properly."
    time.sleep(0.8)
    assert Path(f"/proc/{new_pid}").exists(), "Restarted monitor did not remain running on valid input"
    assert matching_pids(lambda c: any(x == str(HOME / "supervisor.sh") for x in c)), \
        "Supervisor exited instead of restarting the crashed monitor"

    raw.terminate()
    try:
        raw.wait(timeout=3)
    except subprocess.TimeoutExpired:
        raw.kill()
    mock = subprocess.Popen([str(HOME / "mock_smtp.py")], stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    wait_for(lambda: mock.poll() is None and get_pids("mock_smtp.py"), 3,
             "mock_smtp.py could not be restored")

    # Preserve the original final process-presence checks, now on a stable valid record.
    assert get_pids("socat"), "socat is not running. Did start_all.sh start it?"
    assert get_pids("mock_smtp.py"), "mock_smtp.py is not running."
    assert get_pids("supervisor.sh"), "supervisor.sh is not running."
    assert get_pids("finops_alert"), "finops_alert is not running."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
