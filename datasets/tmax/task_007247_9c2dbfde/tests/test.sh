#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import subprocess
import tempfile

PROJECT_DIR = "/home/user/organizer"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=180, **kwargs)


def expected_bins(files, rules):
    ordered = sorted(files, key=lambda f: (-f["size"], f["name"]))
    bins = []

    def conflicts(a, b):
        for tag1 in a["tags"]:
            for tag2 in b["tags"]:
                for rule in rules["conflicts"]:
                    if (rule[0] == tag1 and rule[1] == tag2) or (rule[0] == tag2 and rule[1] == tag1):
                        return True
        return False

    for item in ordered:
        placed = False
        for bin_items in bins:
            if sum(existing["size"] for existing in bin_items) + item["size"] <= rules["max_size"] and not any(
                conflicts(item, existing) for existing in bin_items
            ):
                bin_items.append(item)
                placed = True
                break
        if not placed:
            bins.append([item])

    return [[item["name"] for item in bin_items] for bin_items in bins]


def test_allocation_json_correctness():
    allocation_path = "/home/user/allocation.json"
    assert os.path.isfile(allocation_path), f"Missing output file: {allocation_path}"

    with open(allocation_path, "r") as f:
        try:
            allocation = json.load(f)
        except json.JSONDecodeError:
            assert False, "allocation.json is not a valid JSON file"

    expected_allocation = [
        ["file5.js", "file6.js"],
        ["file2.js", "file1.js", "file4.js"],
        ["file3.js"]
    ]

    assert allocation == expected_allocation, f"Allocation output does not match the expected deterministic bin packing. Got: {allocation}"


def test_cargo_test_passes():
    assert os.path.isdir(PROJECT_DIR), f"Missing project directory: {PROJECT_DIR}"
    result = run(["cargo", "test"], cwd=PROJECT_DIR, env={**os.environ, "PROPTEST_CASES": "256"})
    assert result.returncode == 0, f"`cargo test` failed with output:\n{result.stdout}\n{result.stderr}"


def test_proptest_implemented():
    lib_rs_path = os.path.join(PROJECT_DIR, "src", "lib.rs")
    assert os.path.isfile(lib_rs_path), f"Missing lib.rs file: {lib_rs_path}"

    with open(lib_rs_path, "r") as f:
        content = f.read()

    assert "proptest!" in content or "proptest {" in content or "#[proptest]" in content, "No proptest macro found in lib.rs. You must implement a property-based test."


def test_cli_on_derived_inputs():
    rng = random.Random(914237)
    cases = [
        (
            [
                {"name": "equal-b", "size": 5, "tags": ["x"]},
                {"name": "large", "size": 9, "tags": ["z"]},
                {"name": "equal-a", "size": 5, "tags": ["y"]},
                {"name": "small", "size": 1, "tags": ["x", "q"]},
            ],
            {"max_size": 10, "conflicts": [["x", "y"], ["q", "z"]]},
        ),
        (
            [
                {"name": "a", "size": 0, "tags": ["same"]},
                {"name": "b", "size": 0, "tags": ["same"]},
                {"name": "c", "size": 1, "tags": []},
            ],
            {"max_size": 1, "conflicts": [["same", "same"]]},
        ),
    ]

    tags = ["red", "blue", "green", "db", "ui", "api"]
    for case_index in range(8):
        max_size = rng.randint(12, 45)
        files = []
        for i in range(rng.randint(6, 15)):
            files.append({
                "name": f"case{case_index}-file{i:02d}",
                "size": rng.randint(0, max_size),
                "tags": rng.sample(tags, rng.randint(0, 3)),
            })
        pairs = []
        for pair in rng.sample([(a, b) for i, a in enumerate(tags) for b in tags[i:]], rng.randint(1, 7)):
            pairs.append([pair[0], pair[1]])
        cases.append((files, {"max_size": max_size, "conflicts": pairs}))

    with tempfile.TemporaryDirectory() as td:
        for index, (files, rules) in enumerate(cases):
            input_path = os.path.join(td, f"files-{index}.json")
            rules_path = os.path.join(td, f"rules-{index}.json")
            output_path = os.path.join(td, f"output-{index}.json")
            with open(input_path, "w") as f:
                json.dump(files, f)
            with open(rules_path, "w") as f:
                json.dump(rules, f)

            result = run(
                ["cargo", "run", "--quiet", "--", input_path, rules_path, output_path],
                cwd=PROJECT_DIR,
            )
            assert result.returncode == 0, f"CLI failed on generated case {index}:\n{result.stdout}\n{result.stderr}"
            assert os.path.isfile(output_path), f"CLI did not create output for generated case {index}"
            with open(output_path) as f:
                actual = json.load(f)
            expected = expected_bins(files, rules)
            assert actual == expected, f"Incorrect allocation for generated case {index}. Expected {expected}, got {actual}"


def test_agent_tests_reject_constraint_breaking_implementation():
    lib_path = os.path.join(PROJECT_DIR, "src", "lib.rs")
    with open(lib_path) as f:
        original = f.read()
    signature = "pub fn organize_files("
    assert signature in original, "Required public organize_files function is missing"

    with tempfile.TemporaryDirectory() as td:
        mutant_dir = os.path.join(td, "organizer")
        shutil.copytree(PROJECT_DIR, mutant_dir, ignore=shutil.ignore_patterns("target"))
        mutant_lib = os.path.join(mutant_dir, "src", "lib.rs")
        renamed = original.replace(signature, "pub fn organize_files_original(", 1)
        mutant = '''\n// Verifier mutation: deliberately violates capacity and conflict constraints.\npub fn organize_files(files: &mut Vec<FileItem>, _rules: &Rules) -> Vec<Vec<FileItem>> {\n    files.sort_by(|a, b| b.size.cmp(&a.size).then_with(|| a.name.cmp(&b.name)));\n    vec![files.clone()]\n}\n\n''' + renamed
        with open(mutant_lib, "w") as f:
            f.write(mutant)

        env = {**os.environ, "PROPTEST_CASES": "2048", "CARGO_TARGET_DIR": os.path.join(td, "target")}
        result = run(["cargo", "test", "--quiet"], cwd=mutant_dir, env=env)
        combined = result.stdout + "\n" + result.stderr
        assert result.returncode != 0 and ("FAILED" in combined or "failures:" in combined), (
            "The submitted tests did not reject an implementation that puts every file in one bin; "
            "the property test must meaningfully validate size/conflict constraints.\n" + combined
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
