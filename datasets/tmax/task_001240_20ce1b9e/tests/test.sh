#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import string
import subprocess


def compute_expected_size(manifest_path, start_node="db_primary"):
    with open(manifest_path, 'r') as f:
        data = json.load(f)

    nodes = {}
    edges = {}

    for item in data:
        if item.get("type") == "node":
            nodes[item["id"]] = item["size"]
        elif item.get("type") == "edge":
            src = item["source"]
            tgt = item["target"]
            if src not in edges:
                edges[src] = []
            edges[src].append(tgt)

    total_size = 0
    visited = set()
    queue = [start_node]

    while queue:
        current = queue.pop(0)
        if current not in visited:
            visited.add(current)
            total_size += nodes.get(current, 0)
            for neighbor in edges.get(current, []):
                queue.append(neighbor)

    return total_size


def run_binary(binary_path):
    result = subprocess.run(
        [binary_path],
        cwd="/home/user/backup_graph",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=True,
    )
    return result.stdout.strip()


def test_project_builds_and_traversal_is_correct():
    project_path = "/home/user/backup_graph"
    manifest_path = "/home/user/backup_manifest.json"
    binary_path = os.path.join(project_path, "target", "release", "backup_graph")

    assert os.path.isdir(project_path), f"Missing Rust project at {project_path}"
    assert os.path.exists(os.path.join(project_path, "Cargo.toml")), "Missing Cargo.toml"
    assert os.path.exists(manifest_path), f"Manifest file missing at {manifest_path}"

    subprocess.run(
        ["cargo", "build", "--release", "--bin", "backup_graph"],
        cwd=project_path,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
        check=True,
    )

    assert os.path.isfile(binary_path), f"Built executable missing at {binary_path}"
    assert os.stat(binary_path).st_mode & stat.S_IXUSR, "Built artifact is not executable"

    with open(manifest_path, "rb") as f:
        original_manifest = f.read()

    try:
        expected_original = compute_expected_size(manifest_path)
        assert run_binary(binary_path) == str(expected_original), (
            "The built Rust program produced the wrong total for the supplied manifest"
        )

        rng = random.SystemRandom()
        alphabet = string.ascii_lowercase

        for _ in range(3):
            suffix = ''.join(rng.choice(alphabet) for _ in range(12))
            child_a = f"replica_a_{suffix}"
            child_b = f"replica_b_{suffix}"
            grandchild = f"archive_{suffix}"
            unrelated = f"unrelated_{suffix}"
            unrelated_child = f"unrelated_child_{suffix}"

            sizes = [rng.randrange(11, 10000) for _ in range(6)]
            data = [
                {"type": "node", "id": "db_primary", "size": sizes[0]},
                {"type": "node", "id": child_a, "size": sizes[1]},
                {"type": "node", "id": child_b, "size": sizes[2]},
                {"type": "node", "id": grandchild, "size": sizes[3]},
                {"type": "node", "id": unrelated, "size": sizes[4]},
                {"type": "node", "id": unrelated_child, "size": sizes[5]},
                {"type": "edge", "source": "db_primary", "target": child_a},
                {"type": "edge", "source": "db_primary", "target": child_b},
                {"type": "edge", "source": child_b, "target": grandchild},
                {"type": "edge", "source": unrelated, "target": unrelated_child},
            ]
            rng.shuffle(data)

            with open(manifest_path, "w") as f:
                json.dump(data, f)

            expected = compute_expected_size(manifest_path)
            assert run_binary(binary_path) == str(expected), (
                "The built Rust program does not correctly follow explicit edge targets"
            )
    finally:
        with open(manifest_path, "wb") as f:
            f.write(original_manifest)


def test_report_contains_correct_size():
    manifest_path = "/home/user/backup_manifest.json"
    report_path = "/home/user/report.txt"

    assert os.path.exists(manifest_path), f"Manifest file missing at {manifest_path}"
    assert os.path.exists(report_path), f"Report file missing at {report_path}"

    expected_size = compute_expected_size(manifest_path)

    with open(report_path, 'r') as f:
        report_content = f.read().strip()

    assert report_content == str(expected_size), (
        f"Expected report to contain '{expected_size}', but found '{report_content}'"
    )


def test_rust_code_not_hardcoded():
    main_rs = "/home/user/backup_graph/src/main.rs"
    assert os.path.exists(main_rs), f"Missing main.rs at {main_rs}"

    with open(main_rs, 'r') as f:
        content = f.read()

    assert "println!(\"400\")" not in content.replace(" ", ""), "The result should not be hardcoded in main.rs"
    assert "400" not in content, "The result should not be hardcoded in main.rs"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
