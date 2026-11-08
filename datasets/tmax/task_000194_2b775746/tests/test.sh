#!/bin/bash
set +e
mkdir -p /logs/verifier

(
set -e
PROJECT=/home/user/workspace/migration-service
ORACLE=/app/legacy_graph_resolver
AGENT="$PROJECT/target/release/agent_resolver"
SERVER="$PROJECT/target/release/migration-service"
export PATH="/root/.cargo/bin:$PATH"

# The required source artifacts must be real files, and the original public
# signatures must remain present.
python3 - <<'PY'
from pathlib import Path
p = Path('/home/user/workspace/migration-service/src/bin/agent_resolver.rs')
assert p.is_file() and not p.is_symlink(), 'src/bin/agent_resolver.rs must be a regular source file'

def compact(path):
    return ''.join(Path(path).read_text().split())

g = compact('/home/user/workspace/migration-service/src/graph_parser.rs')
s = compact('/home/user/workspace/migration-service/src/schema_loader.rs')
assert "pubstructGraph<'a>" in g
assert "pubnodes:Vec<&'astr>" in g
assert "pubfnparse_graph(input:String)->Graph<'static>" in g
assert "pubstructSchema<'a>" in s
assert "pubdata:&'astr" in s
assert "pubfnload_schema()->&'staticstr" in s
PY

# Build from the submitted Rust sources instead of trusting a pre-created target.
cd "$PROJECT"
cargo clean
cargo build --release --bins

python3 - <<'PY'
import os
agent = '/home/user/workspace/migration-service/target/release/agent_resolver'
oracle = '/app/legacy_graph_resolver'
assert os.path.exists(agent), f'Agent binary missing at {agent}'
assert os.path.isfile(agent), f'{agent} is not a file'
assert not os.path.islink(agent), f'{agent} must not be a symlink'
assert os.access(agent, os.X_OK), f'{agent} is not executable'
assert os.path.exists(oracle) and os.access(oracle, os.X_OK)
assert not os.path.samefile(agent, oracle), 'Agent binary aliases the legacy resolver'
assert open(agent, 'rb').read() != open(oracle, 'rb').read(), 'Agent binary is byte-identical to the legacy resolver'
PY

# Preserve the original 10,000-case oracle-equivalence assertion.
cat > /tmp/test_final_state.py <<'PY'
import os
import random
import string
import subprocess
import pytest

ORACLE_PATH = '/app/legacy_graph_resolver'
AGENT_PATH = '/home/user/workspace/migration-service/target/release/agent_resolver'
NUM_ITERATIONS = 10000

def generate_random_dag():
    n_nodes = random.randint(1, 200)
    nodes = set()
    while len(nodes) < n_nodes:
        length = random.randint(4, 12)
        nodes.add(''.join(random.choices(string.ascii_letters + string.digits, k=length)))
    nodes = list(nodes)
    topological_order = nodes[:]
    random.shuffle(topological_order)
    possible_edges = []
    for i in range(n_nodes):
        for j in range(i + 1, n_nodes):
            possible_edges.append((topological_order[i], topological_order[j]))
    edges = random.sample(possible_edges, random.randint(0, len(possible_edges)))
    lines = [str(n_nodes), *nodes, str(len(edges))]
    lines.extend(f'{src} {dst}' for src, dst in edges)
    return '\n'.join(lines) + '\n'

def test_agent_binary_exists():
    assert os.path.exists(AGENT_PATH)
    assert os.path.isfile(AGENT_PATH)
    assert not os.path.islink(AGENT_PATH)
    assert os.access(AGENT_PATH, os.X_OK)

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH)
    assert os.access(ORACLE_PATH, os.X_OK)
    random.seed(42)
    for i in range(NUM_ITERATIONS):
        data = generate_random_dag()
        oracle = subprocess.run([ORACLE_PATH], input=data, text=True, capture_output=True, timeout=10)
        assert oracle.returncode == 0, f'Oracle failed on iteration {i}: {oracle.stderr}'
        agent = subprocess.run([AGENT_PATH], input=data, text=True, capture_output=True, timeout=10)
        assert agent.returncode == 0, f'Agent failed on iteration {i}: {agent.stderr}'
        if oracle.stdout.strip() != agent.stdout.strip():
            pytest.fail(f'Mismatch on iteration {i}!\nInput:\n{data}\nOracle output:\n{oracle.stdout.strip()}\nAgent output:\n{agent.stdout.strip()}')
PY
python3 -m pytest /tmp/test_final_state.py -x --tb=short

# Make the legacy executable unavailable while independently derived CLI and
# REST tests run. This rejects symlinks and wrappers that delegate to it.
HIDDEN=/app/.legacy_graph_resolver.verifier-hidden
mv "$ORACLE" "$HIDDEN"
restore_oracle() {
    if [ -e "$HIDDEN" ]; then mv "$HIDDEN" "$ORACLE"; fi
}
trap restore_oracle EXIT

python3 - <<'PY'
import heapq
import json
import os
import random
import subprocess
import time
import urllib.error
import urllib.request

AGENT = '/home/user/workspace/migration-service/target/release/agent_resolver'
SERVER = '/home/user/workspace/migration-service/target/release/migration-service'

def expected(nodes, edges):
    adjacency = {n: [] for n in nodes}
    indegree = {n: 0 for n in nodes}
    for src, dst in edges:
        adjacency[src].append(dst)
        indegree[dst] += 1
    ready = [n for n in nodes if indegree[n] == 0]
    heapq.heapify(ready)
    result = []
    while ready:
        node = heapq.heappop(ready)
        result.append(node)
        for dst in adjacency[node]:
            indegree[dst] -= 1
            if indegree[dst] == 0:
                heapq.heappush(ready, dst)
    return result

def encode(nodes, edges):
    return '\n'.join([str(len(nodes)), *nodes, str(len(edges)), *(f'{a} {b}' for a, b in edges)]) + '\n'

# Deterministic and randomized cases whose answers are calculated here rather
# than obtained from the legacy executable.
cases = [
    (['z', 'a', 'm'], []),
    (['build', 'lint', 'compile', 'deploy'], [('compile', 'build'), ('lint', 'build'), ('build', 'deploy')]),
    (['a1', 'A1', 'b1', 'B1'], [('A1', 'b1'), ('a1', 'b1')]),
]
rng = random.Random(91731)
for case_no in range(250):
    n = rng.randint(1, 80)
    nodes = [f'n{case_no:03d}_{i:03d}_{rng.randrange(10**6):06d}' for i in range(n)]
    order = nodes[:]
    rng.shuffle(order)
    possible = [(order[i], order[j]) for i in range(n) for j in range(i + 1, n)]
    edges = rng.sample(possible, rng.randint(0, min(len(possible), n * 5)))
    rng.shuffle(nodes)
    cases.append((nodes, edges))

for i, (nodes, edges) in enumerate(cases):
    want = ','.join(expected(nodes, edges))
    proc = subprocess.run([AGENT], input=encode(nodes, edges), text=True, capture_output=True, timeout=10)
    assert proc.returncode == 0, f'independent CLI case {i} failed: {proc.stderr}'
    assert proc.stdout.strip() == want, f'independent CLI case {i}: expected {want!r}, got {proc.stdout.strip()!r}'

assert os.path.isfile(SERVER) and os.access(SERVER, os.X_OK), 'REST service binary was not built'
env = os.environ.copy()
env.update({
    'PORT': '18080',
    'BIND_ADDR': '127.0.0.1:18080',
    'AXUM_ADDRESS': '127.0.0.1:18080',
    'MIGRATION_SERVICE_ADDR': '127.0.0.1:18080',
})
server = subprocess.Popen([SERVER], cwd=os.path.dirname(os.path.dirname(SERVER)), env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
try:
    nodes = ['package-z', 'package-a', 'package-m', 'release']
    edges = [('package-a', 'release'), ('package-m', 'release')]
    want = expected(nodes, edges)
    payloads = [
        {'nodes': nodes, 'edges': [[a, b] for a, b in edges]},
        {'nodes': nodes, 'edges': [{'source': a, 'destination': b} for a, b in edges]},
    ]

    def response_order(raw):
        value = json.loads(raw)
        if isinstance(value, list):
            return value
        if isinstance(value, str):
            return [] if value == '' else value.split(',')
        if isinstance(value, dict):
            for key in ('order', 'sequence', 'ordered_sequence', 'build_order', 'result'):
                if key in value:
                    v = value[key]
                    if isinstance(v, str):
                        return [] if v == '' else v.split(',')
                    return v
        raise AssertionError(f'unrecognized REST response: {value!r}')

    success = None
    deadline = time.time() + 12
    while time.time() < deadline and success is None:
        assert server.poll() is None, 'REST service exited before accepting requests'
        for port in (18080, 3000, 8080):
            for payload in payloads:
                request = urllib.request.Request(
                    f'http://127.0.0.1:{port}/api/v1/resolve',
                    data=json.dumps(payload).encode(),
                    headers={'Content-Type': 'application/json'},
                    method='POST')
                try:
                    with urllib.request.urlopen(request, timeout=1) as response:
                        if 200 <= response.status < 300:
                            success = response_order(response.read().decode())
                            break
                except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError):
                    pass
            if success is not None:
                break
        if success is None:
            time.sleep(0.15)
    assert success is not None, 'REST API did not answer POST /api/v1/resolve'
    assert success == want, f'REST API expected {want!r}, got {success!r}'
finally:
    server.terminate()
    try:
        server.wait(timeout=3)
    except subprocess.TimeoutExpired:
        server.kill()
        server.wait()
PY

restore_oracle
trap - EXIT
) 
status=$?

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
