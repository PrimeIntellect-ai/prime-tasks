#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess

import pytest

PROJECT_DIR = "/home/user/svd_analyzer"
RAW_FILE = "/home/user/raw_kmer_counts.csv"
REF_FILE = "/home/user/ref_svs.txt"
OUTPUT_FILE = "/home/user/sv_diff.txt"


def run(cmd, cwd=PROJECT_DIR, timeout=240):
    return subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=True,
    )


@pytest.fixture(scope="session", autouse=True)
def verify_and_build_rust_project():
    manifest = os.path.join(PROJECT_DIR, "Cargo.toml")
    assert os.path.isfile(manifest), "Cargo.toml not found in the Rust project."

    metadata = json.loads(run(["cargo", "metadata", "--format-version", "1"]).stdout)
    root_id = metadata.get("resolve", {}).get("root")
    root_package = next((p for p in metadata["packages"] if p["id"] == root_id), None)
    assert root_package is not None, "Cargo.toml must define a root Rust package."

    bin_targets = [t for t in root_package["targets"] if "bin" in t.get("kind", [])]
    assert bin_targets, "The Rust project must define a binary target."

    nalgebra_deps = [d for d in root_package["dependencies"] if d["name"] == "nalgebra"]
    assert nalgebra_deps, "The Rust project must depend on the nalgebra crate."

    resolved = {p["id"]: p for p in metadata["packages"]}
    nalgebra_versions = [
        p["version"] for p in resolved.values() if p.get("name") == "nalgebra"
    ]
    assert any(v.split(".")[:2] == ["0", "32"] for v in nalgebra_versions), (
        "The resolved nalgebra dependency must be version 0.32.x."
    )

    source_text = "\n".join(
        open(t["src_path"], "r", encoding="utf-8").read() for t in bin_targets
    ).lower()
    assert "nalgebra" in source_text, "The binary source must use nalgebra."
    assert "svd" in source_text, "The binary source must perform an SVD."

    result = run(["cargo", "build", "--release"])
    assert os.path.isdir(os.path.join(PROJECT_DIR, "target", "release")), result.stdout


def test_rust_project_exists():
    """Check if the Rust project directory exists."""
    project_dir = "/home/user/svd_analyzer"
    assert os.path.exists(project_dir), f"Rust project directory {project_dir} does not exist."
    assert os.path.isdir(project_dir), f"{project_dir} is not a directory."
    assert os.path.exists(os.path.join(project_dir, "Cargo.toml")), "Cargo.toml not found in the Rust project."


def test_sv_diff_output():
    """Check if the final output file exists and has the correct contents."""
    output_file = "/home/user/sv_diff.txt"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."

    with open(output_file, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == 3, f"Expected exactly 3 lines in {output_file}, but found {len(lines)}."

    expected_values = ["0.46", "0.21", "0.00"]

    for i, (actual, expected) in enumerate(zip(lines, expected_values)):
        assert actual.strip() == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual.strip()}'."


def singular_values_4x3(values):
    matrix = [values[i:i + 3] for i in range(0, 12, 3)]
    gram = [[sum(row[i] * row[j] for row in matrix) for j in range(3)] for i in range(3)]

    for _ in range(100):
        p, q = max(((0, 1), (0, 2), (1, 2)), key=lambda pair: abs(gram[pair[0]][pair[1]]))
        if abs(gram[p][q]) < 1e-12:
            break
        app, aqq, apq = gram[p][p], gram[q][q], gram[p][q]
        angle = 0.5 * math.atan2(2.0 * apq, aqq - app)
        c, s = math.cos(angle), math.sin(angle)
        for k in range(3):
            if k == p or k == q:
                continue
            gkp, gkq = gram[k][p], gram[k][q]
            gram[k][p] = gram[p][k] = c * gkp - s * gkq
            gram[k][q] = gram[q][k] = s * gkp + c * gkq
        gram[p][p] = c*c*app - 2.0*s*c*apq + s*s*aqq
        gram[q][q] = s*s*app + 2.0*s*c*apq + c*c*aqq
        gram[p][q] = gram[q][p] = 0.0

    return sorted((math.sqrt(max(0.0, gram[i][i])) for i in range(3)), reverse=True)


def test_executable_computes_hidden_svd_case():
    backups = {}
    for path in (RAW_FILE, REF_FILE, OUTPUT_FILE):
        backups[path] = open(path, "rb").read() if os.path.exists(path) else None

    try:
        while True:
            values = [(secrets.randbelow(300) - 100) / 17.0 for _ in range(12)]
            singular_values = singular_values_4x3(values)
            if singular_values[-1] > 0.1:
                break

        references = sorted(
            [(secrets.randbelow(200) + 20) / 11.0 for _ in range(3)],
            reverse=True,
        )
        expected = [f"{abs(s - r):.2f}" for s, r in zip(singular_values, references)]

        with open(RAW_FILE, "w", encoding="utf-8") as f:
            f.write(", ".join(f"{v:.12f}" for v in values) + "\n")
        with open(REF_FILE, "w", encoding="utf-8") as f:
            f.write("\n".join(f"{v:.12f}" for v in references) + "\n")
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)

        run(["cargo", "run", "--release", "--quiet"])
        assert os.path.isfile(OUTPUT_FILE), "Executing the Rust binary did not create sv_diff.txt."
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            actual = f.read().strip().splitlines()
        assert actual == expected, f"Hidden SVD case mismatch: expected {expected}, got {actual}."
    finally:
        for path, data in backups.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
