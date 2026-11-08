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
mkdir -p /logs/verifier

run_verifier() (
    set -euo pipefail

    cleanup_port() {
        python3 - <<'PY'
import os, signal
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        if fields[1].split(':')[-1].upper() == '1F90' and fields[3] == '0A':
            inodes.add(fields[9])
for entry in os.listdir('/proc'):
    if not entry.isdigit() or int(entry) == os.getpid():
        continue
    try:
        for fd in os.listdir(f'/proc/{entry}/fd'):
            try:
                target = os.readlink(f'/proc/{entry}/fd/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                os.kill(int(entry), signal.SIGTERM)
                break
    except (OSError, ProcessLookupError, PermissionError):
        pass
PY
        sleep 1
    }

    cleanup_port

    # Preserve the original existence assertions, then require the build system
    # to recreate both requested artifacts from scratch.
    test -f /app/Makefile
    test -f /app/src/go-server/poly_test.go
    rm -f /app/libpoly.so /app/poly-server
    make -C /app
    test -f /app/libpoly.so
    test -x /app/poly-server
    readelf -h /app/libpoly.so | grep -q 'DYN (Shared object file)'
    readelf -h /app/poly-server >/dev/null
    ldd /app/poly-server | grep -q 'libpoly\.so'

    # Verify that the submitted Go tests really execute the supplied oracle.
    test -x /app/poly_oracle
    rm -f /tmp/oracle-called
    mv /app/poly_oracle /tmp/poly_oracle.verifier-real
    cat > /app/poly_oracle <<'EOF'
#!/bin/sh
echo called >> /tmp/oracle-called
exec /tmp/poly_oracle.verifier-real "$@"
EOF
    chmod +x /app/poly_oracle
    restore_oracle() {
        rm -f /app/poly_oracle
        if [ -e /tmp/poly_oracle.verifier-real ]; then
            mv /tmp/poly_oracle.verifier-real /app/poly_oracle
        fi
    }
    trap restore_oracle EXIT
    (
        cd /app/src/go-server
        go clean -testcache
        LD_LIBRARY_PATH=/app CGO_ENABLED=1 go test -count=1 ./...
    )
    test -s /tmp/oracle-called
    restore_oracle
    trap - EXIT

    # Exercise the submitted shared library under Valgrind over many sizes and
    # values. This retains functional checking while detecting invalid accesses
    # and per-call leaks in evaluate_polynomial.
    cat > /tmp/poly_memcheck.c <<'EOF'
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "/app/src/libpoly/poly.h"

static uint64_t state = UINT64_C(0x6a09e667f3bcc909);
static double rnd(void) {
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    return ((double)(state % 2000001) - 1000000.0) / 250000.0;
}

int main(void) {
    for (int trial = 0; trial < 3000; ++trial) {
        int degree = trial % 257;
        double *c = malloc((size_t)(degree + 1) * sizeof(*c));
        if (!c) return 2;
        for (int i = 0; i <= degree; ++i) c[i] = rnd();
        double x = rnd() / 4.0;
        double expected = 0.0;
        for (int i = degree; i >= 0; --i) expected = expected * x + c[i];
        double got = evaluate_polynomial(c, degree, x);
        if (!isfinite(got) || fabs(got - expected) > 1e-11 * fmax(1.0, fabs(expected))) {
            fprintf(stderr, "wrong result at trial %d: %.17g != %.17g\n", trial, got, expected);
            free(c);
            return 3;
        }
        free(c);
    }
    return 0;
}
EOF
    gcc -O0 -g /tmp/poly_memcheck.c -L/app -Wl,-rpath,/app -lpoly -lm -o /tmp/poly_memcheck
    LD_LIBRARY_PATH=/app valgrind --quiet --leak-check=full --show-leak-kinds=all \
        --errors-for-leak-kinds=all --error-exitcode=99 /tmp/poly_memcheck

    # Interpose evaluate_polynomial and log its arguments. This proves that the
    # built HTTP server routes each evaluation through the C ABI rather than
    # merely carrying an unused libpoly dependency.
    cat > /tmp/poly_spy.c <<'EOF'
#include <stdio.h>
double evaluate_polynomial(double *coeffs, int degree, double x) {
    FILE *f = fopen("/tmp/poly-spy.log", "a");
    if (f) { fprintf(f, "%d %.17g\n", degree, x); fclose(f); }
    double result = 0.0;
    for (int i = degree; i >= 0; --i) result = result * x + coeffs[i];
    return result;
}
EOF
    gcc -shared -fPIC /tmp/poly_spy.c -o /tmp/poly_spy.so
    rm -f /tmp/poly-spy.log
    cd /app
    LD_LIBRARY_PATH=/app LD_PRELOAD=/tmp/poly_spy.so nohup /app/poly-server >/tmp/poly-spy-server.log 2>&1 &
    spy_pid=$!

    python3 - "$spy_pid" <<'PY'
import json, math, os, random, sys, time
import requests
pid = int(sys.argv[1])
url = 'http://127.0.0.1:8080/poly/eval'
headers = {'Authorization': 'Bearer SIGMA_7781'}
for _ in range(60):
    if not os.path.exists(f'/proc/{pid}'):
        raise AssertionError('built poly-server exited during startup')
    try:
        requests.post(url, json={'coeffs':[1.0], 'x':0.0}, timeout=.25)
        break
    except requests.RequestException:
        time.sleep(.1)
else:
    raise AssertionError('built poly-server did not listen on port 8080')

rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
for degree in [0, 1, 2, 5, 17, 64, 193, 511]:
    coeffs = [rng.uniform(-3.0, 3.0) for _ in range(degree + 1)]
    x = rng.uniform(-0.85, 0.85)
    expected = 0.0
    for c in reversed(coeffs):
        expected = expected * x + c
    try:
        os.unlink('/tmp/poly-spy.log')
    except FileNotFoundError:
        pass
    r = requests.post(url, json={'coeffs': coeffs, 'x': x}, headers=headers, timeout=3)
    assert r.status_code == 200, (r.status_code, r.text)
    data = r.json()
    got = data['result']
    assert math.isfinite(got)
    assert abs(got - expected) <= 1e-9 * max(1.0, abs(expected)), (got, expected)
    lines = open('/tmp/poly-spy.log').read().splitlines()
    seen = False
    for line in lines:
        d, sx = line.split()
        if int(d) == degree and abs(float(sx) - x) <= 1e-15 * max(1.0, abs(x)):
            seen = True
    assert seen, f'HTTP request degree={degree} x={x} did not call evaluate_polynomial'
PY
    kill "$spy_pid"
    wait "$spy_pid" 2>/dev/null || true
    cleanup_port

    # Launch the actual built server using the submitted shared library and
    # leave this process running after verification.
    cd /app
    LD_LIBRARY_PATH=/app nohup /app/poly-server >/tmp/poly-server.log 2>&1 &
    real_pid=$!

    cat > /tmp/test_final_state.py <<'PY'
import json
import math
import os
import random
import time
import pytest
import requests

URL = "http://127.0.0.1:8080/poly/eval"
AUTH = {"Authorization": "Bearer SIGMA_7781"}
PID = int(os.environ["POLY_SERVER_PID"])

def wait_for_server():
    for _ in range(60):
        if not os.path.exists(f"/proc/{PID}"):
            pytest.fail("built poly-server exited during startup")
        try:
            requests.post(URL, json={"coeffs": [1.0], "x": 0.0}, timeout=.25)
            return
        except requests.RequestException:
            time.sleep(.1)
    pytest.fail("built poly-server did not start")

wait_for_server()

def test_makefile_exists():
    assert os.path.isfile("/app/Makefile"), "Makefile does not exist in /app/"

def test_go_test_file_exists():
    assert os.path.isfile("/app/src/go-server/poly_test.go"), "poly_test.go does not exist in /app/src/go-server/"

def test_listens_exactly_on_loopback():
    inodes = set()
    for fd in os.listdir(f"/proc/{PID}/fd"):
        try:
            target = os.readlink(f"/proc/{PID}/fd/{fd}")
        except OSError:
            continue
        if target.startswith("socket:["):
            inodes.add(target[8:-1])
    listeners = []
    for line in open('/proc/net/tcp').read().splitlines()[1:]:
        fields = line.split()
        if fields[9] in inodes and fields[3] == '0A' and fields[1].endswith(':1F90'):
            listeners.append(fields[1].split(':')[0])
    assert listeners == ['0100007F'], f"server must listen exactly on 127.0.0.1:8080, found {listeners}"

def test_http_server_unauthorized():
    payload = {"coeffs": [2.0, -1.0, 3.0], "x": 4.0}
    try:
        response = requests.post(URL, json=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized for missing auth header, got {response.status_code}"

    headers = {"Authorization": "Bearer INVALID_TOKEN"}
    try:
        response = requests.post(URL, json=payload, headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized for invalid auth header, got {response.status_code}"

def test_http_server_authorized_eval():
    payload = {"coeffs": [2.0, -1.0, 3.0], "x": 4.0}
    try:
        response = requests.post(URL, json=payload, headers=AUTH, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert "result" in data, "Response JSON missing 'result' key"
    assert abs(data["result"] - 46.0) < 1e-6, f"Expected result 46.0, got {data['result']}"

def test_http_server_randomized_oracle_cases():
    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    degrees = [0, 1, 3, 8, 31, 79, 257, rng.randint(100, 400)]
    for degree in degrees:
        coeffs = [rng.uniform(-5.0, 5.0) for _ in range(degree + 1)]
        x = rng.uniform(-0.9, 0.9)
        expected = 0.0
        for c in reversed(coeffs):
            expected = expected * x + c
        response = requests.post(URL, json={"coeffs": coeffs, "x": x}, headers=AUTH, timeout=4)
        assert response.status_code == 200, response.text
        data = response.json()
        assert set(data) == {"result"}
        got = data["result"]
        assert isinstance(got, (int, float)) and math.isfinite(got)
        assert abs(got - expected) <= 1e-9 * max(1.0, abs(expected)), (degree, x, got, expected)

def test_http_server_large_poly():
    degree = 10000
    coeffs = [1.0] * (degree + 1)
    payload = {"coeffs": coeffs, "x": 1.0}
    try:
        response = requests.post(URL, json=payload, headers=AUTH, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to evaluate large polynomial (server might have crashed): {e}")
    assert response.status_code == 200, f"Expected 200 OK for large polynomial, got {response.status_code}"
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert "result" in data, "Response JSON missing 'result' key"
    assert abs(data["result"] - (degree + 1)) < 1e-6, f"Expected result {degree + 1}, got {data['result']}"
PY

    POLY_SERVER_PID="$real_pid" python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
    kill -0 "$real_pid"
)

if run_verifier 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
