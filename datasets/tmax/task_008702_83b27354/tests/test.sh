#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import subprocess
import tempfile

import pytest

C_FILE = "/home/user/project_subgraph.c"
BIN_FILE = "/home/user/project_subgraph"
SH_FILE = "/home/user/query_pipeline.sh"
DATA_FILE = "/home/user/raw_edges.csv"
ORIGINAL_DATA = b"""10,20,100
20,30,100
30,40,100
40,50,100
10,15,40
15,25,100
20,10,100
30,20,100
30,60,60
60,70,80
70,80,90
"""
_COMPILED = False


def test_files_exist_and_permissions():
    assert os.path.isfile(C_FILE), f"{C_FILE} is missing."
    assert os.path.isfile(SH_FILE), f"{SH_FILE} is missing."
    assert os.access(SH_FILE, os.X_OK), f"{SH_FILE} is not executable."


def compile_c_program():
    global _COMPILED
    if not _COMPILED:
        result = subprocess.run(
            ["gcc", "-O3", C_FILE, "-o", BIN_FILE],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Failed to compile C program:\n{result.stderr}"
        assert os.path.isfile(BIN_FILE), f"{BIN_FILE} was not produced."
        assert os.access(BIN_FILE, os.X_OK), f"{BIN_FILE} is not executable."
        _COMPILED = True


def parse_output(stdout):
    return [line.strip() for line in stdout.splitlines() if line.strip()]


def run_pipeline(root, depth, min_weight):
    compile_c_program()
    result = subprocess.run(
        [SH_FILE, str(root), str(depth), str(min_weight)],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Pipeline script failed with error:\n{result.stderr}"
    return parse_output(result.stdout)


def expected_reachable(edges, root, depth):
    adjacency = {}
    for source, target in edges:
        adjacency.setdefault(source, []).append(target)
    seen = {root}
    frontier = {root}
    for _ in range(depth):
        next_frontier = set()
        for node in frontier:
            for target in adjacency.get(node, []):
                if target not in seen:
                    seen.add(target)
                    next_frontier.add(target)
        frontier = next_frontier
        if not frontier:
            break
    return [str(node) for node in sorted(seen)]


def run_c(edges, root, depth):
    compile_c_program()
    input_data = "".join(f"{source},{target}\n" for source, target in edges)
    result = subprocess.run(
        [BIN_FILE, "--root", str(root), "--depth", str(depth)],
        input=input_data,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"C program failed with error:\n{result.stderr}"
    return parse_output(result.stdout)


def test_pipeline_depth_constraint():
    with open(DATA_FILE, "wb") as f:
        f.write(ORIGINAL_DATA)
    expected = ["10", "15", "20", "25", "30"]
    output = run_pipeline(10, 2, 0)
    assert output == expected, f"Depth constraint test failed. Expected {expected}, got {output}"


def test_pipeline_weight_filtering():
    with open(DATA_FILE, "wb") as f:
        f.write(ORIGINAL_DATA)
    expected = ["10", "20", "30"]
    output = run_pipeline(10, 2, 50)
    assert output == expected, f"Weight filtering test failed. Expected {expected}, got {output}"


def test_pipeline_cycles_and_depth():
    with open(DATA_FILE, "wb") as f:
        f.write(ORIGINAL_DATA)
    expected = ["10", "20", "30", "40", "50"]
    output = run_pipeline(20, 3, 100)
    assert output == expected, f"Cycles and depth test failed. Expected {expected}, got {output}"


def test_c_program_on_runtime_generated_graphs():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    for _ in range(12):
        nodes = rng.sample(range(1, 100001), rng.randint(12, 55))
        root = rng.choice(nodes)
        depth = rng.randint(0, 8)
        edges = []
        for _ in range(rng.randint(30, 180)):
            edges.append((rng.choice(nodes), rng.choice(nodes)))
        # Explicitly include cycles, duplicate edges, and a path whose useful
        # length varies with the generated depth.
        cycle = rng.sample(nodes, 4)
        edges.extend([
            (cycle[0], cycle[1]),
            (cycle[1], cycle[2]),
            (cycle[2], cycle[3]),
            (cycle[3], cycle[0]),
            (cycle[0], cycle[1]),
        ])
        rng.shuffle(edges)
        expected = expected_reachable(edges, root, depth)
        output = run_c(edges, root, depth)
        assert output == expected, (
            f"Generated C graph failed for root={root}, depth={depth}. "
            f"Expected {expected}, got {output}"
        )


def test_pipeline_on_runtime_generated_datasets():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    old_data = open(DATA_FILE, "rb").read() if os.path.exists(DATA_FILE) else None
    try:
        for _ in range(10):
            nodes = rng.sample(range(1, 100001), rng.randint(15, 60))
            root = rng.choice(nodes)
            depth = rng.randint(0, 7)
            threshold = rng.randint(10, 190)
            weighted_edges = []
            for _ in range(rng.randint(40, 210)):
                weighted_edges.append((rng.choice(nodes), rng.choice(nodes), rng.randint(0, 220)))
            # Guarantee values immediately below, equal to, and above the
            # threshold so the strict weight boundary is exercised.
            a, b, c, d = rng.sample(nodes, 4)
            weighted_edges.extend([
                (root, a, threshold - 1),
                (root, b, threshold),
                (b, c, threshold + 1),
                (c, root, threshold),
                (c, d, threshold - 1),
            ])
            rng.shuffle(weighted_edges)
            with open(DATA_FILE, "w", encoding="ascii") as f:
                for source, target, weight in weighted_edges:
                    f.write(f"{source},{target},{weight}\n")
            filtered = [(s, t) for s, t, w in weighted_edges if w >= threshold]
            expected = expected_reachable(filtered, root, depth)
            output = run_pipeline(root, depth, threshold)
            assert output == expected, (
                f"Generated pipeline case failed for root={root}, depth={depth}, "
                f"min_weight={threshold}. Expected {expected}, got {output}"
            )
    finally:
        if old_data is None:
            if os.path.exists(DATA_FILE):
                os.unlink(DATA_FILE)
        else:
            with open(DATA_FILE, "wb") as f:
                f.write(old_data)


def test_pipeline_really_filters_strips_and_invokes_c_binary():
    compile_c_program()
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    root = rng.randint(5000, 90000)
    other = rng.sample([n for n in range(1, 100001) if n != root], 5)
    depth = 3
    threshold = rng.randint(50, 150)
    rows = [
        (root, other[0], threshold),
        (root, other[1], threshold - 1),
        (other[0], other[2], threshold + 9),
        (other[2], root, threshold),
        (other[2], other[3], threshold - 20),
        (other[3], other[4], threshold + 30),
    ]
    expected_clean = "".join(f"{s},{t}\n" for s, t, w in rows if w >= threshold)
    expected_nodes = expected_reachable(
        [(s, t) for s, t, w in rows if w >= threshold], root, depth
    )

    old_data = open(DATA_FILE, "rb").read() if os.path.exists(DATA_FILE) else None
    temp_dir = tempfile.mkdtemp(prefix="pipeline_probe_")
    real_binary = os.path.join(temp_dir, "real_project_subgraph")
    capture_file = os.path.join(temp_dir, "stdin.csv")
    args_file = os.path.join(temp_dir, "args.txt")
    try:
        with open(DATA_FILE, "w", encoding="ascii") as f:
            for source, target, weight in rows:
                f.write(f"{source},{target},{weight}\n")

        os.replace(BIN_FILE, real_binary)
        wrapper = f"""#!/bin/sh
printf '%s\\n' \"$@\" > {args_file!r}
cat > {capture_file!r}
exec {real_binary!r} \"$@\" < {capture_file!r}
"""
        with open(BIN_FILE, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(BIN_FILE, 0o755)

        result = subprocess.run(
            [SH_FILE, str(root), str(depth), str(threshold)],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"Pipeline probe failed:\n{result.stderr}"
        assert os.path.isfile(capture_file), "Pipeline did not invoke /home/user/project_subgraph."
        with open(args_file, encoding="utf-8") as f:
            actual_args = f.read().splitlines()
        assert actual_args == ["--root", str(root), "--depth", str(depth)], (
            f"C executable received incorrect arguments: {actual_args}"
        )
        with open(capture_file, encoding="ascii") as f:
            captured = f.read()
        assert captured == expected_clean, (
            "The data piped to the C executable was not the correctly filtered, "
            f"two-column edge list. Expected {expected_clean!r}, got {captured!r}"
        )
        assert parse_output(result.stdout) == expected_nodes
    finally:
        if os.path.lexists(BIN_FILE):
            os.unlink(BIN_FILE)
        if os.path.exists(real_binary):
            os.replace(real_binary, BIN_FILE)
        shutil.rmtree(temp_dir, ignore_errors=True)
        if old_data is None:
            if os.path.exists(DATA_FILE):
                os.unlink(DATA_FILE)
        else:
            with open(DATA_FILE, "wb") as f:
                f.write(old_data)


def test_pipeline_accepts_exactly_three_arguments():
    compile_c_program()
    for args in (["10", "2"], ["10", "2", "50", "extra"]):
        result = subprocess.run([SH_FILE, *args], capture_output=True, text=True, timeout=10)
        assert result.returncode != 0, f"Pipeline accepted invalid argument list: {args}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
