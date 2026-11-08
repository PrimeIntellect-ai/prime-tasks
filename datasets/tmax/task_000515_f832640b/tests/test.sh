#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

HEADER = "/app/json-3.11.2/single_include/nlohmann/json.hpp"
SOURCE = "/home/user/etl_filter.cpp"
BINARY = "/home/user/etl_filter"


def run_checked(command, timeout=30):
    try:
        return subprocess.run(command, check=True, capture_output=True, text=True, timeout=timeout)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Command failed: {command}\nStdout: {e.stdout}\nStderr: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {command}")


def test_json_header_fixed_and_compiles():
    assert os.path.isfile(HEADER), f"File {HEADER} does not exist."
    with open(HEADER, "r", encoding="utf-8") as f:
        content = f.read()
    assert "#define std::size_t int" not in content, "The malicious macro '#define std::size_t int' is still present in json.hpp."

    with tempfile.TemporaryDirectory() as td:
        probe = Path(td) / "probe.cpp"
        executable = Path(td) / "probe"
        probe.write_text(
            '#include <nlohmann/json.hpp>\n'
            'int main() { auto j = nlohmann::json::parse("{\\"x\\":1,\\"a\\":[true,null]}"); '
            'return (j["x"] == 1 && j["a"].size() == 2) ? 0 : 1; }\n',
            encoding="utf-8",
        )
        run_checked([
            "g++", "-std=c++17", "-I/app/json-3.11.2/single_include",
            str(probe), "-o", str(executable)
        ], timeout=60)
        run_checked([str(executable)])


def test_binary_exists():
    assert os.path.isfile(BINARY), f"Executable not found at {BINARY}."
    assert os.access(BINARY, os.X_OK), f"File at {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "etl_filter must be a compiled executable."


@pytest.fixture(scope="session")
def rebuilt_binary():
    assert os.path.isfile(SOURCE), f"Source file not found at {SOURCE}."
    td = tempfile.TemporaryDirectory()
    executable = Path(td.name) / "etl_filter_rebuilt"
    depfile = Path(td.name) / "deps.d"
    run_checked([
        "g++", "-std=c++17", "-I/app/json-3.11.2/single_include",
        "-MD", "-MF", str(depfile), SOURCE, "-o", str(executable)
    ], timeout=120)

    deps = depfile.read_text(encoding="utf-8").replace("\\\n", " ").split()
    header_real = os.path.realpath(HEADER)
    included = any(os.path.realpath(token.rstrip("\\")) == header_real for token in deps[1:])
    assert included, "etl_filter.cpp does not include the fixed vendored nlohmann/json header."

    yield str(executable)
    td.cleanup()


def test_adversarial_corpus_filtering():
    clean_corpus = "/app/data/clean/"
    evil_corpus = "/app/data/evil/"
    assert os.path.isdir(clean_corpus), "Clean corpus directory missing."
    assert os.path.isdir(evil_corpus), "Evil corpus directory missing."

    with tempfile.TemporaryDirectory() as clean_out, tempfile.TemporaryDirectory() as evil_out:
        run_checked([BINARY, clean_corpus, clean_out])
        run_checked([BINARY, evil_corpus, evil_out])

        clean_expected = {f for f in os.listdir(clean_corpus) if f.endswith('.json')}
        clean_actual = set(os.listdir(clean_out))
        missing_clean = clean_expected - clean_actual
        modified_clean = []
        for f in clean_actual.intersection(clean_expected):
            with open(os.path.join(clean_corpus, f), "r") as src, open(os.path.join(clean_out, f), "r") as dst:
                try:
                    if json.load(src) != json.load(dst):
                        modified_clean.append(f)
                except json.JSONDecodeError:
                    modified_clean.append(f)

        evil_expected = {f for f in os.listdir(evil_corpus) if f.endswith('.json')}
        evil_actual = set(os.listdir(evil_out))
        evil_bypassed = list(evil_actual)

        errors = []
        if missing_clean or modified_clean:
            errors.append(f"{len(missing_clean) + len(modified_clean)} of {len(clean_expected)} clean modified or rejected.")
            if missing_clean:
                errors.append(f"Missing clean files: {', '.join(missing_clean)}.")
            if modified_clean:
                errors.append(f"Modified clean files: {', '.join(modified_clean)}.")
        if evil_bypassed:
            errors.append(f"{len(evil_bypassed)} of {len(evil_expected)} evil bypassed.")
            errors.append(f"Bypassed evil files: {', '.join(evil_bypassed)}.")
        if errors:
            pytest.fail(" ".join(errors))


def oracle_reject(edges):
    if edges and sum(e["source"] == e["target"] for e in edges) * 2 > len(edges):
        return True

    adjacency = {}
    for edge in edges:
        source, target = edge["source"], edge["target"]
        adjacency.setdefault(source, set())
        adjacency.setdefault(target, set())
        if source != target:
            adjacency[source].add(target)
            adjacency[target].add(source)

    if not adjacency or not all(len(neighbors) == 2 for neighbors in adjacency.values()):
        return False

    start = next(iter(adjacency))
    seen = {start}
    stack = [start]
    while stack:
        node = stack.pop()
        for neighbor in adjacency[node]:
            if neighbor not in seen:
                seen.add(neighbor)
                stack.append(neighbor)
    return len(seen) == len(adjacency)


def make_runtime_corpus(directory):
    rng = random.SystemRandom()
    cases = []

    # Organic trees and stars: connected but not cycles.
    for _ in range(6):
        count = rng.randint(4, 10)
        nodes = [f"u_{secrets.token_hex(5)}" for _ in range(count)]
        edges = []
        for i in range(1, count):
            parent = rng.randrange(i)
            source, target = nodes[i], nodes[parent]
            if rng.randrange(2):
                source, target = target, source
            edges.append({"source": source, "target": target})
        rng.shuffle(edges)
        cases.append(edges)

    # Pure cycles of varying sizes.
    for _ in range(5):
        count = rng.randint(3, 11)
        nodes = [f"r_{secrets.token_hex(5)}" for _ in range(count)]
        edges = []
        for i in range(count):
            source, target = nodes[i], nodes[(i + 1) % count]
            if rng.randrange(2):
                source, target = target, source
            edges.append({"source": source, "target": target})
        rng.shuffle(edges)
        cases.append(edges)

    # Inputs where a strict majority of the original edge records are loops.
    for _ in range(5):
        nodes = [f"s_{secrets.token_hex(5)}" for _ in range(rng.randint(3, 8))]
        nonloops = rng.randint(1, 4)
        loop_count = nonloops + rng.randint(1, 4)
        edges = []
        for i in range(nonloops):
            edges.append({"source": nodes[i % len(nodes)], "target": nodes[(i + 1) % len(nodes)]})
        for _ in range(loop_count):
            node = rng.choice(nodes)
            edges.append({"source": node, "target": node})
        rng.shuffle(edges)
        cases.append(edges)

    # Additional random simple graphs; their outcomes are computed by the oracle.
    for _ in range(8):
        count = rng.randint(4, 9)
        nodes = [f"g_{secrets.token_hex(5)}" for _ in range(count)]
        possible = [(nodes[i], nodes[j]) for i in range(count) for j in range(i + 1, count)]
        rng.shuffle(possible)
        chosen = possible[:rng.randint(1, len(possible))]
        cases.append([{"source": a, "target": b} for a, b in chosen])

    expected = {}
    for edges in cases:
        filename = f"window_{secrets.token_hex(8)}.json"
        if rng.randrange(2):
            raw = json.dumps(edges, indent=rng.choice([1, 2, 4]), ensure_ascii=False) + "\n"
        else:
            raw = json.dumps(edges, separators=(",", ":"), ensure_ascii=False)
        (Path(directory) / filename).write_text(raw, encoding="utf-8")
        if not oracle_reject(edges):
            expected[filename] = raw.encode("utf-8")

    (Path(directory) / f"ignore_{secrets.token_hex(5)}.txt").write_text("not json", encoding="utf-8")
    assert expected and len(expected) < len(cases)
    return expected


def exercise_runtime_corpus(executable, input_dir, expected):
    with tempfile.TemporaryDirectory(prefix=f"result_{secrets.token_hex(4)}_") as output_dir:
        run_checked([executable, input_dir, output_dir], timeout=30)
        actual_names = set(os.listdir(output_dir))
        assert actual_names == set(expected), (
            f"Wrong accepted-file set. Expected {sorted(expected)}, got {sorted(actual_names)}"
        )
        for filename, original in expected.items():
            assert (Path(output_dir) / filename).read_bytes() == original, (
                f"Accepted file {filename} was not copied exactly as supplied."
            )


def test_runtime_generated_mixed_corpus(rebuilt_binary):
    with tempfile.TemporaryDirectory(prefix=f"incoming_{secrets.token_hex(6)}_") as input_dir:
        expected = make_runtime_corpus(input_dir)
        exercise_runtime_corpus(BINARY, input_dir, expected)
        exercise_runtime_corpus(rebuilt_binary, input_dir, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
