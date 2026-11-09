#!/bin/bash
set +e
mkdir -p /logs/verifier

if (
    set -euo pipefail

    INGEST_PID=""
    WRAPPER_PID=""
    cleanup() {
        if [ -n "$INGEST_PID" ]; then kill "$INGEST_PID" 2>/dev/null || true; fi
        if [ -n "$WRAPPER_PID" ]; then kill "$WRAPPER_PID" 2>/dev/null || true; fi
    }
    trap cleanup EXIT

    python3 - <<'PY'
import os
import re

path = '/app/generator.cpp'
assert os.path.isfile(path), '/app/generator.cpp does not exist or is not a regular file.'
assert not os.path.islink(path), '/app/generator.cpp must be an actual source file, not a symlink.'
with open(path, encoding='utf-8') as f:
    source = f.read()
assert source.strip(), '/app/generator.cpp is empty.'
assert re.search(r'^\s*#\s*include\s*[<\"]omp\.h[>\"]', source, re.M), 'generator.cpp does not include omp.h.'
assert re.search(r'^\s*#\s*pragma\s+omp\s+.*parallel', source, re.M), 'generator.cpp does not contain an OpenMP parallel pragma.'
assert re.search(r'^\s*#\s*include\s*[<\"]curl/curl\.h[>\"]', source, re.M), 'generator.cpp does not include libcurl.'
assert 'curl_easy_init' in source and 'curl_easy_perform' in source, 'generator.cpp does not use the libcurl easy API.'
assert 'http://127.0.0.1:8000/ingest' in source, 'generator.cpp does not target the required ingestion endpoint.'
assert re.search(r'(mt19937|ranlux|default_random_engine|random_device|\brand\s*\()', source), 'generator.cpp contains no random-number generation.'
assert re.search(r'(edge|adjacen|adjacency)', source, re.I), 'generator.cpp contains no graph edge/adjacency implementation.'
assert re.search(r'(triangle|triplet|clustering)', source, re.I), 'generator.cpp contains no clustering-coefficient implementation.'
PY

    # Rebuild the demanded artifact from the submitted source. Library placement at
    # the end is linker-equivalent and works with Debian's --as-needed default.
    rm -f /app/generator
    g++ -O3 -fopenmp /app/generator.cpp -o /app/generator -lcurl
    test -x /app/generator
    ldd /app/generator | grep -q 'libgomp'
    ldd /app/generator | grep -q 'libcurl'
    nm -D /app/generator | grep -q 'curl_easy_perform'

    # Replace any agent-started services with a clean Redis instance.
    if command -v fuser >/dev/null 2>&1; then
        fuser -k 8000/tcp >/dev/null 2>&1 || true
    else
        pkill -f '[p]ython.*ingestion.py' 2>/dev/null || true
    fi
    redis-cli -p 6379 shutdown nosave >/dev/null 2>&1 || true
    if command -v fuser >/dev/null 2>&1; then
        fuser -k 6379/tcp >/dev/null 2>&1 || true
    fi
    redis-server --port 6379 --bind 127.0.0.1 --daemonize yes --save '' --appendonly no
    for _ in $(seq 1 50); do
        redis-cli -p 6379 ping 2>/dev/null | grep -q PONG && break
        sleep 0.1
    done
    redis-cli -p 6379 ping | grep -q PONG
    redis-cli -p 6379 del graph_metrics >/dev/null

    # Launch the submitted ingestion application itself. This exercises both its
    # corrected Flask bind address and its corrected Redis connection.
    python3 /app/ingestion.py >/tmp/ingestion-smoke.log 2>&1 &
    INGEST_PID=$!
    SMOKE_OK=0
    for _ in $(seq 1 100); do
        if curl -sf -X POST -H 'Content-Type: application/json' \
            -d '{"c":0.3}' http://127.0.0.1:8000/ingest >/dev/null 2>&1; then
            SMOKE_OK=1
            break
        fi
        sleep 0.1
    done
    test "$SMOKE_OK" -eq 1
    python3 - <<'PY'
import json
import redis
r = redis.Redis(host='127.0.0.1', port=6379, db=0)
data = r.lrange('graph_metrics', 0, -1)
assert len(data) == 1, 'The submitted ingestion service did not store the smoke-test POST exactly once.'
assert float(json.loads(data[0])['c']) == 0.3
r.delete('graph_metrics')
PY
    kill "$INGEST_PID" 2>/dev/null || true
    wait "$INGEST_PID" 2>/dev/null || true
    INGEST_PID=""

    # Run the submitted Flask app through a small verification wrapper which
    # counts successful, valid HTTP requests without changing its /ingest route.
    TOKEN=$(python3 - <<'PY'
import secrets
print(secrets.token_hex(24))
PY
)
    cat > /tmp/run_instrumented_ingestion.py <<'PY'
import importlib.util
import math
import sys
import threading
from flask import jsonify, request

spec = importlib.util.spec_from_file_location('submitted_ingestion', '/app/ingestion.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
app = module.app
lock = threading.Lock()
state = {'successful_valid_posts': 0}
token = sys.argv[1]

@app.after_request
def count_successful_ingests(response):
    if request.path == '/ingest' and request.method == 'POST' and 200 <= response.status_code < 300:
        data = request.get_json(silent=True)
        try:
            valid = isinstance(data, dict) and set(data) == {'c'} and math.isfinite(float(data['c']))
        except (TypeError, ValueError, KeyError):
            valid = False
        if valid:
            with lock:
                state['successful_valid_posts'] += 1
    return response

@app.get('/__verify_' + token)
def verification_status():
    with lock:
        return jsonify(state)

app.run(host='127.0.0.1', port=8000, threaded=True)
PY
    python3 /tmp/run_instrumented_ingestion.py "$TOKEN" >/tmp/ingestion-verifier.log 2>&1 &
    WRAPPER_PID=$!
    READY=0
    for _ in $(seq 1 100); do
        if curl -sf "http://127.0.0.1:8000/__verify_${TOKEN}" >/dev/null 2>&1; then
            READY=1
            break
        fi
        sleep 0.1
    done
    test "$READY" -eq 1
    redis-cli -p 6379 del graph_metrics >/dev/null

    # The final dataset must now be produced by the freshly compiled artifact,
    # through successful HTTP POSTs observed by the submitted Flask app.
    timeout 900s /app/generator >/tmp/generator.log 2>&1

    VERIFY_TOKEN="$TOKEN" python3 - <<'PY'
import json
import math
import os
import redis
import urllib.request
from scipy.stats import kstest

# Keep the original ingestion-script assertions.
with open('/app/ingestion.py', 'r') as f:
    content = f.read()
assert '6379' in content, 'Redis port in ingestion.py was not fixed to 6379.'
assert '127.0.0.1' in content or '0.0.0.0' in content, 'Flask host in ingestion.py was not fixed to a valid loopback/any address.'

try:
    r = redis.Redis(host='127.0.0.1', port=6379, db=0)
    r.ping()
except redis.exceptions.ConnectionError:
    raise AssertionError('Could not connect to Redis on 127.0.0.1:6379. Is redis-server running?')

data = r.lrange('graph_metrics', 0, -1)
assert data, "No data found in Redis list 'graph_metrics'."
assert len(data) == 10000, f'Expected exactly 10000 values in Redis, but found {len(data)}.'

values = []
for d in data:
    try:
        parsed = json.loads(d)
        assert isinstance(parsed, dict) and set(parsed) == {'c'}
        value = float(parsed['c'])
        assert math.isfinite(value) and 0.0 <= value <= 1.0
        values.append(value)
    except (json.JSONDecodeError, KeyError, ValueError, TypeError, AssertionError):
        raise AssertionError(f"Data in Redis is not in the expected JSON format {{'c': <clustering coefficient>}}. Found: {d!r}")

url = 'http://127.0.0.1:8000/__verify_' + os.environ['VERIFY_TOKEN']
with urllib.request.urlopen(url, timeout=5) as response:
    observed = json.load(response)
assert observed['successful_valid_posts'] == 10000, (
    f"The generator made {observed['successful_valid_posts']} successful valid POST requests; expected exactly 10000."
)

stat, pval = kstest(values, 'norm', args=(0.30, 0.05))
assert stat < 0.03, (
    f'KS_STAT is {stat:.4f}, which is not < 0.03. '
    'The distribution of the generated clustering coefficients does not '
    'sufficiently match the target N(0.30, 0.05^2).'
)
PY
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
