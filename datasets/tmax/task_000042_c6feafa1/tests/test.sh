#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH=/opt/cargo/bin:$PATH

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import stat
import subprocess
import tempfile
import time

BIN_PATH = "/home/user/auditor_bin"
MANIFEST_PATH = "/app/route-auth-auditor/Cargo.toml"
DECODER_PATH = "/app/route-auth-auditor/src/decoder.rs"
FIXTURE_PATH = "/app/test_data/large_gateway.json"


def run_binary(fixture, timeout=2.0):
    start = time.perf_counter()
    try:
        res = subprocess.run(
            [BIN_PATH, fixture], capture_output=True, text=True, timeout=timeout
        )
    except subprocess.TimeoutExpired:
        raise AssertionError(f"Binary did not finish within {timeout} seconds")
    return res, time.perf_counter() - start


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.digest()


def test_01_auditor_bin_exists():
    assert os.path.isfile(BIN_PATH), f"The executable {BIN_PATH} is missing. Did you compile and copy it?"
    assert not os.path.islink(BIN_PATH), f"{BIN_PATH} must be the copied release executable, not a symlink"
    assert stat.S_ISREG(os.stat(BIN_PATH).st_mode), f"{BIN_PATH} is not a regular file"
    assert os.access(BIN_PATH, os.X_OK), f"The file {BIN_PATH} is not executable."
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BIN_PATH} is not a compiled ELF executable"


def test_02_cargo_test_passes():
    assert os.path.isfile(MANIFEST_PATH), f"Cargo.toml missing at {MANIFEST_PATH}"
    test_res = subprocess.run(
        ["cargo", "test", "--manifest-path", MANIFEST_PATH],
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert test_res.returncode == 0, (
        f"Unit tests failed. Cargo test output:\n{test_res.stdout}\n{test_res.stderr}"
    )


def test_03_decoder_on_derived_inputs():
    assert os.path.isfile(DECODER_PATH), f"Decoder source missing at {DECODER_PATH}"
    rng = random.SystemRandom()
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !+/?=&:,_-"
    assertions = []
    for _ in range(30):
        plain = "".join(rng.choice(alphabet) for _ in range(rng.randint(4, 40)))
        encoded_parts = []
        encoded_any = False
        for ch in plain:
            must_encode = ch in " !+/?=&:,_-"
            if must_encode or rng.random() < 0.35:
                hx = f"{ord(ch):02X}"
                hx = "".join(c.lower() if c.isalpha() and rng.random() < 0.5 else c for c in hx)
                encoded_parts.append("%" + hx)
                encoded_any = True
            else:
                encoded_parts.append(ch)
        if not encoded_any:
            encoded_parts[0] = f"%{ord(plain[0]):02X}"
        encoded = "".join(encoded_parts)
        assertions.append(
            f"assert_eq!(decoder::percent_decode({json.dumps(encoded)}), {json.dumps(plain)});"
        )

    with tempfile.TemporaryDirectory() as td:
        runner = os.path.join(td, "decoder_check.rs")
        executable = os.path.join(td, "decoder_check")
        with open(runner, "w") as f:
            f.write(f'#[path = "{DECODER_PATH}"]\nmod decoder;\nfn main() {{\n')
            f.write("\n".join(assertions))
            f.write("\n}\n")
        compiled = subprocess.run(
            ["rustc", "--edition=2021", runner, "-o", executable],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert compiled.returncode == 0, (
            f"Could not compile decoder checks:\n{compiled.stdout}\n{compiled.stderr}"
        )
        checked = subprocess.run([executable], capture_output=True, text=True, timeout=10)
        assert checked.returncode == 0, (
            f"Percent decoding failed on verifier-derived inputs:\n"
            f"{checked.stdout}\n{checked.stderr}"
        )


def test_04_binary_matches_fresh_release_build():
    clean = subprocess.run(
        ["cargo", "clean", "--manifest-path", MANIFEST_PATH],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert clean.returncode == 0, f"cargo clean failed:\n{clean.stdout}\n{clean.stderr}"
    build = subprocess.run(
        ["cargo", "build", "--release", "--manifest-path", MANIFEST_PATH],
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert build.returncode == 0, f"Release build failed:\n{build.stdout}\n{build.stderr}"
    rebuilt = "/app/route-auth-auditor/target/release/route-auth-auditor"
    assert os.path.isfile(rebuilt), f"Release build did not produce {rebuilt}"
    assert file_hash(BIN_PATH) == file_hash(rebuilt), (
        f"{BIN_PATH} is not the executable produced by a fresh release build of the submitted package"
    )


def test_05_original_fixture_execution_time_and_correctness():
    assert os.path.isfile(FIXTURE_PATH), f"Test fixture missing at {FIXTURE_PATH}"
    res, elapsed = run_binary(FIXTURE_PATH)
    assert res.returncode == 0, f"Binary failed to execute. stderr:\n{res.stderr}"
    assert elapsed <= 0.25, (
        f"Execution time {elapsed:.4f}s exceeded threshold of 0.25s. "
        "The graph traversal is likely still exponential (unmemoized)."
    )
    assert "Root auth evaluated to: true" in res.stdout, (
        f"Binary did not produce the expected output. stdout:\n{res.stdout}"
    )


def make_correctness_graph(rng, wanted):
    count = rng.randint(35, 70)
    graph = {}
    for i in range(count):
        candidates = list(range(i))
        dep_count = rng.randint(0, min(4, len(candidates)))
        deps = rng.sample(candidates, dep_count) if dep_count else []
        graph[f"n{i}"] = {
            "base_auth": bool(rng.getrandbits(1)),
            "dependencies": [f"n{x}" for x in deps],
        }
    root_deps = [f"n{x}" for x in rng.sample(range(max(1, count // 2), count), 4)]
    graph["root"] = {"base_auth": True, "dependencies": root_deps}

    reachable = set()
    stack = ["root"]
    while stack:
        node = stack.pop()
        if node in reachable:
            continue
        reachable.add(node)
        stack.extend(graph[node]["dependencies"])

    for node in reachable:
        graph[node]["base_auth"] = True
    if wanted is False:
        victim = rng.choice(sorted(reachable - {"root"}))
        graph[victim]["base_auth"] = False
    for node in set(graph) - reachable:
        graph[node]["base_auth"] = bool(rng.getrandbits(1))
    return graph


def evaluate_expected(graph, node="root"):
    memo = {}
    def visit(name):
        if name not in memo:
            data = graph[name]
            memo[name] = data["base_auth"] and all(visit(d) for d in data["dependencies"])
        return memo[name]
    return visit(node)


def test_06_graph_correctness_on_derived_inputs():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory() as td:
        for index, wanted in enumerate([True, False, True, False, False, True]):
            graph = make_correctness_graph(rng, wanted)
            expected = evaluate_expected(graph)
            assert expected is wanted
            fixture = os.path.join(td, f"graph_{index}.json")
            with open(fixture, "w") as f:
                json.dump(graph, f)
            res, _ = run_binary(fixture)
            assert res.returncode == 0, f"Binary failed for derived graph: {res.stderr}"
            expected_line = f"Root auth evaluated to: {str(expected).lower()}"
            assert res.stdout.strip() == expected_line, (
                f"Wrong result for a verifier-derived graph. Expected {expected_line!r}, "
                f"got {res.stdout!r}"
            )


def test_07_memoized_performance_on_generated_fixture():
    graph = {}
    depth = random.SystemRandom().randint(50, 56)
    graph["p0"] = {"base_auth": True, "dependencies": []}
    for i in range(1, depth):
        graph[f"p{i}"] = {
            "base_auth": True,
            "dependencies": [f"p{i-1}", f"p{i-1}"],
        }
    graph["root"] = {
        "base_auth": True,
        "dependencies": [f"p{depth-1}", f"p{depth-1}"],
    }
    with tempfile.TemporaryDirectory() as td:
        fixture = os.path.join(td, "generated_large_gateway.json")
        with open(fixture, "w") as f:
            json.dump(graph, f)
        res, elapsed = run_binary(fixture)
    assert res.returncode == 0, f"Binary failed on generated performance graph: {res.stderr}"
    assert res.stdout.strip() == "Root auth evaluated to: true", res.stdout
    assert elapsed < 0.25, (
        f"Generated diamond graph took {elapsed:.4f}s; traversal is not O(N)"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
