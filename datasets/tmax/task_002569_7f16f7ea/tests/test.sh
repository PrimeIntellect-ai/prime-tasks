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
reward=0
MOCK_PID=""
RUST_PID=""
MONITOR_PID=""
cleanup() {
    [ -z "$MONITOR_PID" ] || kill "$MONITOR_PID" 2>/dev/null || true
    [ -z "$RUST_PID" ] || kill "$RUST_PID" 2>/dev/null || true
    [ -z "$MOCK_PID" ] || kill "$MOCK_PID" 2>/dev/null || true
    echo "$reward" > /logs/verifier/reward.txt
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_initial_state.py
import os
import time
import requests
import pytest

def test_mock_fixture_exists():
    path = "/app/rust-processor/tests/fixtures/mock_ast.json"
    assert os.path.isfile(path), f"Missing mock fixture file: {path}"

def test_rust_processor_evaluates_correctly():
    url = "http://127.0.0.1:8080/evaluate"
    for _ in range(10):
        try:
            requests.get("http://127.0.0.1:8080/", timeout=1)
            break
        except requests.ConnectionError:
            time.sleep(1)
    else:
        pytest.fail("Rust processor is not listening on 127.0.0.1:8080")

    for payload, expected in [
        ({"version": "2.1.0", "rule_id": "rule-prod"}, True),
        ({"version": "0.9.0", "rule_id": "rule-prod"}, False),
    ]:
        try:
            response = requests.post(url, json=payload, timeout=5)
        except requests.RequestException as exc:
            pytest.fail(f"Failed to send request to {url}: {exc}")
        assert response.status_code == 200, (
            f"Expected status code 200, got {response.status_code}. "
            f"Response: {response.text}"
        )
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {response.text}")
        assert data.get("allowed") is expected, (
            f"Expected allowed: {expected} for {payload}, got {data}"
        )
TEST_EOF
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_initial_state.py -x --tb=short

# The submitted Rust project itself must compile and pass its complete test suite.
cd /app/rust-processor
cargo test
cargo build --release

# The required fixture must be valid AST JSON and must evaluate true for 1.4.5.
python3 - <<'PY'
import json
p = "/app/rust-processor/tests/fixtures/mock_ast.json"
with open(p) as f:
    ast = json.load(f)

def ver(s):
    return tuple(map(int, s.split("-")[0].split("+")[0].split(".")))

def ev(n, v):
    typ = n.get("type")
    if typ == "AND":
        return ev(n["left"], v) and ev(n["right"], v)
    if typ == "OR":
        return ev(n["left"], v) or ev(n["right"], v)
    assert typ == "CONSTRAINT" and isinstance(n.get("value"), str)
    text = n["value"].strip()
    for op in (">=", "<=", ">", "<", "="):
        if text.startswith(op):
            rhs = ver(text[len(op):].strip())
            lhs = ver(v)
            return {">=": lhs >= rhs, "<=": lhs <= rhs, ">": lhs > rhs,
                    "<": lhs < rhs, "=": lhs == rhs}[op]
    raise AssertionError("invalid fixture constraint")

assert ev(ast, "1.4.5") is True, "fixture does not evaluate true for 1.4.5"
PY

# Kill listeners so verification exercises the freshly built submitted binary
# against a verifier-controlled legacy engine.
kill_port() {
python3 - "$1" <<'PY'
import os, signal, sys, time
port = int(sys.argv[1])
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        if int(fields[1].rsplit(":", 1)[1], 16) == port and fields[3] == "0A":
            inodes.add(fields[9])
for pid in os.listdir("/proc"):
    if not pid.isdigit() or int(pid) == os.getpid():
        continue
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                os.kill(int(pid), signal.SIGTERM)
                break
    except OSError:
        pass
time.sleep(1)
PY
}
kill_port 8080
kill_port 8081

cat <<'PY' > /tmp/mock_legacy.py
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote
import json

CASES = "/tmp/legacy_cases.json"
COUNTS = "/tmp/legacy_requests.log"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Authorization") != "Bearer internal-token":
            self.send_response(401)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"error":"Unauthorized"}')
            return
        prefix = "/ast/"
        if not self.path.startswith(prefix):
            self.send_response(404)
            self.end_headers()
            return
        rule = unquote(self.path[len(prefix):].split("?", 1)[0])
        try:
            with open(CASES) as f:
                cases = json.load(f)
            ast = cases[rule]
        except Exception:
            self.send_response(404)
            self.end_headers()
            return
        with open(COUNTS, "a") as f:
            f.write(rule + "\n")
        body = json.dumps(ast).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", 8081), Handler).serve_forever()
PY
printf '{}\n' > /tmp/legacy_cases.json
: > /tmp/legacy_requests.log
python3 /tmp/mock_legacy.py >/tmp/mock_legacy.out 2>&1 &
MOCK_PID=$!

redis-cli ping >/dev/null 2>&1 || redis-server --daemonize yes
redis-cli FLUSHDB >/dev/null
: > /tmp/redis-monitor.log
redis-cli MONITOR > /tmp/redis-monitor.log 2>&1 &
MONITOR_PID=$!
sleep 1

REDIS_URL=redis://127.0.0.1:6379 \
LEGACY_ENGINE_URL=http://127.0.0.1:8081 \
/app/rust-processor/target/release/rust-processor >/tmp/rust-processor.out 2>&1 &
RUST_PID=$!

cat <<'PY' > /tmp/test_dynamic_integration.py
import json
import os
import random
import secrets
import time
import requests

URL = "http://127.0.0.1:8080/evaluate"
CASES_FILE = "/tmp/legacy_cases.json"
COUNT_FILE = "/tmp/legacy_requests.log"

for _ in range(40):
    try:
        r = requests.get("http://127.0.0.1:8080/", timeout=.5)
        break
    except requests.RequestException:
        time.sleep(.25)
else:
    raise AssertionError("freshly built Rust processor did not start")

rng = random.SystemRandom()
tag = secrets.token_hex(12)
major = rng.randint(2, 7)
minor = rng.randint(1, 7)
patch = rng.randint(1, 7)
base = f"{major}.{minor}.{patch}"
upper = f"{major + 1}.0.0"
below = f"{major}.{minor}.{patch - 1}"
inside = f"{major}.{minor}.{patch + 1}"
high = f"{major + 3}.0.0"

rules = {
    f"and-{tag}": {
        "type": "AND",
        "left": {"type": "CONSTRAINT", "value": f">={base}"},
        "right": {"type": "CONSTRAINT", "value": f"<{upper}"},
    },
    f"or-{tag}": {
        "type": "OR",
        "left": {"type": "CONSTRAINT", "value": f"<{base}"},
        "right": {"type": "CONSTRAINT", "value": f">={high}"},
    },
    f"nested-{tag}": {
        "type": "AND",
        "left": {
            "type": "OR",
            "left": {"type": "CONSTRAINT", "value": f"<{base}"},
            "right": {"type": "CONSTRAINT", "value": f">={base}"},
        },
        "right": {"type": "CONSTRAINT", "value": f"<{upper}"},
    },
}

def save():
    tmp = CASES_FILE + ".new"
    with open(tmp, "w") as f:
        json.dump(rules, f)
    os.replace(tmp, CASES_FILE)

save()

def evaluate(rule, version, expected):
    payload = {"version": version, "rule_id": rule}
    response = requests.post(URL, json=payload, timeout=5)
    assert response.status_code == 200, (response.status_code, response.text)
    try:
        data = response.json()
    except ValueError:
        raise AssertionError(f"non-JSON response: {response.text}")
    assert data.get("allowed") is expected, (payload, expected, data)

and_rule = f"and-{tag}"
or_rule = f"or-{tag}"
nested_rule = f"nested-{tag}"
evaluate(and_rule, below, False)
evaluate(and_rule, base, True)
evaluate(and_rule, inside, True)
evaluate(and_rule, upper, False)
evaluate(or_rule, below, True)
evaluate(or_rule, inside, False)
evaluate(or_rule, high, True)
evaluate(nested_rule, inside, True)
evaluate(nested_rule, upper, False)

# A unique rule/version is fetched once. Changing the legacy AST afterward must
# not change the repeated answer because the first result is held in Redis.
cache_rule = f"cache-{tag}"
cache_version = f"{major}.5.5"
rules[cache_rule] = {"type": "CONSTRAINT", "value": f">={major}.0.0"}
save()
before = open(COUNT_FILE).read().splitlines().count(cache_rule)
evaluate(cache_rule, cache_version, True)
rules[cache_rule] = {"type": "CONSTRAINT", "value": f">={major + 5}.0.0"}
save()
evaluate(cache_rule, cache_version, True)
after = open(COUNT_FILE).read().splitlines().count(cache_rule)
assert after - before == 1, "repeated request was not served from cache"

with open("/tmp/dynamic_tag", "w") as f:
    f.write(tag)
PY
python3 /tmp/test_dynamic_integration.py

kill "$MONITOR_PID" 2>/dev/null || true
wait "$MONITOR_PID" 2>/dev/null || true
MONITOR_PID=""
# Confirm that the processor actually issued both cache reads and writes to Redis.
grep -Eiq '"(get|mget)"' /tmp/redis-monitor.log
grep -Eiq '"(set|setex|psetex)"' /tmp/redis-monitor.log

reward=1
