#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import functools
import json
import math
import os
import random
import re
import shutil
import subprocess

PROJECT = "/home/user/ols_pipeline"
MANIFEST = os.path.join(PROJECT, "Cargo.toml")
INPUT = "/home/user/data/input.csv"
OUTPUT_DIR = "/home/user/output"
OUTPUT = os.path.join(OUTPUT_DIR, "coefficients.txt")
BASELINE = b"""x1,x2,y
1.0,2.0,7.0
2.0,NaN,12.0
3.0,4.0,15.0
4.0,6.0,20.0
"""


def test_rust_project_exists():
    """Verify that the Rust project directory exists."""
    assert os.path.isdir(PROJECT), f"Rust project directory {PROJECT} does not exist."
    assert os.path.isfile(MANIFEST), f"Cargo.toml not found in {PROJECT}. Is it a valid Rust project?"


@functools.lru_cache(maxsize=1)
def cargo_metadata():
    result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps", "--manifest-path", MANIFEST],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, f"cargo metadata failed:\n{result.stderr}"
    return json.loads(result.stdout)


def project_package(metadata):
    manifest_real = os.path.realpath(MANIFEST)
    matches = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == manifest_real]
    assert len(matches) == 1, "Could not identify the package defined by the submitted Cargo.toml."
    return matches[0]


def test_nalgebra_is_used_by_rust_sources():
    metadata = cargo_metadata()
    package = project_package(metadata)
    nalgebra_deps = [d for d in package.get("dependencies", []) if d.get("name") == "nalgebra"]
    assert nalgebra_deps, "Cargo.toml must declare nalgebra as a dependency."

    aliases = {d.get("rename") or d["name"] for d in nalgebra_deps}
    sources = []
    for root, dirs, files in os.walk(PROJECT):
        dirs[:] = [d for d in dirs if d not in {"target", ".git"}]
        for name in files:
            if name.endswith(".rs"):
                with open(os.path.join(root, name), "r", encoding="utf-8", errors="replace") as f:
                    sources.append(f.read())
    assert sources, "No Rust source files were found in the project."
    source = "\n".join(sources)
    assert any(re.search(r"\b" + re.escape(alias) + r"\b", source) for alias in aliases), \
        "Rust source does not reference the declared nalgebra dependency."
    assert re.search(r"\b(?:DMatrix|DVector|SMatrix|SVector|Matrix\w*|Vector\w*|OMatrix|OVector|try_inverse|transpose)\b", source), \
        "Rust source does not appear to use nalgebra matrix/vector operations."


@functools.lru_cache(maxsize=1)
def built_binary():
    metadata = cargo_metadata()
    package = project_package(metadata)
    result = subprocess.run(
        ["cargo", "build", "--message-format=json-render-diagnostics", "--manifest-path", MANIFEST],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, f"The Rust project did not build successfully:\n{result.stderr}\n{result.stdout[-4000:]}"

    executables = {}
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if (message.get("reason") == "compiler-artifact"
                and message.get("package_id") == package["id"]
                and "bin" in message.get("target", {}).get("kind", [])
                and message.get("executable")):
            executables[message["target"]["name"]] = message["executable"]

    default_run = package.get("default_run")
    if default_run:
        assert default_run in executables, f"The default-run binary {default_run!r} was not built."
        executable = executables[default_run]
    else:
        assert len(executables) == 1, "The project must provide one runnable binary, or set package.default-run."
        executable = next(iter(executables.values()))

    assert os.path.isfile(executable) and os.access(executable, os.X_OK), "Cargo did not produce an executable binary."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The produced artifact is not a native executable."
    return executable


def run_pipeline(csv_bytes):
    os.makedirs(os.path.dirname(INPUT), exist_ok=True)
    with open(INPUT, "wb") as f:
        f.write(csv_bytes)
    shutil.rmtree(OUTPUT_DIR, ignore_errors=True)

    result = subprocess.run(
        [built_binary()],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"Rust program failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.isdir(OUTPUT_DIR), "The program did not create /home/user/output."
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."

    with open(OUTPUT, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 3, f"Expected exactly 3 coefficients in {OUTPUT}, but found {len(lines)}."
    for line in lines:
        assert re.fullmatch(r"-?\d+\.\d{4}", line), f"Coefficient is not printed to exactly 4 decimal places: {line!r}"
    return lines


def test_coefficients_output():
    """Run the Rust artifact and retain the original fixed-data assertions."""
    lines = run_pipeline(BASELINE)
    expected_coefficients = ["2.0000", "3.0000", "1.0000"]
    for i, (actual, expected) in enumerate(zip(lines, expected_coefficients)):
        assert actual == expected, f"Coefficient {i} mismatch: expected {expected}, got {actual}."


def solve_3x3(a, b):
    aug = [list(a[i]) + [b[i]] for i in range(3)]
    for col in range(3):
        pivot = max(range(col, 3), key=lambda r: abs(aug[r][col]))
        assert abs(aug[pivot][col]) > 1e-10, "Generated test matrix was singular."
        aug[col], aug[pivot] = aug[pivot], aug[col]
        divisor = aug[col][col]
        aug[col] = [v / divisor for v in aug[col]]
        for row in range(3):
            if row != col:
                factor = aug[row][col]
                aug[row] = [aug[row][j] - factor * aug[col][j] for j in range(4)]
    return [aug[i][3] for i in range(3)]


def expected_ols(feature_rows, ys):
    xtx = [[0.0] * 3 for _ in range(3)]
    xty = [0.0] * 3
    for (x1, x2), y in zip(feature_rows, ys):
        row = [1.0, x1, x2]
        for i in range(3):
            xty[i] += row[i] * y
            for j in range(3):
                xtx[i][j] += row[i] * row[j]
    return solve_3x3(xtx, xty)


def make_secret_case():
    rng = random.SystemRandom()
    missing_x1 = {0: "", 3: "NA", 6: "NaN", 9: "not_a_number"}
    missing_x2 = {1: "NA", 4: "NaN", 7: "", 10: "invalid"}

    while True:
        x1_valid = [round(rng.uniform(-8.0, 12.0), 6) for _ in range(12)]
        x2_valid = [round(rng.uniform(-10.0, 9.0), 6) for _ in range(12)]
        mean1 = sum(x1_valid[i] for i in range(12) if i not in missing_x1) / (12 - len(missing_x1))
        mean2 = sum(x2_valid[i] for i in range(12) if i not in missing_x2) / (12 - len(missing_x2))
        features = [
            (mean1 if i in missing_x1 else x1_valid[i], mean2 if i in missing_x2 else x2_valid[i])
            for i in range(12)
        ]
        true_w = [rng.uniform(1.0, 5.0), rng.uniform(1.0, 4.0), rng.uniform(-4.0, -1.0)]
        ys = [round(true_w[0] + true_w[1] * x1 + true_w[2] * x2 + rng.uniform(-0.7, 0.7), 10)
              for x1, x2 in features]
        coefficients = expected_ols(features, ys)
        if all(abs((abs(v) * 10000.0) % 1.0 - 0.5) > 1e-5 for v in coefficients):
            break

    rows = ["x1,x2,y"]
    for i in range(12):
        sx1 = missing_x1.get(i, format(x1_valid[i], ".6f"))
        sx2 = missing_x2.get(i, format(x2_valid[i], ".6f"))
        rows.append(f"{sx1},{sx2},{ys[i]:.10f}")
    return ("\n".join(rows) + "\n").encode(), [f"{v:.4f}" for v in coefficients]


def test_recomputes_coefficients_from_dirty_input():
    csv_bytes, expected = make_secret_case()
    actual = run_pipeline(csv_bytes)
    assert actual == expected, f"Coefficients for verifier-generated dirty input are wrong: expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
