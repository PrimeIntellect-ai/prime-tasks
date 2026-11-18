#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import os
import secrets
import subprocess

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"


def redis_cmd(*args):
    result = subprocess.run(["redis-cli", *args], check=True, capture_output=True, text=True)
    return result.stdout.strip()


def redis_set(key, value):
    try:
        subprocess.run(["redis-cli", "SET", key, value], check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to set Redis key {key}: {e.stderr.decode()}")


def test_api_resolution():
    # Populate Redis with a valid DAG
    # root_app:1.0 -> libB:2.0, libC:3.0
    # libB:2.0 -> libD:1.5
    # libC:3.0 -> libD:1.5
    # libD:1.5 -> []
    redis_set("artifact:root_app:1.0:deps", json.dumps([{"name": "libB", "version": "2.0"}, {"name": "libC", "version": "3.0"}]))
    redis_set("artifact:root_app:1.0:checksum", "aaaa")

    redis_set("artifact:libB:2.0:deps", json.dumps([{"name": "libD", "version": "1.5"}]))
    redis_set("artifact:libB:2.0:checksum", "bbbb")

    redis_set("artifact:libC:3.0:deps", json.dumps([{"name": "libD", "version": "1.5"}]))
    redis_set("artifact:libC:3.0:checksum", "cccc")

    redis_set("artifact:libD:1.5:deps", json.dumps([]))
    redis_set("artifact:libD:1.5:checksum", "dddd")

    try:
        resp = requests.get(f"{BASE_URL}/api/v1/artifacts/resolve/root_app?version=1.0", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Python API: {e}")

    assert resp.status_code == 200, f"Expected HTTP 200, got {resp.status_code}. Response: {resp.text}"

    try:
        data = resp.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")

    assert data.get("artifact") == "root_app", "Response artifact name mismatch"
    assert data.get("version") == "1.0", "Response artifact version mismatch"

    deps = data.get("resolved_dependencies", [])
    names = [d.get("name") for d in deps]

    assert "libD" in names, "libD missing from resolved dependencies"
    assert "libB" in names, "libB missing from resolved dependencies"
    assert "libC" in names, "libC missing from resolved dependencies"
    assert "root_app" not in names, "root_app should not be in its own dependencies list"

    idx_d = names.index("libD")
    idx_b = names.index("libB")
    idx_c = names.index("libC")

    assert idx_d < idx_b, "Topological sort failed: libD must appear before libB"
    assert idx_d < idx_c, "Topological sort failed: libD must appear before libC"

    # Check aggregated checksum based on the actual valid topological sort returned
    if idx_b < idx_c:
        concat_str = "dddd" + "bbbb" + "cccc" + "aaaa"
    else:
        concat_str = "dddd" + "cccc" + "bbbb" + "aaaa"

    expected_checksum = hashlib.sha256(concat_str.encode("utf-8")).hexdigest()
    assert data.get("aggregated_checksum") == expected_checksum, "Aggregated checksum is incorrect"


def test_api_circular_dependency():
    redis_set("artifact:circA:1:deps", json.dumps([{"name": "circB", "version": "1"}]))
    redis_set("artifact:circA:1:checksum", "1111")
    redis_set("artifact:circB:1:deps", json.dumps([{"name": "circA", "version": "1"}]))
    redis_set("artifact:circB:1:checksum", "2222")

    try:
        resp = requests.get(f"{BASE_URL}/api/v1/artifacts/resolve/circA?version=1", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Python API: {e}")

    assert resp.status_code == 400, f"Expected HTTP 400 for circular dependency, got {resp.status_code}"

    try:
        data = resp.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")

    assert "error" in data, "Expected 'error' key in response for circular dependency"
    assert "circular dependency detected" in data["error"].lower(), "Expected error message to mention circular dependency"


def _install_graph(nodes, versions, edges, checksums):
    redis_cmd("FLUSHDB")
    for node in nodes:
        deps = [{"name": dep, "version": versions[dep]} for dep in edges[node]]
        redis_set(f"artifact:{node}:{versions[node]}:deps", json.dumps(deps))
        redis_set(f"artifact:{node}:{versions[node]}:checksum", checksums[node])


def _assert_resolution(root, nodes, versions, edges, checksums):
    response = requests.get(
        f"{BASE_URL}/api/v1/artifacts/resolve/{root}",
        params={"version": versions[root]},
        timeout=5,
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data.get("artifact") == root
    assert data.get("version") == versions[root]

    resolved = data.get("resolved_dependencies")
    assert isinstance(resolved, list)
    expected_nodes = set(nodes) - {root}
    returned_pairs = [(item.get("name"), item.get("version")) for item in resolved]
    assert len(returned_pairs) == len(expected_nodes)
    assert set(returned_pairs) == {(node, versions[node]) for node in expected_nodes}
    assert len({name for name, _ in returned_pairs}) == len(returned_pairs)

    order = [name for name, _ in returned_pairs] + [root]
    positions = {name: index for index, name in enumerate(order)}
    for dependent in nodes:
        for dependency in edges[dependent]:
            assert positions[dependency] < positions[dependent], (
                f"dependency {dependency} appeared after dependent {dependent}: {order}"
            )

    expected_hash = hashlib.sha256(
        "".join(checksums[name] for name in order).encode("utf-8")
    ).hexdigest()
    assert data.get("aggregated_checksum") == expected_hash
    return data.get("aggregated_checksum")


def test_random_redis_backed_dags_and_checksum_mutation():
    rng = secrets.SystemRandom()
    for case in range(8):
        count = rng.randint(3, 10)
        token = secrets.token_hex(6)
        nodes = [f"node_{token}_{case}_{i}" for i in range(count)]
        versions = {node: f"{case}.{i}.{rng.randint(0, 999)}" for i, node in enumerate(nodes)}

        # Every node is reachable from the final root. Edges always point to a
        # lower index, with extra random edges creating branching and sharing.
        edges = {node: [] for node in nodes}
        for i in range(1, count):
            edges[nodes[i]].append(nodes[i - 1])
            for j in range(i - 1):
                if rng.random() < 0.35 and nodes[j] not in edges[nodes[i]]:
                    edges[nodes[i]].append(nodes[j])
            rng.shuffle(edges[nodes[i]])

        checksums = {node: secrets.token_hex(rng.randint(5, 24)) for node in nodes}
        root = nodes[-1]
        _install_graph(nodes, versions, edges, checksums)
        before = _assert_resolution(root, nodes, versions, edges, checksums)

        mutated = rng.choice(nodes)
        old_value = checksums[mutated]
        checksums[mutated] = old_value + secrets.token_hex(8)
        redis_set(f"artifact:{mutated}:{versions[mutated]}:checksum", checksums[mutated])
        after = _assert_resolution(root, nodes, versions, edges, checksums)
        assert after != before, "Changing one Redis checksum must change the aggregate"


def test_random_cycles_are_rejected():
    rng = secrets.SystemRandom()
    for case in range(5):
        count = rng.randint(2, 7)
        token = secrets.token_hex(6)
        nodes = [f"cycle_{token}_{case}_{i}" for i in range(count)]
        versions = {node: f"v{rng.randint(10, 99999)}" for node in nodes}
        edges = {nodes[i]: [nodes[(i + 1) % count]] for i in range(count)}
        checksums = {node: secrets.token_hex(12) for node in nodes}
        _install_graph(nodes, versions, edges, checksums)

        response = requests.get(
            f"{BASE_URL}/api/v1/artifacts/resolve/{nodes[0]}",
            params={"version": versions[nodes[0]]},
            timeout=5,
        )
        assert response.status_code == 400, response.text
        body = response.json()
        assert "circular dependency detected" in body.get("error", "").lower()


def test_version_query_parameter_is_required():
    name = f"missing_version_{secrets.token_hex(5)}"
    response = requests.get(f"{BASE_URL}/api/v1/artifacts/resolve/{name}", timeout=5)
    assert 400 <= response.status_code < 500


def _is_given_decorator(node):
    if not isinstance(node, ast.Call):
        return False
    func = node.func
    return (isinstance(func, ast.Name) and func.id == "given") or (
        isinstance(func, ast.Attribute) and func.attr == "given"
    )


def test_property_based_tests_exist_and_pass():
    test_file = "/home/user/tests/test_graph.py"
    assert os.path.isfile(test_file), f"Test file {test_file} does not exist"

    with open(test_file, "r") as f:
        content = f.read()

    assert "hypothesis" in content, "The test file does not seem to import or use 'hypothesis'"
    assert "@given" in content, "The test file does not seem to use the '@given' decorator from hypothesis"

    # Ensure @given is attached to substantive tests about generated graph
    # ordering and checksum mutation, rather than to an unrelated trivial test.
    try:
        tree = ast.parse(content, filename=test_file)
    except SyntaxError as exc:
        pytest.fail(f"Property test file is not valid Python: {exc}")

    given_tests = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            decorators = [d for d in node.decorator_list if _is_given_decorator(d)]
            if decorators:
                assert any(d.args or d.keywords for d in decorators), "@given must provide generated strategies"
                given_tests.append(node)

    assert given_tests, "No test function decorated with Hypothesis @given was found"
    assert sum(isinstance(n, ast.Assert) for fn in given_tests for n in ast.walk(fn)) >= 2, (
        "Hypothesis tests must assert both topological ordering and checksum mutation"
    )

    formal_names = {
        arg.arg
        for fn in given_tests
        for arg in (fn.args.posonlyargs + fn.args.args + fn.args.kwonlyargs)
    }
    loaded_names = {
        n.id for fn in given_tests for n in ast.walk(fn)
        if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load)
    }
    assert formal_names & loaded_names, "Generated test inputs are not used by the property tests"

    compare_ops = [
        op
        for fn in given_tests
        for n in ast.walk(fn)
        if isinstance(n, ast.Compare)
        for op in n.ops
    ]
    assert any(isinstance(op, (ast.Lt, ast.LtE)) for op in compare_ops), (
        "A generated-graph property must compare dependency and dependent positions"
    )
    assert any(isinstance(op, ast.NotEq) for op in compare_ops), (
        "A property must assert that mutating one checksum changes the aggregate"
    )

    identifiers = " ".join(
        n.id if isinstance(n, ast.Name) else n.attr
        for fn in given_tests
        for n in ast.walk(fn)
        if isinstance(n, (ast.Name, ast.Attribute))
    ).lower()
    assert any(term in identifiers for term in ("dag", "graph", "edge", "depend")), (
        "Hypothesis tests do not appear to generate or consume dependency graphs"
    )
    assert any(term in identifiers for term in ("topo", "order", "position", "index")), (
        "Hypothesis tests do not appear to validate topological ordering"
    )
    assert any(term in identifiers for term in ("checksum", "hash", "digest", "mutat")), (
        "Hypothesis tests do not appear to validate checksum mutation"
    )
    assert any(term in content.lower() for term in ("/app", "resolver", "api")), (
        "Property tests must exercise the submitted resolution implementation"
    )

    res = subprocess.run(["pytest", test_file], capture_output=True, text=True)
    assert res.returncode == 0, f"pytest on {test_file} failed:\n{res.stdout}\n{res.stderr}"
TEST_EOF

# Stop any previously running API and Redis so the submitted orchestration script
# must actually bring up the current implementation.
python3 - << 'PY'
import os
import signal
import time


def listener_inodes(port):
    result = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(path).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and int(fields[1].split(":")[-1], 16) == port and fields[3] == "0A":
                result.add(fields[9])
    return result


def kill_port(port):
    inodes = listener_inodes(port)
    for proc in os.listdir("/proc"):
        if not proc.isdigit() or int(proc) == os.getpid():
            continue
        fd_dir = f"/proc/{proc}/fd"
        try:
            links = [os.readlink(os.path.join(fd_dir, fd)) for fd in os.listdir(fd_dir)]
        except (OSError, PermissionError):
            continue
        if any(link.startswith("socket:[") and link[8:-1] in inodes for link in links):
            try:
                os.kill(int(proc), signal.SIGTERM)
            except ProcessLookupError:
                pass

for _ in range(3):
    kill_port(8080)
    time.sleep(0.4)
PY
redis-cli shutdown nosave >/dev/null 2>&1 || true

startup_ok=1
if [ ! -x /app/start_services.sh ]; then
    startup_ok=0
elif ! timeout 20s /app/start_services.sh >/tmp/start_services.log 2>&1; then
    startup_ok=0
fi

ready=0
for _ in $(seq 1 50); do
    if redis-cli PING 2>/dev/null | grep -q PONG && python3 - << 'PY' >/dev/null 2>&1
import socket
s = socket.create_connection(("127.0.0.1", 8080), timeout=0.3)
s.close()
PY
    then
        ready=1
        break
    fi
    sleep 0.2
done

if [ "$startup_ok" -eq 1 ] && [ "$ready" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    cat /tmp/start_services.log 2>/dev/null || true
    echo "0" > /logs/verifier/reward.txt
fi
