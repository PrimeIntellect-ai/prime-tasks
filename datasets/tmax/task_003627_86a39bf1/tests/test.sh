#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import random
import shutil
import string
import subprocess
import tempfile
from pathlib import Path

import networkx as nx
import pytest

DETECTOR = "/home/user/detector.py"
VENDORED = "/app/vendored/py-graph-ext-1.2"


def expected_label(rows):
    graph = nx.Graph()
    for source, target, amount, timestamp in rows:
        graph.add_edge(str(source), str(target))

    centrality = nx.betweenness_centrality(graph)
    high_centrality = any(value > 0.45 for value in centrality.values())

    high_velocity = False
    for source, target, amount, timestamp in rows:
        velocity = sum(
            float(other_amount)
            for other_source, _, other_amount, other_timestamp in rows
            if str(other_source) == str(source)
            and float(timestamp) - 3600 <= float(other_timestamp) <= float(timestamp)
        )
        if velocity > 10000:
            high_velocity = True
            break

    return "FRAUD" if high_centrality and high_velocity else "NORMAL"


def write_csv(path, rows):
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["source_id", "target_id", "amount", "timestamp"])
        writer.writerows(rows)


def random_token(prefix):
    return prefix + "_" + "".join(random.SystemRandom().choice(string.ascii_letters) for _ in range(12))


@pytest.fixture(scope="session")
def generated_cases():
    root = Path(tempfile.mkdtemp(prefix="network_inputs_"))
    base = random.SystemRandom().randint(100000, 900000)

    def nodes(count):
        return [random_token("node") for _ in range(count)]

    cases = []

    # High centrality and high velocity: fraudulent.
    a, b, c, d = nodes(4)
    cases.append([
        (a, b, 4000, base),
        (a, b, 4000, base + 100),
        (a, b, 4001, base + 200),
        (b, c, 25, base + 300),
        (c, d, 25, base + 400),
    ])

    # High velocity without high centrality: normal triangle.
    a, b, c = nodes(3)
    cases.append([
        (a, b, 6000, base + 10),
        (a, b, 6000, base + 20),
        (b, c, 10, base + 30),
        (c, a, 10, base + 40),
    ])

    # High centrality without high velocity: normal path.
    a, b, c, d, e = nodes(5)
    cases.append([
        (a, b, 100, base + 1),
        (b, c, 100, base + 2),
        (c, d, 100, base + 3),
        (d, e, 100, base + 4),
    ])

    # Large amounts outside the sixty-minute window: normal.
    a, b, c, d = nodes(4)
    cases.append([
        (a, b, 6000, base),
        (a, b, 6000, base + 3601),
        (b, c, 10, base + 3602),
        (c, d, 10, base + 3603),
    ])

    # Centrality and velocity may be witnessed by different parts of the graph.
    a, b, c, d, e = nodes(5)
    cases.append([
        (a, b, 5500, base + 50),
        (a, b, 5501, base + 60),
        (b, c, 10, base + 70),
        (b, d, 10, base + 80),
        (b, e, 10, base + 90),
    ])

    result = []
    for rows in cases:
        path = root / (random_token("input") + ".csv")
        write_csv(path, rows)
        result.append((path, expected_label(rows)))

    # Replace the initially empty, writable corpus with verifier-controlled data,
    # retaining the original labeled-corpus assertions.
    for directory in (Path("/app/corpus/evil"), Path("/app/corpus/clean")):
        if directory.is_symlink() or directory.is_file():
            directory.unlink()
        elif directory.exists():
            shutil.rmtree(directory)
        directory.mkdir(parents=True)

    for path, label in result:
        destination = Path("/app/corpus/evil" if label == "FRAUD" else "/app/corpus/clean")
        shutil.copyfile(path, destination / path.name)

    yield result
    shutil.rmtree(root, ignore_errors=True)


def make_instrumentation(root):
    package = root / "py_graph_ext"
    package.mkdir()
    (package / "__init__.py").write_text("from .graph import Graph\n")
    (package / "centrality.py").write_text(
        "import networkx as nx\n"
        "def compute_betweenness(graph):\n"
        "    return nx.betweenness_centrality(graph)\n"
    )
    (package / "graph.py").write_text(r'''
import json
import os
import networkx as nx


def _record(event):
    marker = os.environ.get("DETECTOR_MARKER")
    if marker:
        with open(marker, "a") as handle:
            handle.write(json.dumps(event) + "\n")


class Graph:
    def __init__(self):
        self._g = nx.Graph()
        _record({"kind": "graph_init"})

    def add_edge(self, u, v):
        self._g.add_edge(u, v)
        _record({"kind": "graph_add_edge"})

    def add_node(self, u):
        self._g.add_node(u)
        _record({"kind": "graph_add_node"})

    def compute_betweenness(self):
        _record({"kind": "graph_compute_betweenness"})
        return nx.betweenness_centrality(self._g)
''')

    (root / "sitecustomize.py").write_text(r'''
import json
import os
import sqlite3

_real_connect = sqlite3.connect
_MISSING = object()


def _record(event):
    marker = os.environ.get("DETECTOR_MARKER")
    if marker:
        with open(marker, "a") as handle:
            handle.write(json.dumps(event) + "\n")


def _sql(sql, params=_MISSING):
    _record({
        "kind": "sql",
        "text": str(sql),
        "parameterized": params is not _MISSING,
    })


class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, params=_MISSING):
        _sql(sql, params)
        if params is _MISSING:
            return self._cursor.execute(sql)
        return self._cursor.execute(sql, params)

    def executemany(self, sql, params):
        _sql(sql, params)
        return self._cursor.executemany(sql, params)

    def executescript(self, sql):
        _sql(sql)
        return self._cursor.executescript(sql)

    def __iter__(self):
        return iter(self._cursor)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return self._cursor.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._cursor, name)


class ConnectionProxy:
    def __init__(self, connection):
        self._connection = connection

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, params=_MISSING):
        _sql(sql, params)
        if params is _MISSING:
            return CursorProxy(self._connection.execute(sql))
        return CursorProxy(self._connection.execute(sql, params))

    def executemany(self, sql, params):
        _sql(sql, params)
        return CursorProxy(self._connection.executemany(sql, params))

    def executescript(self, sql):
        _sql(sql)
        return CursorProxy(self._connection.executescript(sql))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)


def connect(database, *args, **kwargs):
    _record({"kind": "sqlite_connect", "database": str(database)})
    return ConnectionProxy(_real_connect(database, *args, **kwargs))


sqlite3.connect = connect
''')


def run_instrumented(path, instrumentation):
    marker = Path(tempfile.mkstemp(prefix="detector_trace_", suffix=".jsonl")[1])
    marker.write_text("")
    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = str(instrumentation) + (os.pathsep + old_pythonpath if old_pythonpath else "")
    env["DETECTOR_MARKER"] = str(marker)
    try:
        result = subprocess.run(
            ["python3", DETECTOR, str(path)],
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
            cwd="/tmp",
        )
        events = [json.loads(line) for line in marker.read_text().splitlines() if line.strip()]
        return result, events
    finally:
        marker.unlink(missing_ok=True)


def test_detector_exists():
    assert os.path.isfile(DETECTOR), "The script /home/user/detector.py does not exist."
    assert os.path.isfile("/home/user/DONE"), "The file /home/user/DONE does not exist."


def test_vendored_library_is_fixed_and_editably_installable():
    install = subprocess.run(
        ["python3", "-m", "pip", "install", "-e", VENDORED],
        capture_output=True,
        text=True,
        timeout=60,
        env={k: v for k, v in os.environ.items() if k != "BUILD_PY_GRAPH_EXT"},
    )
    assert install.returncode == 0, install.stdout + install.stderr

    check = subprocess.run(
        ["python3", "-c", (
            "import pathlib, py_graph_ext; "
            "from py_graph_ext import Graph; "
            "p=pathlib.Path(py_graph_ext.__file__).resolve(); "
            "assert str(p).startswith('/app/vendored/py-graph-ext-1.2/'); "
            "g=Graph(); g.add_edge('a','b'); g.add_edge('b','c'); "
            "assert g.compute_betweenness()['b'] > 0.45"
        )],
        capture_output=True,
        text=True,
        timeout=10,
        cwd="/tmp",
        env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"},
    )
    assert check.returncode == 0, check.stdout + check.stderr


def test_detector_behavior_and_required_techniques(generated_cases):
    instrumentation = Path(tempfile.mkdtemp(prefix="detector_instrumentation_"))
    try:
        make_instrumentation(instrumentation)
        for path, expected in generated_cases:
            result, events = run_instrumented(path, instrumentation)
            assert result.returncode == 0, result.stderr
            assert result.stdout.strip() == expected
            assert result.stdout == expected + "\n", "Detector must print exactly one output line."

            assert any(e.get("kind") == "sqlite_connect" and e.get("database") == ":memory:" for e in events), \
                "Detector did not use an in-memory SQLite database."

            sql_events = [e for e in events if e.get("kind") == "sql"]
            normalized = [(e.get("text") or "").upper() for e in sql_events]
            assert any("CREATE" in sql and "INDEX" in sql for sql in normalized), \
                "Detector did not create an SQLite index."

            window_events = [
                (e, sql) for e, sql in zip(sql_events, normalized)
                if "SUM" in sql and "OVER" in sql and "PARTITION BY" in sql
                and "ORDER BY" in sql and "RANGE" in sql and "PRECEDING" in sql
            ]
            assert window_events, "Detector did not execute the required window-function velocity query."
            assert any(e.get("parameterized") for e, _ in window_events), \
                "The window-function query was not parameterized."

            kinds = [e.get("kind") for e in events]
            assert "graph_init" in kinds, "Detector did not instantiate py_graph_ext.Graph."
            assert "graph_add_edge" in kinds, "Detector did not load edges into py_graph_ext.Graph."
            assert "graph_compute_betweenness" in kinds, \
                "Detector did not use py_graph_ext.Graph.compute_betweenness()."
    finally:
        shutil.rmtree(instrumentation, ignore_errors=True)


def test_adversarial_corpus(generated_cases):
    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"

    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))

    assert evil_files, f"No CSV files found in evil corpus dir: {evil_dir}"
    assert clean_files, f"No CSV files found in clean corpus dir: {clean_dir}"

    evil_bypassed = []
    clean_modified = []

    for f in evil_files:
        try:
            result = subprocess.run(
                ["python3", DETECTOR, f], capture_output=True, text=True, timeout=10
            )
            output = result.stdout.strip()
            if output != "FRAUD":
                evil_bypassed.append((os.path.basename(f), output))
        except subprocess.TimeoutExpired:
            evil_bypassed.append((os.path.basename(f), "TIMEOUT"))
        except Exception as exc:
            evil_bypassed.append((os.path.basename(f), f"ERROR: {exc}"))

    for f in clean_files:
        try:
            result = subprocess.run(
                ["python3", DETECTOR, f], capture_output=True, text=True, timeout=10
            )
            output = result.stdout.strip()
            if output != "NORMAL":
                clean_modified.append((os.path.basename(f), output))
        except subprocess.TimeoutExpired:
            clean_modified.append((os.path.basename(f), "TIMEOUT"))
        except Exception as exc:
            clean_modified.append((os.path.basename(f), f"ERROR: {exc}"))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed. Offending files: " + ", ".join(x[0] for x in evil_bypassed[:10]))
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified. Offending files: " + ", ".join(x[0] for x in clean_modified[:10]))
    if errors:
        pytest.fail("\n".join(errors))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
