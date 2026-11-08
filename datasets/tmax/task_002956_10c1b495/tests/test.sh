#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess


def test_cleaned_measurements_exists():
    file_path = "/home/user/cleaned_measurements.csv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} should be a file."


def test_cleaned_measurements_content():
    file_path = "/home/user/cleaned_measurements.csv"
    expected_content = """id,measurement,value
X-1,p1,10.5
X-1,p2,12.5
X-1,p4,14.2
X-2,p1,11.1
X-3,p5,5.5
Y-9,m1,-2.0
Y-9,m2,0.0"""

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == expected_content.strip(), f"Content of {file_path} does not match the expected output."


def test_rust_project_exists():
    project_dir = "/home/user/cleaner"
    cargo_toml_path = os.path.join(project_dir, "Cargo.toml")

    assert os.path.exists(project_dir), f"Rust project directory {project_dir} is missing."
    assert os.path.isdir(project_dir), f"{project_dir} should be a directory."
    assert os.path.exists(cargo_toml_path), f"Cargo.toml is missing in {project_dir}."


def test_rust_project_uses_rayon():
    cargo_toml_path = "/home/user/cleaner/Cargo.toml"

    with open(cargo_toml_path, "r") as f:
        content = f.read()

    assert "rayon" in content, "The 'rayon' crate is not listed in Cargo.toml."


def test_rayon_is_a_real_dependency_and_is_used_for_parallel_iteration():
    project_dir = "/home/user/cleaner"
    result = subprocess.run(
        ["cargo", "metadata", "--format-version=1", "--no-deps"],
        cwd=project_dir,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, f"cargo metadata failed:\n{result.stdout}\n{result.stderr}"
    metadata = json.loads(result.stdout)
    manifest = os.path.realpath(os.path.join(project_dir, "Cargo.toml"))
    package = next(
        (p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == manifest),
        None,
    )
    assert package is not None, "Cargo.toml does not describe a buildable Cargo package."
    rayon_deps = [d for d in package["dependencies"] if d["name"] == "rayon"]
    assert rayon_deps, "rayon must be an actual Cargo dependency, not merely text in Cargo.toml."

    source_dir = os.path.join(project_dir, "src")
    rust_sources = []
    for root, dirs, files in os.walk(source_dir):
        dirs[:] = [d for d in dirs if d != "target"]
        for name in files:
            if name.endswith(".rs"):
                with open(os.path.join(root, name), "r") as f:
                    rust_sources.append(f.read())
    source = "\n".join(rust_sources)
    aliases = {d.get("rename") or "rayon" for d in rayon_deps}
    assert any(re.search(r"\b" + re.escape(alias) + r"\s*::", source) for alias in aliases), \
        "Rust source does not import or call the rayon dependency."
    parallel_api = re.compile(
        r"\b(?:par_iter|par_iter_mut|into_par_iter|par_bridge|par_lines|ParallelIterator|"
        r"ParallelBridge|IndexedParallelIterator)\b|\brayon\s*::\s*(?:scope|join|spawn)\b"
    )
    assert parallel_api.search(source), "Rust source does not use a Rayon parallel-processing API."


def test_program_handles_unseen_input():
    project_dir = "/home/user/cleaner"
    input_path = "/home/user/raw_measurements.txt"
    output_path = "/home/user/cleaned_measurements.csv"

    with open(input_path, "r") as f:
        original_input = f.read()

    tag = secrets.token_hex(4)
    low = random.randint(20, 80) / 10.0
    high = low + random.randint(5, 30) / 10.0
    middle = (low + high) / 2.0
    beta = random.randint(90, 170) / 10.0
    neg_low = -random.randint(50, 90) / 10.0
    neg_high = -random.randint(1, 30) / 10.0

    dynamic_input = (
        f"Z-{tag} | temp: {low:.1f}C, bad: N/A, temp: {high:.1f} c, neg: {neg_low:.1f} C\n"
        f"A-{tag} | beta: {beta:.1f}C, alpha: 0.0c, junk: err\n"
        f"Z-{tag} | temp: {middle:.2f}C, neg: {neg_high:.1f}c\n"
        f"A-{tag} | beta: {beta - 0.5:.1f} C\n"
    )
    expected = "\n".join([
        "id,measurement,value",
        f"A-{tag},alpha,0.0",
        f"A-{tag},beta,{beta:.1f}",
        f"Z-{tag},neg,{max(neg_low, neg_high):.1f}",
        f"Z-{tag},temp,{max(low, high, middle):.1f}",
    ])

    try:
        with open(input_path, "w") as f:
            f.write(dynamic_input)

        result = subprocess.run(
            ["cargo", "run", "--quiet"],
            cwd=project_dir,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
            env={**os.environ, "RAYON_NUM_THREADS": "4"},
        )
        assert result.returncode == 0, f"Rust program failed:\n{result.stdout}\n{result.stderr}"
        assert os.path.isfile(output_path), "Program did not create cleaned_measurements.csv."
        with open(output_path, "r") as f:
            actual = f.read().strip()
        assert actual == expected, f"Program produced incorrect output for unseen input.\nExpected:\n{expected}\nActual:\n{actual}"
    finally:
        with open(input_path, "w") as f:
            f.write(original_input)
        subprocess.run(
            ["cargo", "run", "--quiet"],
            cwd=project_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
            env={**os.environ, "RAYON_NUM_THREADS": "4"},
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
