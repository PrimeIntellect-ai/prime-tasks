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
export HOME=/home/user

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import pwd
import signal
import socket
import subprocess
import time

import cv2
import requests

HOME = "/home/user"
VIDEO = "/app/monitoring_feed.mp4"


def derive_expected_count():
    cap = cv2.VideoCapture(VIDEO)
    assert cap.isOpened(), f"Could not open {VIDEO}"
    count = 0
    total = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        total += 1
        block = frame[0:16, 0:16]
        red = (block[:, :, 2] > 200) & (block[:, :, 1] < 50) & (block[:, :, 0] < 50)
        if float(red.mean()) > 0.90:
            count += 1
    cap.release()
    assert total > 0, "Video contained no decodable frames"
    return count


EXPECTED = derive_expected_count()


def wait_get(url, timeout=8):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            return requests.get(url, timeout=1)
        except requests.RequestException as exc:
            last = exc
            time.sleep(0.15)
    raise AssertionError(f"Failed to connect to {url}: {last}")


def stop_user_processes():
    subprocess.run(["pkill", "-9", "-u", "user"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.3)


def launch_start():
    path = os.path.join(HOME, "start.sh")
    assert os.path.isfile(path), "~/start.sh does not exist"
    subprocess.Popen(
        ["runuser", "-u", "user", "--", "env", f"HOME={HOME}", "bash", path],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def raw_http(port, path):
    with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
        sock.sendall(f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n".encode())
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    response = b"".join(chunks)
    assert b"\r\n\r\n" in response, "HTTP response did not use a CRLF header separator"
    head, body = response.split(b"\r\n\r\n", 1)
    assert head.startswith(b"HTTP/1.1 200 OK\r\n"), f"Bad status line or header formatting: {head!r}"
    return head, body


def test_server_conf():
    conf_path = os.path.join(HOME, "server.conf")
    assert os.path.exists(conf_path), f"Configuration file {conf_path} does not exist."
    with open(conf_path, "r") as f:
        content = f.read()

    assert "PORT=8080" in content, "PORT=8080 not found in server.conf"
    assert f"HIGH_LOAD_FRAMES={EXPECTED}" in content, (
        f"HIGH_LOAD_FRAMES={EXPECTED} not found in server.conf; expected value was derived from the video"
    )


def test_analyzer_is_c_program():
    server_source = os.path.join(HOME, "server.c")
    assert os.path.isfile(server_source), "~/server.c does not exist"

    preferred = os.path.join(HOME, "analyzer.c")
    candidates = [preferred] if os.path.isfile(preferred) else []
    candidates += [p for p in glob.glob(os.path.join(HOME, "*.c"))
                   if p != server_source and p not in candidates]
    assert candidates, "No C source for the required frame analyzer was found in the home directory"

    errors = []
    compiled = False
    for source in candidates:
        output = "/tmp/submitted_analyzer"
        result = subprocess.run(["gcc", "-std=c11", source, "-o", output],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode == 0:
            with open(output, "rb") as f:
                assert f.read(4) == b"\x7fELF", "Analyzer did not compile to a native executable"
            compiled = True
            break
        errors.append(f"{source}: {result.stderr}")
    assert compiled, "The submitted analyzer C source did not compile:\n" + "\n".join(errors)


def test_http_endpoints():
    r = requests.get("http://127.0.0.1:8080/health", timeout=2)
    assert r.status_code == 200, f"/health returned status {r.status_code}, expected 200"
    assert "OK" in r.text, "/health body does not contain 'OK'"

    r = requests.get("http://127.0.0.1:8080/report", timeout=2)
    assert r.status_code == 200, f"/report returned status {r.status_code}, expected 200"
    content_type = r.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type application/json, got {content_type}"
    data = r.json()
    assert data.get("high_load_frames") == EXPECTED, (
        f"Expected high_load_frames to be {EXPECTED}, got {data.get('high_load_frames')}"
    )

    _, health_body = raw_http(8080, "/health")
    assert health_body == b"OK", f"/health body must be exactly OK, got {health_body!r}"
    report_head, report_body = raw_http(8080, "/report")
    assert b"content-type: application/json" in report_head.lower(), "Missing JSON Content-Type"
    assert report_body == f'{{"high_load_frames": {EXPECTED}}}'.encode(), (
        f"/report body was not exact: {report_body!r}"
    )


def test_start_compiles_source_reads_config_and_supervises():
    server_c = os.path.join(HOME, "server.c")
    server_bin = os.path.join(HOME, "server")
    conf = os.path.join(HOME, "server.conf")
    log = os.path.join(HOME, "server.log")
    assert os.path.isfile(server_c), "~/server.c does not exist"

    with open(server_c, "rb") as f:
        original_source = f.read()
    source_stat = os.stat(server_c)

    probe_source = r'''#include <arpa/inet.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
int main(void) {
    int s = socket(AF_INET, SOCK_STREAM, 0), one = 1;
    struct sockaddr_in a;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    memset(&a, 0, sizeof(a)); a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK); a.sin_port = htons(18081);
    if (bind(s, (struct sockaddr *)&a, sizeof(a)) || listen(s, 8)) return 2;
    for (;;) {
        int c = accept(s, 0, 0); if (c < 0) continue;
        char b[1024]; read(c, b, sizeof(b));
        const char *r = "HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\nCOMPILED_PROBE";
        write(c, r, strlen(r)); close(c);
        puts("PROBE_LOG"); fflush(stdout);
    }
}
'''

    stop_user_processes()
    with open(server_c, "w") as f:
        f.write(probe_source)
    os.chown(server_c, source_stat.st_uid, source_stat.st_gid)
    os.chmod(server_c, source_stat.st_mode)
    if os.path.exists(server_bin):
        os.unlink(server_bin)
    if os.path.exists(log):
        os.unlink(log)

    launch_start()
    probe = wait_get("http://127.0.0.1:18081/health")
    assert probe.text == "COMPILED_PROBE", (
        "start.sh did not compile and launch the current contents of ~/server.c"
    )
    time.sleep(0.2)
    assert os.path.isfile(log), "~/server.log was not created"
    with open(log, "r", errors="replace") as f:
        assert "PROBE_LOG" in f.read(), "Server stdout was not redirected to ~/server.log"

    stop_user_processes()
    with open(server_c, "wb") as f:
        f.write(original_source)
    os.chown(server_c, source_stat.st_uid, source_stat.st_gid)
    os.chmod(server_c, source_stat.st_mode)

    probe_count = EXPECTED + 111
    with open(conf, "w") as f:
        f.write(f"PORT=18080\nHIGH_LOAD_FRAMES={probe_count}\n")
    os.chown(conf, pwd.getpwnam("user").pw_uid, pwd.getpwnam("user").pw_gid)
    if os.path.exists(server_bin):
        os.unlink(server_bin)

    launch_start()
    changed = wait_get("http://127.0.0.1:18080/report")
    assert changed.status_code == 200
    assert changed.json().get("high_load_frames") == probe_count, (
        "The compiled server did not read PORT and HIGH_LOAD_FRAMES from ~/server.conf at startup"
    )

    stop_user_processes()
    with open(conf, "w") as f:
        f.write(f"PORT=8080\nHIGH_LOAD_FRAMES={EXPECTED}\n")
    os.chown(conf, pwd.getpwnam("user").pw_uid, pwd.getpwnam("user").pw_gid)
    launch_start()
    final = wait_get("http://127.0.0.1:8080/health")
    assert final.status_code == 200 and "OK" in final.text

    output = subprocess.check_output(["pgrep", "-x", "server"]).decode("utf-8")
    server_pids = [int(x) for x in output.strip().splitlines() if x]
    assert server_pids, "The 'server' executable is not currently running."
    server_pid = server_pids[0]
    assert os.stat(f"/proc/{server_pid}").st_uid == pwd.getpwnam("user").pw_uid, (
        "The server is not running as the standard user"
    )

    os.kill(server_pid, signal.SIGKILL)
    restarted = wait_get("http://127.0.0.1:8080/health", timeout=6)
    assert restarted.status_code == 200, f"After kill, /health returned status {restarted.status_code}"
    assert "OK" in restarted.text, "After kill, /health body does not contain 'OK'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
