#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tempfile
import uuid
import pytest

RESOLVER = "/home/user/resolve_deps.sh"
FUZZER = "/home/user/fuzzer.sh"
REPRO = "/home/user/repro_db.txt"


def run_resolver(target, lines, timeout=3):
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as f:
        f.write("\n".join(lines) + "\n")
        db_path = f.name
    try:
        return subprocess.run(
            [RESOLVER, target, db_path],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    finally:
        os.remove(db_path)


def random_names(count):
    prefix = "N" + uuid.uuid4().hex[:10]
    return [f"{prefix}{i}" for i in range(count)]


def validate_graph(text):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    assert len(lines) >= 2, "Fuzzer-generated database is not a meaningful graph"
    has_edge = False
    for line in lines:
        assert line.count(":") == 1, f"Invalid dependency database line: {line!r}"
        item, deps = line.split(":", 1)
        assert re.fullmatch(r"[A-Za-z0-9_.-]+", item), f"Invalid item name: {item!r}"
        if deps:
            has_edge = True
            for dep in deps.split(","):
                assert re.fullmatch(r"[A-Za-z0-9_.-]+", dep), f"Invalid dependency name: {dep!r}"
    assert has_edge, "Fuzzer-generated graph contains no dependencies"


def test_fuzzer_script_exists():
    assert os.path.isfile(FUZZER), f"Fuzzer script not found at {FUZZER}"


def test_fuzzer_is_bash_and_actually_fuzzes_resolver():
    with open(FUZZER, "r", errors="replace") as f:
        source = f.read()
    assert source.strip(), "fuzzer.sh is empty"
    assert source.startswith("#!") and "bash" in source.splitlines()[0], "fuzzer.sh must be a Bash script"
    assert not re.search(r"(^|[;&|]\s*)(python[0-9]*|perl|ruby|node)(\s|$)", source, re.M), \
        "fuzzer.sh must use Bash and standard coreutils only"

    with open(RESOLVER, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(RESOLVER).st_mode)

    probe_dir = tempfile.mkdtemp(prefix="fuzzer_probe_")
    wrapper = f'''#!/bin/bash
set -u
probe={probe_dir!r}
n=$(find "$probe" -maxdepth 1 -name 'graph_*' | wc -l)
printf '%s\n' "${{1-}}" > "$probe/target_$n"
if [[ -n "${{2-}}" && -f "$2" ]]; then
    cp "$2" "$probe/graph_$n"
fi
exit 124
'''

    observations = []
    try:
        with open(RESOLVER, "w") as f:
            f.write(wrapper)
        os.chmod(RESOLVER, 0o755)

        for run_number in range(2):
            before = set(os.listdir(probe_dir))
            result = subprocess.run(
                ["bash", "-x", FUZZER],
                capture_output=True,
                text=True,
                timeout=15,
                env={**os.environ, "HOME": "/home/user"},
            )
            after = set(os.listdir(probe_dir))
            graph_files = sorted(
                name for name in after - before if name.startswith("graph_")
            )
            assert graph_files, "fuzzer.sh never invoked /home/user/resolve_deps.sh with a database"

            trace = result.stderr
            assert any("timeout" in line and "resolve_deps.sh" in line for line in trace.splitlines()), \
                "fuzzer.sh did not run resolve_deps.sh through a timeout"

            report = result.stdout + "\n" + result.stderr
            assert re.search(r"timeout|timed out|hang|failure|failed|problem|issue|detected|124", report, re.I), \
                "fuzzer.sh did not identify/report the simulated resolver failure"

            generated = []
            for name in graph_files:
                with open(os.path.join(probe_dir, name), "r", errors="replace") as f:
                    graph = f.read()
                validate_graph(graph)
                generated.append(graph)
            observations.append(tuple(generated))

        assert observations[0] != observations[1], \
            "Repeated fuzzer runs generated identical graph data; graphs must be random"
    finally:
        with open(RESOLVER, "wb") as f:
            f.write(original)
        os.chmod(RESOLVER, original_mode)
        for name in os.listdir(probe_dir):
            os.remove(os.path.join(probe_dir, name))
        os.rmdir(probe_dir)


def test_repro_db_exists():
    assert os.path.isfile(REPRO), f"Reproducible DB not found at {REPRO}"


def test_resolve_deps_executable():
    assert os.path.isfile(RESOLVER), f"Missing file: {RESOLVER}"
    st = os.stat(RESOLVER)
    assert bool(st.st_mode & stat.S_IXUSR), f"File is not executable: {RESOLVER}"


def test_circular_dependency_handling():
    result = run_resolver("A", ["A:B", "B:C", "C:A"])
    assert result.returncode == 1, f"Expected exit code 1 for circular dependency, got {result.returncode}"
    assert "Error: Circular dependency detected for A" in result.stderr, "Expected correct error message in stderr"


def test_normal_dependency_handling():
    result = run_resolver("X", ["X:Y", "Y:Z", "Z:"])
    assert result.returncode == 0, f"Expected exit code 0 for normal dependency, got {result.returncode}"


def test_randomized_cycles_report_the_revisited_item():
    for cycle_size in range(1, 7):
        names = random_names(cycle_size + 4)
        root, prefix = names[0], names[1]
        cycle = names[2:2 + cycle_size]
        leaf = names[-1]
        lines = [f"{root}:{prefix},{leaf}", f"{prefix}:{cycle[0]}"]
        for i, item in enumerate(cycle):
            lines.append(f"{item}:{cycle[(i + 1) % len(cycle)]}")
        lines.append(f"{leaf}:")

        result = run_resolver(root, lines)
        expected = f"Error: Circular dependency detected for {cycle[0]}"
        assert result.returncode == 1, f"Cycle of size {cycle_size} was not rejected"
        assert expected in result.stderr, f"Expected {expected!r}, got stderr {result.stderr!r}"


def test_randomized_acyclic_graphs_and_shared_dependencies_succeed():
    for _ in range(5):
        n = random_names(9)
        lines = [
            f"{n[0]}:{n[1]},{n[2]},{n[1]}",
            f"{n[1]}:{n[3]},{n[4]}",
            f"{n[2]}:{n[4]},{n[5]}",
            f"{n[3]}:{n[6]}",
            f"{n[4]}:{n[6]},{n[7]}",
            f"{n[5]}:{n[7]}",
            f"{n[6]}:{n[8]}",
            f"{n[7]}:{n[8]}",
            f"{n[8]}:",
        ]
        result = run_resolver(n[0], lines)
        assert result.returncode == 0, \
            f"Acyclic graph with shared dependencies failed: {result.stderr!r}"
        assert "Circular dependency detected" not in result.stderr


def test_repro_db_triggers_cycle():
    assert os.path.isfile(REPRO), f"Reproducible DB not found at {REPRO}"
    targets = []
    with open(REPRO, "r") as f:
        for line in f:
            line = line.strip()
            if ":" in line:
                targets.append(line.split(":", 1)[0])

    assert targets, "repro_db.txt is empty or improperly formatted"

    cycle_detected = False
    for target in targets:
        try:
            result = subprocess.run(
                [RESOLVER, target, REPRO],
                capture_output=True,
                text=True,
                timeout=3,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("repro_db.txt caused the resolver to hang instead of detecting its cycle")
        if result.returncode == 1 and "Error: Circular dependency detected" in result.stderr:
            cycle_detected = True
            break

    assert cycle_detected, "repro_db.txt did not trigger a circular dependency error for any of its targets"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
