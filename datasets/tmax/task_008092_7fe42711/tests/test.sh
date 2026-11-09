#!/bin/bash
set -u
mkdir -p /logs/verifier

SERVER=/home/user/api/server.py
BACKUP=/tmp/original_pipeline_server.py
cp "$SERVER" "$BACKUP"
restore_server() {
    cp "$BACKUP" "$SERVER" 2>/dev/null || true
    chmod +x "$SERVER" 2>/dev/null || true
}
trap restore_server EXIT

cat > "$SERVER" <<'PY_SERVER'
import http.server
import json
import time

EVENTS = "/tmp/pipeline_api_events.log"

with open(EVENTS, "a") as f:
    f.write("BOOT\n")
    f.flush()

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        with open(EVENTS, "a") as f:
            f.write(self.path + "\n")
            f.flush()

        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        elif self.path.startswith("/tier/"):
            filename = self.path.split("/")[-1]
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            tier = "archive" if filename in ("db_backup.log", "syslog.log") else "retain"
            self.wfile.write(json.dumps({"tier": tier}).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == "__main__":
    time.sleep(3)
    http.server.HTTPServer(("localhost", 9090), Handler).serve_forever()
PY_SERVER
chmod +x "$SERVER"
: > /tmp/pipeline_api_events.log
chmod 666 /tmp/pipeline_api_events.log

cat > /tmp/verify_pipeline.py <<'PY_TEST'
import gzip
import hashlib
import json
import os
import pwd
import secrets
import shutil
import signal
import subprocess
import time
import urllib.request

SCRIPT = "/home/user/run_pipeline.sh"
EVENTS = "/tmp/pipeline_api_events.log"
USER = pwd.getpwnam("user")


def proc_cmdlines():
    result = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            raw = open(f"/proc/{name}/cmdline", "rb").read()
            cmd = raw.replace(b"\0", b" ").decode(errors="ignore")
            result.append((int(name), cmd))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return result


def kill_services():
    victims = []
    for pid, cmd in proc_cmdlines():
        low = cmd.lower()
        if "/home/user/api/server.py" in cmd or ("socat" in low and "8080" in cmd) or ("nc" in low and ("8080" in cmd or "9090" in cmd)):
            victims.append(pid)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.25)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def listening_ports():
    ports = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(path).read().splitlines()[1:]
        except FileNotFoundError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 4 and fields[3] == "0A":
                ports.add(int(fields[1].split(":")[-1], 16))
    return ports


def write_fixture(sizes):
    for path in ("/home/user/logs_pool", "/home/user/archive", "/home/user/reports"):
        shutil.rmtree(path, ignore_errors=True)
        os.makedirs(path, exist_ok=True)
        os.chown(path, USER.pw_uid, USER.pw_gid)

    contents = {}
    for filename, size in sizes.items():
        data = os.urandom(size)
        path = os.path.join("/home/user/logs_pool", filename)
        with open(path, "wb") as f:
            f.write(data)
        os.chown(path, USER.pw_uid, USER.pw_gid)
        contents[filename] = data
    return contents


def read_events():
    try:
        return [line.strip() for line in open(EVENTS) if line.strip()]
    except FileNotFoundError:
        return []


def run_fresh(sizes):
    kill_services()
    contents = write_fixture(sizes)
    open(EVENTS, "w").close()
    os.chmod(EVENTS, 0o666)

    start = time.monotonic()
    proc = subprocess.Popen(
        [SCRIPT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        user=USER.pw_uid,
        group=USER.pw_gid,
    )

    seen_8080 = False
    seen_9090 = False
    seen_server = False
    seen_socat_forward = False
    seen_nc = False
    seen_nc_8080 = False
    seen_nc_9090 = False
    deadline = start + 25

    while proc.poll() is None and time.monotonic() < deadline:
        ports = listening_ports()
        seen_8080 |= 8080 in ports
        seen_9090 |= 9090 in ports
        for _, cmd in proc_cmdlines():
            low = cmd.lower()
            seen_server |= "/home/user/api/server.py" in cmd
            if "socat" in low and "8080" in cmd and "9090" in cmd:
                seen_socat_forward = True
            if "nc" in low:
                seen_nc = True
                seen_nc_8080 |= "8080" in cmd
                seen_nc_9090 |= "9090" in cmd
        time.sleep(0.05)

    if proc.poll() is None:
        proc.kill()
        raise AssertionError("run_pipeline.sh did not finish within 25 seconds")
    assert proc.returncode == 0, f"run_pipeline.sh exited with status {proc.returncode}"
    elapsed = time.monotonic() - start

    # Include persistent background processes in the observations.
    ports = listening_ports()
    seen_8080 |= 8080 in ports
    seen_9090 |= 9090 in ports
    for _, cmd in proc_cmdlines():
        low = cmd.lower()
        seen_server |= "/home/user/api/server.py" in cmd
        seen_socat_forward |= "socat" in low and "8080" in cmd and "9090" in cmd
        if "nc" in low:
            seen_nc = True
            seen_nc_8080 |= "8080" in cmd
            seen_nc_9090 |= "9090" in cmd

    assert elapsed >= 2.7, "pipeline did not wait for the delayed API to become healthy"
    assert seen_server, "the provided Python API server was not started"
    assert seen_9090, "the API server was never observed listening on port 9090"
    assert seen_8080, "no local tunnel was observed listening on port 8080"
    assert seen_socat_forward or (seen_nc and seen_nc_8080 and seen_nc_9090), "no socat/nc forwarding setup from 8080 to 9090 was observed"

    with urllib.request.urlopen("http://localhost:8080/health", timeout=3) as response:
        assert response.status == 200 and response.read() == b"OK", "the port-8080 tunnel is not healthy"

    events = read_events()
    assert "BOOT" in events, "the API server was not executed"
    assert "/health" in events, "the pipeline never polled the health endpoint"
    tier_events = [e for e in events if e.startswith("/tier/")]
    assert tier_events, "the pipeline made no tier API queries"
    assert events.index("/health") < min(events.index(e) for e in tier_events), "tier queries occurred before successful health polling"
    for filename in sizes:
        assert f"/tier/{filename}" in events, f"the API was not queried for {filename}"

    return contents


def assert_state(contents, expected_count, expected_bytes):
    # Original verifier assertions: script and required directories.
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    assert os.path.isdir("/home/user/archive"), "Directory /home/user/archive was not created."
    assert os.path.isdir("/home/user/reports"), "Directory /home/user/reports was not created."

    for filename in ("db_backup.log", "syslog.log"):
        archive = f"/home/user/archive/{filename}.gz"
        assert os.path.isfile(archive), f"Archive {archive} is missing."
        assert not os.path.exists(f"/home/user/logs_pool/{filename}"), f"Original file {filename} should have been moved/removed."
        with gzip.open(archive, "rb") as f:
            restored = f.read()
        assert restored == contents[filename], f"{archive} is not a valid gzip of the original file"

    assert os.path.isfile("/home/user/logs_pool/web_access.log"), "File web_access.log should have been retained in /home/user/logs_pool."
    assert not os.path.exists("/home/user/archive/web_access.log.gz"), "File web_access.log should not have been archived."
    assert open("/home/user/logs_pool/web_access.log", "rb").read() == contents["web_access.log"], "retained log was modified"

    report_path = "/home/user/reports/summary.json"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."
    with open(report_path) as f:
        data = json.load(f)
    assert "archived_count" in data, "Key 'archived_count' missing in summary.json."
    assert "freed_bytes" in data, "Key 'freed_bytes' missing in summary.json."
    assert set(data) == {"archived_count", "freed_bytes"}, "summary.json has an unexpected structure"
    assert data["archived_count"] == expected_count, f"Expected archived_count to be {expected_count}, got {data['archived_count']}."
    assert data["freed_bytes"] == expected_bytes, f"Expected freed_bytes to be {expected_bytes}, got {data['freed_bytes']}."


def rerun_idempotence(contents):
    before = {}
    for filename in ("db_backup.log.gz", "syslog.log.gz"):
        path = os.path.join("/home/user/archive", filename)
        before[filename] = hashlib.sha256(open(path, "rb").read()).hexdigest()

    result = subprocess.run(
        [SCRIPT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=20,
        user=USER.pw_uid,
        group=USER.pw_gid,
    )
    assert result.returncode == 0, "a second pipeline run failed"

    for filename, digest in before.items():
        path = os.path.join("/home/user/archive", filename)
        assert hashlib.sha256(open(path, "rb").read()).hexdigest() == digest, "an existing archive was corrupted on the second run"
    assert open("/home/user/logs_pool/web_access.log", "rb").read() == contents["web_access.log"]
    with open("/home/user/reports/summary.json") as f:
        data = json.load(f)
    assert data == {"archived_count": 0, "freed_bytes": 0}, "the second run must report that no new files were archived"


def main():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    try:
        # Preserve and exercise all original fixed-state expectations.
        baseline = {
            "db_backup.log": 2097152,
            "web_access.log": 1048576,
            "syslog.log": 524288,
        }
        contents = run_fresh(baseline)
        assert_state(contents, 2, 2097152 + 524288)
        rerun_idempotence(contents)

        # Re-run from a fresh state with verifier-chosen sizes so hardcoded reports fail.
        dynamic = {
            "db_backup.log": 700000 + secrets.randbelow(200000),
            "web_access.log": 350000 + secrets.randbelow(100000),
            "syslog.log": 180000 + secrets.randbelow(90000),
        }
        contents = run_fresh(dynamic)
        assert_state(contents, 2, dynamic["db_backup.log"] + dynamic["syslog.log"])
    finally:
        kill_services()


if __name__ == "__main__":
    main()
PY_TEST

if python3 /tmp/verify_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
