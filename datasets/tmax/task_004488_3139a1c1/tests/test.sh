#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import secrets
import string
import subprocess
import tempfile

VERIFIER = "/home/user/pipeline/verifier.py"
HASH_MODULE = "/home/user/pipeline/hash.py"
ROOT = "com.mobile.core.app"


def fnv1a(data):
    value = 0x811C9DC5
    for char in data:
        value ^= ord(char)
        value = (value * 0x01000193) & 0xFFFFFFFF
    return f"{value:08x}"


def run_verifier(path, cwd=None):
    return subprocess.run(
        ["python3", VERIFIER, path],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=8,
    )


def write_graph(directory, graph):
    path = os.path.join(directory, secrets.token_hex(10) + ".json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(graph, handle)
    return path


def test_verifier_script_exists():
    assert os.path.isfile(VERIFIER), f"Missing required script: {VERIFIER}"


def test_hash_script_exists_and_implements_algorithm():
    assert os.path.isfile(HASH_MODULE), f"Missing required script: {HASH_MODULE}"
    spec = importlib.util.spec_from_file_location("submitted_pipeline_hash", HASH_MODULE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "calculate_hash", None)), "calculate_hash is missing or not callable"

    samples = ["", "a", "hello", ROOT, "alpha,beta,gamma"]
    alphabet = string.ascii_letters + string.digits + "._,-"
    for _ in range(20):
        samples.append("".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(100))))

    for sample in samples:
        actual = module.calculate_hash(sample)
        assert isinstance(actual, str), "calculate_hash must return a string"
        assert actual == fnv1a(sample), f"Incorrect hash for input {sample!r}"


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.json')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.json')]

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_clean = []
    for cf in clean_files:
        result = run_verifier(cf)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(cf))

    failed_evil = []
    for ef in evil_files:
        result = run_verifier(ef)
        if result.returncode == 0:
            failed_evil.append(os.path.basename(ef))

    error_messages = []
    if failed_clean:
        error_messages.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        error_messages.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed/accepted: {', '.join(failed_evil)}")

    assert not failed_clean and not failed_evil, " | ".join(error_messages)


def test_generated_graphs_from_unpredictable_paths():
    with tempfile.TemporaryDirectory(prefix="pipeline-check-") as directory:
        # Exercise several freshly generated DAGs with branching, sharing, and
        # non-root expected_hash values that must be ignored.
        for _ in range(8):
            count = 4 + secrets.randbelow(10)
            names = ["mod_" + secrets.token_hex(6) for _ in range(count)]
            graph = {
                ROOT: {"deps": [], "expected_hash": ""},
            }
            for name in names:
                graph[name] = {"deps": [], "expected_hash": secrets.token_hex(4)}

            all_nodes = [ROOT] + names
            # Give every generated module a parent among earlier nodes, making
            # every module reachable while preserving acyclicity.
            for index, name in enumerate(names, start=1):
                parent = all_nodes[secrets.randbelow(index)]
                graph[parent]["deps"].append(name)

            # Add extra forward edges to test shared transitive dependencies.
            for left in range(len(all_nodes)):
                for right in range(left + 1, len(all_nodes)):
                    if secrets.randbelow(7) == 0:
                        child = all_nodes[right]
                        if child not in graph[all_nodes[left]]["deps"]:
                            graph[all_nodes[left]]["deps"].append(child)

            graph[ROOT]["expected_hash"] = fnv1a(",".join(sorted(all_nodes)))
            valid_path = write_graph(directory, graph)
            assert run_verifier(valid_path, cwd=directory).returncode == 0, "Fresh valid DAG was rejected"

            bad_hash_graph = json.loads(json.dumps(graph))
            bad_hash_graph[ROOT]["expected_hash"] = secrets.token_hex(4)
            while bad_hash_graph[ROOT]["expected_hash"] == graph[ROOT]["expected_hash"]:
                bad_hash_graph[ROOT]["expected_hash"] = secrets.token_hex(4)
            bad_path = write_graph(directory, bad_hash_graph)
            assert run_verifier(bad_path, cwd=directory).returncode != 0, "Fresh bad hash was accepted"

        # A reachable cycle has the otherwise-correct checksum, so rejection
        # requires cycle detection rather than merely spotting a fixed hash.
        cycle_names = ["cycle_" + secrets.token_hex(6) for _ in range(5)]
        cycle_graph = {ROOT: {"deps": [cycle_names[0]], "expected_hash": ""}}
        for index, name in enumerate(cycle_names):
            next_name = cycle_names[index + 1] if index + 1 < len(cycle_names) else cycle_names[0]
            cycle_graph[name] = {"deps": [next_name], "expected_hash": ""}
        cycle_graph[ROOT]["expected_hash"] = fnv1a(",".join(sorted([ROOT] + cycle_names)))
        cycle_path = write_graph(directory, cycle_graph)
        assert run_verifier(cycle_path, cwd=directory).returncode != 0, "Fresh reachable cycle was accepted"

        # Cycles outside the root's reachable subgraph do not invalidate the update.
        live = "live_" + secrets.token_hex(6)
        dead_a = "dead_" + secrets.token_hex(6)
        dead_b = "dead_" + secrets.token_hex(6)
        scoped_graph = {
            ROOT: {"deps": [live], "expected_hash": fnv1a(",".join(sorted([ROOT, live])))},
            live: {"deps": [], "expected_hash": "ignored"},
            dead_a: {"deps": [dead_b], "expected_hash": ""},
            dead_b: {"deps": [dead_a], "expected_hash": ""},
        }
        scoped_path = write_graph(directory, scoped_graph)
        assert run_verifier(scoped_path, cwd=directory).returncode == 0, "Unreachable modules incorrectly affected verification"


def test_malformed_input_is_not_accepted():
    with tempfile.TemporaryDirectory(prefix="pipeline-malformed-") as directory:
        malformed = os.path.join(directory, secrets.token_hex(8) + ".json")
        with open(malformed, "w", encoding="utf-8") as handle:
            handle.write("{not valid json")
        assert run_verifier(malformed, cwd=directory).returncode != 0

        missing_root = write_graph(directory, {"other": {"deps": [], "expected_hash": fnv1a("other")}})
        assert run_verifier(missing_root, cwd=directory).returncode != 0
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
