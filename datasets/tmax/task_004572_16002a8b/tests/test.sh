#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess
import tempfile

CSV_PATH = "/home/user/training_data.csv"
EVAL_SCRIPT = "/app/train_and_eval.py"
SOURCE_DIR = "/app/libfastcontact-0.9"
SOURCE_PATH = os.path.join(SOURCE_DIR, "fastcontact.c")
BINARY_PATH = os.path.join(SOURCE_DIR, "fastcontact")
PDB_DIR = "/app/data/raw_pdbs"
EXPECTED_HEADER = ["pdb_id", "mean_dist", "max_dist", "var_dist", "label"]


def pdb_features(path):
    atoms = []
    with open(path, "r") as f:
        for line in f:
            if line.startswith("ATOM  ") and len(line) >= 54 and line[12:16].strip() == "CA":
                atoms.append((float(line[30:38]), float(line[38:46]), float(line[46:54])))

    if len(atoms) < 2:
        return (0.0, 0.0, 0.0)

    distances = []
    for i in range(len(atoms)):
        for j in range(i + 1, len(atoms)):
            dx = atoms[j][0] - atoms[i][0]
            dy = atoms[j][1] - atoms[i][1]
            dz = atoms[j][2] - atoms[i][2]
            distances.append(math.sqrt(dx * dx + dy * dy + dz * dz))

    mean = sum(distances) / len(distances)
    maximum = max(distances)
    variance = sum((d - mean) ** 2 for d in distances) / len(distances)
    return (mean, maximum, variance)


def run_fastcontact(binary, pdb_path):
    result = subprocess.run(
        [binary, pdb_path], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"fastcontact failed for {pdb_path}:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    match = re.fullmatch(
        r"\s*Mean:\s*([-+0-9.eE]+),\s*Max:\s*([-+0-9.eE]+),\s*Var:\s*([-+0-9.eE]+)\s*",
        result.stdout,
    )
    assert match is not None, f"Unexpected fastcontact output for {pdb_path}: {result.stdout!r}"
    values = tuple(float(match.group(i)) for i in range(1, 4))
    assert all(math.isfinite(v) for v in values), f"Non-finite output for {pdb_path}: {values}"
    return values


def assert_close_tuple(actual, expected, context):
    for name, got, want in zip(("mean", "max", "variance"), actual, expected):
        assert math.isclose(got, want, rel_tol=2e-6, abs_tol=2e-5), (
            f"Incorrect {name} for {context}: got {got}, expected {want}"
        )


def write_synthetic_pdb(path):
    records = [
        ("CA", 0.0, 0.0, 0.0),
        ("CB", 900.0, 900.0, 900.0),
        ("CA", 0.0, 0.0, 3.0),
        ("CA", 4.0, 0.0, 0.0),
    ]
    with open(path, "w") as f:
        for serial, (name, x, y, z) in enumerate(records, 1):
            f.write(
                f"ATOM  {serial:5d} {name:^4s} ALA A{serial:4d}    "
                f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n"
            )


def test_library_builds_and_computes_correct_distances():
    assert os.path.isfile(SOURCE_PATH), f"Missing C source: {SOURCE_PATH}"
    assert os.path.isfile(os.path.join(SOURCE_DIR, "Makefile")), "Missing Makefile"

    if os.path.lexists(BINARY_PATH):
        os.remove(BINARY_PATH)
    build = subprocess.run(
        ["make", "-B", "fastcontact"], cwd=SOURCE_DIR,
        capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, f"Build failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK), (
        "Build did not produce an executable fastcontact binary"
    )
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fastcontact must be a compiled ELF executable"

    source_binary = "/tmp/fastcontact_from_source"
    compile_result = subprocess.run(
        ["gcc", "-O2", "-Wall", "-o", source_binary, SOURCE_PATH, "-lm"],
        capture_output=True, text=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        f"The submitted C source does not compile:\n{compile_result.stdout}\n{compile_result.stderr}"
    )

    with tempfile.TemporaryDirectory() as td:
        synthetic = os.path.join(td, "geometry.pdb")
        write_synthetic_pdb(synthetic)
        expected = pdb_features(synthetic)
        assert_close_tuple(run_fastcontact(BINARY_PATH, synthetic), expected, "synthetic geometry")
        assert_close_tuple(run_fastcontact(source_binary, synthetic), expected, "submitted C source")


def test_training_data_csv_exists():
    assert os.path.isfile(CSV_PATH), f"Expected CSV file at {CSV_PATH} does not exist."


def test_training_data_csv_header():
    with open(CSV_PATH, 'r') as f:
        header = f.readline().strip()
    expected_header = "pdb_id,mean_dist,max_dist,var_dist,label"
    assert header == expected_header, f"CSV header is incorrect. Expected '{expected_header}', got '{header}'."


def test_csv_contains_exact_pdb_rows_labels_and_features():
    pdb_paths = sorted(
        os.path.join(PDB_DIR, name)
        for name in os.listdir(PDB_DIR)
        if name.endswith(".pdb") and os.path.isfile(os.path.join(PDB_DIR, name))
    )
    assert pdb_paths, f"No PDB inputs found in {PDB_DIR}"

    with open(CSV_PATH, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == EXPECTED_HEADER, f"Unexpected CSV columns: {reader.fieldnames}"
        rows = list(reader)

    expected_ids = {os.path.basename(path)[:-4] for path in pdb_paths}
    actual_ids = [row["pdb_id"] for row in rows]
    assert len(rows) == len(pdb_paths), f"Expected {len(pdb_paths)} rows, found {len(rows)}"
    assert len(actual_ids) == len(set(actual_ids)), "CSV contains duplicate pdb_id rows"
    assert set(actual_ids) == expected_ids, "CSV pdb_id values do not exactly match the input PDB files"
    rows_by_id = {row["pdb_id"]: row for row in rows}

    for pdb_path in pdb_paths:
        pdb_id = os.path.basename(pdb_path)[:-4]
        row = rows_by_id[pdb_id]
        if "compact" in pdb_id:
            expected_label = "1"
        elif "extended" in pdb_id:
            expected_label = "0"
        else:
            raise AssertionError(f"Cannot derive label from PDB filename: {pdb_id}")
        assert row["label"] == expected_label, f"Incorrect filename-derived label for {pdb_id}"

        try:
            csv_values = tuple(float(row[col]) for col in ("mean_dist", "max_dist", "var_dist"))
        except (TypeError, ValueError) as exc:
            raise AssertionError(f"Non-numeric features for {pdb_id}: {row}") from exc
        assert all(math.isfinite(v) for v in csv_values), f"Non-finite features for {pdb_id}"

        independently_expected = pdb_features(pdb_path)
        tool_values = run_fastcontact(BINARY_PATH, pdb_path)
        assert_close_tuple(tool_values, independently_expected, f"fastcontact on {pdb_id}")
        assert_close_tuple(csv_values, independently_expected, f"CSV row {pdb_id}")


def test_model_accuracy_meets_threshold():
    # Run the evaluation script
    result = subprocess.run(
        ["python3", EVAL_SCRIPT, CSV_PATH],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Evaluation script failed with error:\n{result.stderr}"

    # Extract accuracy from standard output
    output = result.stdout
    match = re.search(r"Accuracy:\s*([0-9]*\.?[0-9]+)", output)
    assert match is not None, f"Could not parse 'Accuracy: <value>' from output:\n{output}"

    accuracy = float(match.group(1))
    threshold = 0.90

    assert accuracy >= threshold, f"Model accuracy {accuracy} is below the threshold of {threshold}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
