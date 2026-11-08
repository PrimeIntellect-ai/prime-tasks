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
set +e
mkdir -p /logs/verifier

# Remove any server the agent may have started before verification, including a
# fabricated process which does not have one of the expected command lines.
python3 - <<'PY'
import os
import signal
import time

ports = {6379, 6380, 8080}
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table, "r", encoding="ascii") as f:
            next(f)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[3] == "0A":
                    port = int(fields[1].split(":")[1], 16)
                    if port in ports:
                        inodes.add(fields[9])
    except OSError:
        pass

victims = set()
for name in os.listdir("/proc"):
    if not name.isdigit():
        continue
    fd_dir = f"/proc/{name}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                victims.add(int(name))
                break
    except OSError:
        pass

for pid in victims:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(1)
for pid in victims:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY

# Execute the artifact the instruction requires instead of trusting services
# which happened to be running before the verifier began.
su -s /bin/bash user -c 'cd /home/user/app && exec bash ./start.sh' >/tmp/app-start-verifier.log 2>&1 &
START_PID=$!
export START_PID

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import time

import pytest
import redis
import requests

APP_DIR = "/home/user/app"
BASE_URL = "http://127.0.0.1:8080"
START_PID = int(os.environ["START_PID"])

EXPECTED_WORKER = '''import time
import redis
from config import API_SECRET

if API_SECRET != "git-sec-9942x":
    raise ValueError("Invalid API_SECRET")

r = redis.Redis(host='127.0.0.1', port=6379, decode_responses=True)
while True:
    try:
        r.set("secret_data", "secret-payload-from-redis")
        time.sleep(10)
    except Exception as e:
        print("Worker redis connection failed:", e)
        time.sleep(2)
'''

EXPECTED_FRONTEND = '''import os
from fastapi import FastAPI, Header, HTTPException
import redis

INIT_TOKEN = os.environ.get("INIT_TOKEN")
if INIT_TOKEN != "TOKEN-A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6":
    raise RuntimeError("Missing or invalid INIT_TOKEN")

app = FastAPI()
r = redis.Redis(host='127.0.0.1', port=6379, decode_responses=True)

@app.get("/health")
def health():
    return {"status": "healthy"}

@app.get("/secure-data")
def secure_data(authorization: str = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Unauthorized")
    token = authorization.split(" ")[1]
    if token != "git-sec-9942x":
        raise HTTPException(status_code=403, detail="Forbidden")

    try:
        data = r.get("secret_data")
    except Exception:
        raise HTTPException(status_code=500, detail="Redis connection failed")

    if not data:
        raise HTTPException(status_code=500, detail="Data not ready")
    return {"data": data}
'''


def recovered_credentials():
    history = subprocess.check_output(
        ["git", "log", "-p", "--all", "--", "worker/config.py"],
        cwd=APP_DIR,
        text=True,
    )
    secrets_found = re.findall(r'API_SECRET\s*=\s*["\']([^"\']+)["\']', history)
    assert secrets_found, "No deleted API_SECRET assignment was found in git history"
    api_secret = secrets_found[-1]

    with open(os.path.join(APP_DIR, "frontend_crash.dump"), "rb") as f:
        dump = f.read()
    tokens = re.findall(rb"TOKEN-[A-Za-z0-9]{32}", dump)
    assert len(set(tokens)) == 1, "Expected exactly one initialization token in the dump"
    return api_secret, tokens[0].decode("ascii")


API_SECRET, INIT_TOKEN = recovered_credentials()


def proc_info():
    result = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            with open(f"/proc/{pid}/status", "r", encoding="utf-8") as f:
                status = f.read()
            ppid = int(re.search(r"^PPid:\s+(\d+)$", status, re.M).group(1))
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode("utf-8", "replace").strip()
            result[pid] = (ppid, cmd)
        except (OSError, AttributeError):
            pass
    return result


def descendants(root, info):
    found = set()
    changed = True
    while changed:
        changed = False
        for pid, (ppid, _cmd) in info.items():
            if pid not in found and (ppid == root or ppid in found):
                found.add(pid)
                changed = True
    return found


def environment(pid):
    with open(f"/proc/{pid}/environ", "rb") as f:
        entries = f.read().split(b"\0")
    return {
        item.split(b"=", 1)[0].decode(): item.split(b"=", 1)[1].decode()
        for item in entries if b"=" in item
    }


def listening_inode(port):
    wanted = f"{port:04X}"
    with open("/proc/net/tcp", "r", encoding="ascii") as f:
        next(f)
        for line in f:
            fields = line.split()
            address, found_port = fields[1].split(":")
            if address == "0100007F" and found_port == wanted and fields[3] == "0A":
                return fields[9]
    return None


def pid_owns_inode(pid, inode):
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                if os.readlink(f"/proc/{pid}/fd/{fd}") == f"socket:[{inode}]":
                    return True
            except OSError:
                pass
    except OSError:
        pass
    return False


@pytest.fixture(scope="session", autouse=True)
def wait_for_real_stack():
    deadline = time.time() + 25
    last_error = None
    while time.time() < deadline:
        try:
            assert os.path.exists(f"/proc/{START_PID}"), "start.sh exited"
            rr = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
            assert rr.ping()
            response = requests.get(f"{BASE_URL}/health", timeout=1)
            assert response.status_code == 200
            if rr.get("secret_data") == "secret-payload-from-redis":
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.25)
    log = ""
    try:
        with open("/tmp/app-start-verifier.log", "r", encoding="utf-8") as f:
            log = f.read()
    except OSError:
        pass
    pytest.fail(f"Stack did not become ready: {last_error}\nstart.sh output:\n{log}")


def test_expected_project_services_were_not_replaced():
    with open(os.path.join(APP_DIR, "worker/main.py"), encoding="utf-8") as f:
        assert f.read() == EXPECTED_WORKER, "worker/main.py was replaced instead of fixing startup"
    with open(os.path.join(APP_DIR, "frontend/main.py"), encoding="utf-8") as f:
        assert f.read() == EXPECTED_FRONTEND, "frontend/main.py was replaced instead of fixing startup"


def test_start_script_launched_all_real_processes_with_credentials():
    info = proc_info()
    child_pids = descendants(START_PID, info)
    assert child_pids, "start.sh has no running child services"

    redis_pids = [p for p in child_pids if "redis-server" in info[p][1]]
    worker_pids = [p for p in child_pids if re.search(r"python\S*\s+worker/main\.py(?:\s|$)", info[p][1])]
    frontend_pids = [p for p in child_pids if "uvicorn" in info[p][1] and "frontend.main:app" in info[p][1]]
    assert redis_pids, "start.sh did not launch redis-server"
    assert worker_pids, "start.sh did not launch worker/main.py"
    assert frontend_pids, "start.sh did not launch uvicorn frontend.main:app"

    assert any(environment(p).get("API_SECRET") == API_SECRET for p in worker_pids), \
        "The recovered API_SECRET was not supplied to the worker"
    assert any(environment(p).get("INIT_TOKEN") == INIT_TOKEN for p in frontend_pids), \
        "The dump token was not supplied to the frontend"

    redis_inode = listening_inode(6379)
    web_inode = listening_inode(8080)
    assert redis_inode, "Redis is not listening on 127.0.0.1:6379"
    assert web_inode, "The frontend is not listening on 127.0.0.1:8080"
    assert any(pid_owns_inode(p, redis_inode) for p in redis_pids), "The launched Redis does not own port 6379"
    assert any(pid_owns_inode(p, web_inode) for p in frontend_pids), "The launched uvicorn does not own port 8080"


def test_health_endpoint():
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the FastAPI frontend on port 8080: {e}")
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert data.get("status") == "healthy", f"Expected status 'healthy', got {data.get('status')}"


def test_secure_data_endpoint():
    headers = {"Authorization": f"Bearer {API_SECRET}"}
    try:
        response = requests.get(f"{BASE_URL}/secure-data", headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the FastAPI frontend on port 8080: {e}")
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert data.get("data") == "secret-payload-from-redis", f"Expected data 'secret-payload-from-redis', got {data.get('data')}"


def test_frontend_reads_live_redis_and_enforces_authentication():
    assert requests.get(f"{BASE_URL}/secure-data", timeout=5).status_code == 401
    assert requests.get(
        f"{BASE_URL}/secure-data",
        headers={"Authorization": "Bearer " + secrets.token_hex(16)},
        timeout=5,
    ).status_code == 403

    challenge = "verifier-" + secrets.token_hex(20)
    rr = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
    rr.set("secret_data", challenge)
    response = requests.get(
        f"{BASE_URL}/secure-data",
        headers={"Authorization": f"Bearer {API_SECRET}"},
        timeout=5,
    )
    assert response.status_code == 200
    assert response.json() == {"data": challenge}, "Frontend did not return the randomized live Redis value"


def test_worker_is_actively_connected_to_redis():
    rr = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
    rr.delete("secret_data")
    deadline = time.time() + 13
    while time.time() < deadline:
        if rr.get("secret_data") == "secret-payload-from-redis":
            return
        time.sleep(0.25)
    pytest.fail("The background worker did not repopulate Redis")


def test_debugging_report_exists():
    report_path = os.path.join(APP_DIR, "debugging_report.txt")
    assert os.path.isfile(report_path), f"Debugging report not found at {report_path}"
    with open(report_path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert len(content) > 0, f"Debugging report at {report_path} is empty."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
