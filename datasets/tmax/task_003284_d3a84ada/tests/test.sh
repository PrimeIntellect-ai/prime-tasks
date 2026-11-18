#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import tempfile

AGENT_DIR = "/home/user/analyzer"
AGENT_PATH = os.path.join(AGENT_DIR, "target/release/analyzer")
LIB_DIR = "/app/libfastdir"
LIB_PATH = os.path.join(LIB_DIR, "libfastdir.a")


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=120, **kwargs)


def assert_builds_from_source():
    make_clean = run(["make", "clean"], cwd=LIB_DIR)
    assert make_clean.returncode == 0, make_clean.stdout + make_clean.stderr

    make_build = run(["make"], cwd=LIB_DIR)
    assert make_build.returncode == 0, make_build.stdout + make_build.stderr
    assert os.path.isfile(LIB_PATH), f"Static library not found at {LIB_PATH}"

    archive = run(["ar", "t", LIB_PATH])
    assert archive.returncode == 0, archive.stdout + archive.stderr
    assert "fastdir.o" in archive.stdout.splitlines(), "libfastdir.a does not contain fastdir.o"

    clean = run(["cargo", "clean"], cwd=AGENT_DIR)
    assert clean.returncode == 0, clean.stdout + clean.stderr
    build = run(["cargo", "build", "--release"], cwd=AGENT_DIR)
    assert build.returncode == 0, build.stdout + build.stderr


def assert_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable at {AGENT_PATH} is not executable"
    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Release analyzer is not an ELF executable"


def invoke(directory):
    return subprocess.run(
        [AGENT_PATH, directory], capture_output=True, text=True, timeout=10
    )


def check_dag(directory, filenames, edges):
    proc = invoke(directory)
    assert proc.returncode == 0, (
        f"analyzer exited with {proc.returncode}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )

    output = proc.stdout.splitlines()
    expected_nodes = set(filenames)
    expected_nodes.update(dep for _, dep in edges)

    assert "CYCLE DETECTED" not in output, f"Acyclic graph reported as cyclic: {proc.stdout!r}"
    assert len(output) == len(set(output)), f"Duplicate output nodes: {output!r}"
    assert set(output) == expected_nodes, (
        f"Wrong output node set. Expected {expected_nodes!r}, got {set(output)!r}"
    )

    positions = {name: i for i, name in enumerate(output)}
    for source, dependency in edges:
        assert positions[source] < positions[dependency], (
            f"Invalid topological order for edge {source!r} -> {dependency!r}: {output!r}"
        )


def test_random_dags():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory() as root:
        for case in range(30):
            directory = os.path.join(root, f"case_{case}")
            os.makedirs(directory)
            count = rng.randint(5, 16)
            names = []
            while len(names) < count:
                name = "".join(rng.choice(string.ascii_lowercase) for _ in range(10)) + ".txt"
                if name not in names:
                    names.append(name)

            edges = []
            for i, name in enumerate(names):
                possible = names[i + 1:]
                if possible:
                    for dependency in rng.sample(possible, rng.randint(0, min(3, len(possible)))):
                        edges.append((name, dependency))

            for name in names:
                with open(os.path.join(directory, name), "w", encoding="utf-8") as f:
                    f.write("ordinary text that is not a dependency\n")
                    for source, dependency in edges:
                        if source == name:
                            f.write(f'include "{dependency}"\n')

            check_dag(directory, names, edges)


def test_missing_dependency_is_a_graph_node():
    with tempfile.TemporaryDirectory() as directory:
        with open(os.path.join(directory, "root.txt"), "w", encoding="utf-8") as f:
            f.write('include "not-present.txt"\n')
        with open(os.path.join(directory, "independent.txt"), "w", encoding="utf-8") as f:
            f.write("no includes\n")
        check_dag(
            directory,
            ["root.txt", "independent.txt"],
            [("root.txt", "not-present.txt")],
        )


def test_cycle():
    with tempfile.TemporaryDirectory() as directory:
        with open(os.path.join(directory, "alpha.txt"), "w", encoding="utf-8") as f:
            f.write('include "beta.txt"\n')
        with open(os.path.join(directory, "beta.txt"), "w", encoding="utf-8") as f:
            f.write('include "gamma.txt"\n')
        with open(os.path.join(directory, "gamma.txt"), "w", encoding="utf-8") as f:
            f.write('include "alpha.txt"\n')

        proc = invoke(directory)
        assert proc.returncode == 0, (
            f"Cycle case exited with {proc.returncode}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
        assert proc.stdout.splitlines() == ["CYCLE DETECTED"], (
            f"Cycle output was not exactly CYCLE DETECTED: {proc.stdout!r}"
        )


assert_builds_from_source()
assert_executable_exists()
test_random_dags()
test_missing_dependency_is_a_graph_node()
test_cycle()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
