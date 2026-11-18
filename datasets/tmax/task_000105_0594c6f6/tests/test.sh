#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_submission.py
import os
import re
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import urllib.request

SERVER = "/home/user/service/server"
SOURCE_DIR = "/home/user/service"
LOG = "/home/user/leak_fixed.log"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def kill_port_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        port = int(fields[1].rsplit(":", 1)[1], 16)
                        if port == 8080:
                            inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
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
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            pass

    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(pids):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pids.discard(pid)
        if pids:
            time.sleep(0.4)
        pids = {pid for pid in pids if os.path.exists(f"/proc/{pid}")}
        if not pids:
            break


def wait_ready(proc):
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        require(proc.poll() is None, "Server exited before becoming ready")
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080/stats", timeout=0.5) as response:
                value = response.read().decode().strip()
            int(value)
            return
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Server did not provide a numeric /stats response: {last_error}")


def exercise_binary(path, label):
    kill_port_8080()
    dump_path = tempfile.mktemp(prefix="go-stack-", suffix=".log")
    dump = open(dump_path, "wb")
    proc = subprocess.Popen(
        [path], stdout=subprocess.DEVNULL, stderr=dump, start_new_session=True
    )
    try:
        wait_ready(proc)

        with urllib.request.urlopen("http://127.0.0.1:8080/process", timeout=3) as response:
            body = response.read().decode()
        require(body == "Success", f"{label} returned {body!r} from /process, not 'Success'")

        clients = []
        for _ in range(50):
            sock = socket.create_connection(("127.0.0.1", 8080), timeout=2)
            sock.sendall(
                b"GET /process HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
            )
            clients.append(sock)

        # Give all handlers time to start, then emulate simultaneous early disconnects.
        time.sleep(0.25)
        for sock in clients:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            sock.close()

        # The simulated work lasts one second. Any blocked sends are now permanent.
        time.sleep(1.35)
        require(proc.poll() is None, f"{label} exited during cancellation testing")

        # SIGQUIT makes the Go runtime independently dump every live goroutine.
        os.kill(proc.pid, signal.SIGQUIT)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
        dump.close()

        with open(dump_path, "r", errors="replace") as f:
            stacks = f.read()
        goroutines = re.findall(r"^goroutine \d+ \[", stacks, re.MULTILINE)
        require(goroutines, f"{label} did not produce a Go runtime goroutine dump")
        require(
            len(goroutines) < 15,
            f"{label} retained {len(goroutines)} goroutines after client cancellation",
        )
    finally:
        if not dump.closed:
            dump.close()
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=2)
        try:
            os.unlink(dump_path)
        except OSError:
            pass
        kill_port_8080()


# Preserve the original verifier's assertions.
require(os.path.isfile(SERVER), f"The compiled executable {SERVER} is missing.")
require(os.access(SERVER, os.X_OK), f"The file {SERVER} is not executable.")
require(os.path.isfile(LOG), f"The verification log {LOG} was not created. Did you run /home/user/verify.sh?")
with open(LOG) as f:
    log_content = f.read().strip()
require(log_content.startswith("SUCCESS"), f"Expected {LOG} to indicate SUCCESS, but got: {log_content}")

# Require an actual native executable, then execute and stress the submitted artifact.
with open(SERVER, "rb") as f:
    require(f.read(4) == b"\x7fELF", f"{SERVER} is not an ELF executable")
exercise_binary(SERVER, "Submitted server")

# Independently compile main.go's package and exercise that build, ensuring the source fix
# exists and the submitted executable is not merely unrelated working code.
built = "/tmp/verifier-source-server"
result = subprocess.run(
    ["go", "build", "-o", built, "."],
    cwd=SOURCE_DIR,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    timeout=60,
)
require(result.returncode == 0, f"The submitted Go source does not compile:\n{result.stdout}")
exercise_binary(built, "Server rebuilt from submitted source")
print("All verifier checks passed")
PY_EOF

python3 /tmp/verify_submission.py
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
