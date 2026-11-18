#!/bin/bash
mkdir -p /logs/verifier
printf '0\n' > /logs/verifier/reward.txt

WORKSPACE=/home/user/workspace
APP_DIR="$WORKSPACE/app"
VENV_PY="$WORKSPACE/venv/bin/python"
BACKEND_PID=""
NGINX_PID=""

cleanup() {
    if [ -n "$NGINX_PID" ]; then kill "$NGINX_PID" 2>/dev/null || true; fi
    if [ -n "$BACKEND_PID" ]; then kill "$BACKEND_PID" 2>/dev/null || true; fi
    pkill -x nginx 2>/dev/null || true
}
trap cleanup EXIT

# Ensure verification exercises fresh processes using the submitted artifacts.
pkill -x nginx 2>/dev/null || true
pkill -f '[p]ython(3)? .*main.py' 2>/dev/null || true
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import sys

import requests

WORKSPACE_DIR = "/home/user/workspace"
APP_DIR = os.path.join(WORKSPACE_DIR, "app")
LOG_FILE = os.path.join(WORKSPACE_DIR, "test_results.log")
NGINX_CONF = os.path.join(WORKSPACE_DIR, "nginx.conf")
ALGORITHMS_PY = os.path.join(APP_DIR, "algorithms.py")
BASE_URL = "http://127.0.0.1:8080/api/v1/graph/critical_path"


def test_test_results_log_success():
    """Check that the requested integration-test log exists and reports success."""
    assert os.path.isfile(LOG_FILE), f"Missing file: {LOG_FILE}. Did you run the tests and redirect output?"
    with open(LOG_FILE, "r") as f:
        content = f.read()
    assert "1 passed" in content or "100%" in content, "Integration tests did not pass according to test_results.log. Ensure the tests pass and output is redirected."


def test_nginx_conf_fixed():
    """Retain the original source-level assertion."""
    assert os.path.isfile(NGINX_CONF), f"Missing file: {NGINX_CONF}"
    with open(NGINX_CONF, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:5000/api/v1/graph;" not in content, (
        "nginx.conf still contains the buggy proxy_pass line that strips query parameters."
    )


def test_algorithms_py_fixed_import():
    """Retain the original circular-import assertion."""
    assert os.path.isfile(ALGORITHMS_PY), f"Missing file: {ALGORITHMS_PY}"
    with open(ALGORITHMS_PY, "r") as f:
        content = f.read()
    assert "import main" not in content, "algorithms.py still contains the circular 'import main'."


def _load_algorithm():
    if APP_DIR not in sys.path:
        sys.path.insert(0, APP_DIR)
    try:
        import algorithms
    except ImportError as e:
        assert False, f"Failed to import algorithms.py: {e}"
    assert "critical_path" in algorithms.ALGORITHM_REGISTRY, "critical_path is not registered in ALGORITHM_REGISTRY."
    assert callable(algorithms.ALGORITHM_REGISTRY["critical_path"])
    return algorithms.ALGORITHM_REGISTRY["critical_path"]


def test_critical_path_implementation():
    """Retain both original algorithm examples."""
    critical_path_func = _load_algorithm()
    graph1 = {
        "A": {"B": 3.0, "C": 2.0},
        "B": {"D": 4.0},
        "C": {"D": 6.0},
        "D": {},
    }
    result1 = critical_path_func(graph1, "A", "D")
    assert result1 == 8.0, f"critical_path returned {result1} for graph1, expected 8.0"

    graph2 = {
        "A": {"B": 1.0, "C": 10.0},
        "B": {"D": 1.0},
        "C": {"D": 1.0},
        "D": {},
    }
    result2 = critical_path_func(graph2, "A", "D")
    assert result2 == 11.0, f"critical_path returned {result2} for graph2, expected 11.0"


def _random_case():
    """Create a runtime-random DAG and independently derive its answer."""
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    count = rng.randint(6, 11)
    topo = [f"node-{i}-{secrets.token_hex(5)}" for i in range(count)]
    graph = {node: {} for node in topo}

    # A chain guarantees a path while additional forward edges create alternatives.
    for i in range(count - 1):
        graph[topo[i]][topo[i + 1]] = float(rng.randint(-12, 18)) + rng.choice((0.0, 0.25, 0.5, 0.75))
    for i in range(count):
        for j in range(i + 2, count):
            if rng.random() < 0.42:
                graph[topo[i]][topo[j]] = float(rng.randint(-12, 18)) + rng.choice((0.0, 0.25, 0.5, 0.75))

    start_index = rng.randint(0, count - 3)
    end_index = rng.randint(start_index + 2, count - 1)
    start, end = topo[start_index], topo[end_index]

    dist = {node: -math.inf for node in topo}
    dist[start] = 0.0
    for node in topo:
        if dist[node] == -math.inf:
            continue
        for neighbor, weight in graph[node].items():
            dist[neighbor] = max(dist[neighbor], dist[node] + weight)

    # Shuffle dictionary insertion order so implementations cannot assume it is topological.
    shuffled = list(topo)
    rng.shuffle(shuffled)
    graph = {node: graph[node] for node in shuffled}
    return graph, start, end, dist[end]


def test_runtime_randomized_algorithm_cases():
    func = _load_algorithm()
    for _ in range(10):
        graph, start, end, expected = _random_case()
        actual = func(graph, start, end)
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
        assert math.isclose(float(actual), expected, rel_tol=0.0, abs_tol=1e-9), (
            f"critical_path returned {actual!r}; expected {expected!r} for "
            f"start={start!r}, end={end!r}, graph={graph!r}"
        )


def test_proxy_startup_registry_query_forwarding_and_algorithm():
    # These requests pass through the freshly launched Nginx and Flask processes.
    for _ in range(7):
        graph, start, end, expected = _random_case()
        response = requests.post(
            BASE_URL,
            params={"start_node": start, "end_node": end},
            json={"graph": graph},
            timeout=5,
        )
        assert response.status_code == 200, response.text
        payload = response.json()
        assert set(payload) == {"result"}, payload
        assert math.isclose(float(payload["result"]), expected, rel_tol=0.0, abs_tol=1e-9), (
            f"API returned {payload!r}; expected {expected!r}"
        )
TEST_EOF

PASS=1

# Validate and then actually launch the submitted Nginx configuration and Flask app.
if ! nginx -t -c "$WORKSPACE/nginx.conf" -p "$WORKSPACE/" >/tmp/verifier_nginx_test.log 2>&1; then
    PASS=0
fi

if [ "$PASS" -eq 1 ]; then
    (cd "$APP_DIR" && exec "$VENV_PY" main.py) >/tmp/verifier_flask.log 2>&1 &
    BACKEND_PID=$!
    nginx -c "$WORKSPACE/nginx.conf" -p "$WORKSPACE/" >/tmp/verifier_nginx.log 2>&1 &
    NGINX_PID=$!

    READY=0
    for _ in $(seq 1 30); do
        if "$VENV_PY" -c 'import socket; s=socket.create_connection(("127.0.0.1",8080),0.3); s.close()' >/dev/null 2>&1; then
            READY=1
            break
        fi
        sleep 0.2
    done
    if [ "$READY" -ne 1 ]; then PASS=0; fi
fi

# Run the verifier-owned behavioral suite, including unpredictable DAGs over HTTP.
if [ "$PASS" -eq 1 ]; then
    if ! timeout 60 "$VENV_PY" -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short >/tmp/verifier_pytest.log 2>&1; then
        PASS=0
    fi
fi

# Independently execute the integration test the instruction specifically requires;
# do not trust the agent-created test_results.log as evidence of execution.
if [ "$PASS" -eq 1 ]; then
    if ! timeout 30 "$VENV_PY" -m pytest "$WORKSPACE/tests/test_integration.py" -x --tb=short >/tmp/verifier_integration.log 2>&1; then
        PASS=0
    fi
fi

printf '%s\n' "$PASS" > /logs/verifier/reward.txt
exit 0
