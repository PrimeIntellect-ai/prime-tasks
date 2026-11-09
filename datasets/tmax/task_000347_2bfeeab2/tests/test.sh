#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import tempfile
import uuid
import pytest

FILTER_SCRIPT = "/home/user/filter_pdbs.py"
CALC_SCRIPT = "/home/user/calc_com.py"
CLEAN_CORPUS = "/app/tests/corpus/clean"
EVIL_CORPUS = "/app/tests/corpus/evil"
TARGET_EPSILON = 1e-12


def python_bin():
    candidate = "/home/user/venv/bin/python"
    return candidate if os.path.exists(candidate) else "python3"


def run_filter_script(input_dir, output_dir):
    try:
        subprocess.run(
            [python_bin(), FILTER_SCRIPT, input_dir, output_dir],
            check=True,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"filter_pdbs.py failed: {e.stderr}")


def atom_line(serial, name, residue, residue_id, x, y, z, element="C"):
    return (
        f"ATOM  {serial:5d} {name:^4s} {residue:>3s} A{residue_id:4d}    "
        f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00 20.00          {element:>2s}  \n"
    )


def test_filter_pdbs_clean_corpus():
    assert os.path.isfile(FILTER_SCRIPT), f"Missing {FILTER_SCRIPT}"

    with tempfile.TemporaryDirectory() as out_dir:
        run_filter_script(CLEAN_CORPUS, out_dir)

        expected_files = set(os.listdir(CLEAN_CORPUS))
        actual_files = set(os.listdir(out_dir))

        missing = expected_files - actual_files
        assert not missing, f"{len(missing)} of {len(expected_files)} clean files were incorrectly rejected: {list(missing)[:5]}"


def test_filter_pdbs_evil_corpus():
    assert os.path.isfile(FILTER_SCRIPT), f"Missing {FILTER_SCRIPT}"

    with tempfile.TemporaryDirectory() as out_dir:
        run_filter_script(EVIL_CORPUS, out_dir)

        actual_files = set(os.listdir(out_dir))
        expected_files = set(os.listdir(EVIL_CORPUS))

        assert not actual_files, f"{len(actual_files)} of {len(expected_files)} evil files bypassed the filter: {list(actual_files)[:5]}"


def test_filter_pdbs_generated_mixed_corpus():
    """Exercise sanitisation in an unknown directory with derived expectations."""
    assert os.path.isfile(FILTER_SCRIPT), f"Missing {FILTER_SCRIPT}"
    rng = random.SystemRandom()
    shift = rng.randint(-40, 40)

    valid_general = "".join([
        atom_line(1, "N", "ALA", 1, shift + 0.0, 2.0, 3.0, "N"),
        atom_line(2, "CA", "ALA", 1, shift + 1.0, 2.0, 3.0),
        atom_line(3, "C", "ALA", 1, shift + 2.0, 2.0, 3.0),
        atom_line(4, "N", "GLY", 2, shift + 10.0, 4.0, 6.0, "N"),
        atom_line(5, "CA", "GLY", 2, shift + 11.0, 4.0, 6.0),
        atom_line(6, "C", "GLY", 2, shift + 12.0, 4.0, 6.0),
    ])
    # The nearest pair is 0.660 A apart, so it is above the OCR-derived cutoff.
    valid_near_cutoff = "".join([
        atom_line(1, "N", "SER", 1, 0.000, 0.000, 0.000, "N"),
        atom_line(2, "CA", "SER", 1, 0.660, 0.000, 0.000),
        atom_line(3, "C", "SER", 1, 2.000, 0.000, 0.000),
    ])
    clash = "".join([
        atom_line(1, "CA", "ALA", 1, 0.000, 0.000, 0.000),
        atom_line(2, "CB", "ALA", 1, 0.640, 0.000, 0.000),
    ])
    missing_ca = "".join([
        atom_line(1, "N", "VAL", 1, 0.000, 0.000, 0.000, "N"),
        atom_line(2, "C", "VAL", 1, 2.000, 0.000, 0.000),
    ])
    nan_coordinates = "".join([
        atom_line(1, "CA", "ALA", 1, float("nan"), 0.000, 0.000),
        atom_line(2, "C", "ALA", 1, 2.000, 0.000, 0.000),
    ])
    malformed = atom_line(1, "CA", "ALA", 1, 1.000, 2.000, 3.000)
    malformed = malformed[:46] + " TEXT00" + malformed[53:]

    generated = [
        (valid_general, True),
        (valid_near_cutoff, True),
        (clash, False),
        (missing_ca, False),
        (nan_coordinates, False),
        (malformed, False),
    ]
    rng.shuffle(generated)

    with tempfile.TemporaryDirectory(prefix="pdb-input-") as input_dir, tempfile.TemporaryDirectory(prefix="pdb-output-") as output_dir:
        expected = {}
        for content, accepted in generated:
            name = f"{uuid.uuid4().hex}.pdb"
            data = content.encode("ascii")
            with open(os.path.join(input_dir, name), "wb") as f:
                f.write(data)
            if accepted:
                expected[name] = data

        with open(os.path.join(input_dir, f"{uuid.uuid4().hex}.txt"), "w") as f:
            f.write("not a PDB file")

        run_filter_script(input_dir, output_dir)
        actual_names = set(os.listdir(output_dir))
        assert actual_names == set(expected), (
            f"Generated corpus was filtered incorrectly; expected {set(expected)}, got {actual_names}"
        )
        for name, original_data in expected.items():
            output_path = os.path.join(output_dir, name)
            assert os.path.isfile(output_path), f"Accepted output is not a regular file: {name}"
            with open(output_path, "rb") as f:
                assert f.read() == original_data, f"Accepted PDB {name} was not copied unchanged"


def parse_com_output(stdout):
    fields = stdout.strip().split(",")
    assert len(fields) == 3, f"Expected three comma-separated coordinates, got: {stdout!r}"
    try:
        values = tuple(float(field) for field in fields)
    except ValueError:
        pytest.fail(f"COM output contains a non-numeric coordinate: {stdout!r}")
    assert all(math.isfinite(value) for value in values), f"COM output is not finite: {stdout!r}"
    return values


def test_calc_com_determinism():
    assert os.path.isfile(CALC_SCRIPT), f"Missing {CALC_SCRIPT}"

    # Generate a dummy PDB file with 10,000 atoms.
    lines = []
    rounded_coords = []
    for i in range(1, 10001):
        x = random.uniform(-100, 100)
        y = random.uniform(-100, 100)
        z = random.uniform(-100, 100)
        line = f"ATOM  {i:5d}  CA  ALA A   1    {x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n"
        lines.append(line)
        rounded_coords.append((float(line[30:38]), float(line[38:46]), float(line[46:54])))

    expected = tuple(
        math.fsum(coord[axis] for coord in rounded_coords) / len(rounded_coords)
        for axis in range(3)
    )

    outputs = []
    parsed_outputs = []
    with tempfile.TemporaryDirectory() as tmpdir:
        pdb_path = os.path.join(tmpdir, "test.pdb")

        for _ in range(10):
            random.shuffle(lines)
            with open(pdb_path, "w") as f:
                f.writelines(lines)

            try:
                res = subprocess.run(
                    [python_bin(), CALC_SCRIPT, pdb_path],
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
            except subprocess.CalledProcessError as e:
                pytest.fail(f"calc_com.py failed: {e.stderr}")

            outputs.append(res.stdout.strip())
            parsed = parse_com_output(res.stdout)
            parsed_outputs.append(parsed)
            for axis, (actual, correct) in enumerate(zip(parsed, expected)):
                assert abs(actual - correct) <= TARGET_EPSILON, (
                    f"Incorrect COM on axis {axis}: expected {correct!r}, got {actual!r}"
                )

    # Preserve the exact reproducibility requirement from the original verifier.
    unique_outputs = set(outputs)
    assert len(unique_outputs) == 1, f"calc_com.py is not deterministic. Got multiple different outputs for shuffled coordinates: {list(unique_outputs)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
