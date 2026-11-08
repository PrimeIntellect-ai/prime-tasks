#!/bin/bash
mkdir -p /logs/verifier
status=0

# Preserve the original requirement that the agent created a plausible report
# before the verifier runs the submitted property tests itself.
python3 - <<'PY' || status=1
import os
path = "/home/user/test_report.txt"
assert os.path.isfile(path), f"File missing: {path}"
with open(path, "r", errors="replace") as f:
    content = f.read().lower()
assert "test session starts" in content or "passed" in content, \
    "test_report.txt does not look like a valid pytest output"
PY

# Actually execute the required property-based test artifact and replace the
# report with the genuine output from this run.
python3 -m pytest /home/user/test_solver.py 2>&1 | tee /home/user/test_report.txt
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    status=1
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import random
import secrets
import sys

import pytest
from google.protobuf.message import Message


def test_protobuf_compiled():
    path = "/home/user/build_graph_pb2.py"
    assert os.path.isfile(path), f"Compiled Protobuf file missing: {path}"

    sys.path.insert(0, "/home/user")
    import build_graph_pb2

    assert issubclass(build_graph_pb2.BuildGraph, Message)
    assert issubclass(build_graph_pb2.BuildOrder, Message)
    assert [f.name for f in build_graph_pb2.Module.DESCRIPTOR.fields] == ["name", "depends_on"]
    assert [f.name for f in build_graph_pb2.BuildGraph.DESCRIPTOR.fields] == ["modules"]
    assert [f.name for f in build_graph_pb2.BuildOrder.DESCRIPTOR.fields] == ["ordered_modules"]


def test_test_solver_file_created():
    path = "/home/user/test_solver.py"
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r") as f:
        content = f.read()

    assert "hypothesis" in content, "test_solver.py does not import/use hypothesis"
    assert "@given" in content or "@settings" in content, \
        "test_solver.py does not use hypothesis decorators (@given or @settings)"


def test_test_report_generated():
    path = "/home/user/test_report.txt"
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r") as f:
        content = f.read().lower()

    assert "test session starts" in content or "passed" in content, \
        "test_report.txt does not look like a valid pytest output"
    assert "passed" in content, "The executed property-based test suite did not report passing tests"


def load_submission():
    sys.path.insert(0, "/home/user")
    try:
        import build_graph_pb2
        from solver import resolve_build_order
    except ImportError as e:
        pytest.fail(f"Failed to import compiled protobuf or solver.py: {e}")
    return build_graph_pb2, resolve_build_order


def expected_order(names, dependencies):
    indegree = {name: 0 for name in names}
    adjacency = {name: [] for name in names}
    for name in names:
        for dep in dependencies[name]:
            adjacency[dep].append(name)
            indegree[name] += 1

    ready = [name for name, degree in indegree.items() if degree == 0]
    heapq.heapify(ready)
    result = []
    while ready:
        current = heapq.heappop(ready)
        result.append(current)
        for dependent in adjacency[current]:
            indegree[dependent] -= 1
            if indegree[dependent] == 0:
                heapq.heappush(ready, dependent)
    if len(result) != len(names):
        raise ValueError("Cycle detected")
    return result


def make_graph(pb2, module_order, dependencies):
    graph = pb2.BuildGraph()
    for name in module_order:
        module = graph.modules.add()
        module.name = name
        module.depends_on.extend(dependencies[name])
    return graph


def test_solver_logic():
    pb2, resolve_build_order = load_submission()

    # Preserve the original fixed valid-graph assertion.
    g = pb2.BuildGraph()
    m1 = g.modules.add()
    m1.name = "A"
    m1.depends_on.extend(["B", "C"])
    m2 = g.modules.add()
    m2.name = "B"
    m2.depends_on.extend(["D"])
    m3 = g.modules.add()
    m3.name = "C"
    m3.depends_on.extend(["D"])
    m4 = g.modules.add()
    m4.name = "D"

    order = resolve_build_order(g)
    expected = ["D", "B", "C", "A"]
    actual = list(order.ordered_modules)
    assert actual == expected, f"Expected build order {expected}, but got {actual}"

    # Preserve the original fixed cycle assertion.
    g2 = pb2.BuildGraph()
    c1 = g2.modules.add()
    c1.name = "X"
    c1.depends_on.extend(["Y"])
    c2 = g2.modules.add()
    c2.name = "Y"
    c2.depends_on.extend(["X"])

    with pytest.raises(ValueError) as excinfo:
        resolve_build_order(g2)
    assert "Cycle detected" in str(excinfo.value), \
        "Expected ValueError with 'Cycle detected' message when a cycle is present"


def test_many_runtime_generated_acyclic_graphs():
    pb2, resolve_build_order = load_submission()
    rng = random.Random(secrets.randbits(128))

    for case in range(50):
        size = rng.randint(0, 22)
        prefix = secrets.token_hex(4)
        names = [f"{prefix}_{i:02d}_{rng.randrange(1_000_000):06d}" for i in range(size)]
        topo_seed = names[:]
        rng.shuffle(topo_seed)

        dependencies = {name: [] for name in names}
        for later_index, name in enumerate(topo_seed):
            for earlier in topo_seed[:later_index]:
                if rng.random() < 0.24:
                    dependencies[name].append(earlier)
            rng.shuffle(dependencies[name])

        module_order = names[:]
        rng.shuffle(module_order)
        graph = make_graph(pb2, module_order, dependencies)
        expected = expected_order(names, dependencies)
        result = resolve_build_order(graph)

        assert isinstance(result, pb2.BuildOrder), \
            f"Case {case}: resolve_build_order must return BuildOrder"
        actual = list(result.ordered_modules)
        assert actual == expected, \
            f"Case {case}: expected deterministic order {expected}, got {actual}"
        assert len(actual) == len(names)
        positions = {name: i for i, name in enumerate(actual)}
        for name, deps in dependencies.items():
            for dep in deps:
                assert positions[dep] < positions[name]


def test_many_runtime_generated_cycles():
    pb2, resolve_build_order = load_submission()
    rng = random.Random(secrets.randbits(128))

    for case in range(20):
        cycle_size = rng.randint(2, 12)
        extra_size = rng.randint(0, 8)
        prefix = secrets.token_hex(4)
        cycle = [f"{prefix}_cycle_{i}" for i in range(cycle_size)]
        extras = [f"{prefix}_extra_{i}" for i in range(extra_size)]
        names = cycle + extras
        dependencies = {name: [] for name in names}

        for i, name in enumerate(cycle):
            dependencies[name].append(cycle[i - 1])
        for i, name in enumerate(extras):
            possible = cycle + extras[:i]
            if possible and rng.random() < 0.7:
                dependencies[name].append(rng.choice(possible))

        module_order = names[:]
        rng.shuffle(module_order)
        graph = make_graph(pb2, module_order, dependencies)
        with pytest.raises(ValueError) as excinfo:
            resolve_build_order(graph)
        assert str(excinfo.value) == "Cycle detected", \
            f"Case {case}: wrong cycle error: {excinfo.value!r}"
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
if [ "$?" -ne 0 ]; then
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
