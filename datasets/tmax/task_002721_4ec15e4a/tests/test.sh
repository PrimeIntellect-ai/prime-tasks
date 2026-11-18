#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import secrets
import shutil
import subprocess
from pathlib import Path


def test_venv_and_numpy():
    venv_python = "/home/user/prep_env/bin/python"
    assert os.path.isfile(venv_python), "Virtual environment Python executable not found at /home/user/prep_env/bin/python"

    result = subprocess.run([venv_python, "-c", "import numpy"], capture_output=True)
    assert result.returncode == 0, "numpy is not installed in the virtual environment at /home/user/prep_env"


def test_script_exists():
    assert os.path.isfile("/home/user/preprocess.py"), "/home/user/preprocess.py is missing"


def test_features_csv():
    csv_path = "/home/user/features.csv"
    assert os.path.isfile(csv_path), f"{csv_path} is missing"

    with open(csv_path, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == 4, "features.csv should have exactly 4 rows (1 header + 3 data rows)"

    header = rows[0]
    expected_header = ["pdb_id", "seq_length", "com_x", "com_y", "com_z", "max_norm_dist"]
    assert header == expected_header, f"Header mismatch. Expected {expected_header}, got {header}"

    expected_data = [
        ["1abc", "3", "10.0000", "11.3333", "11.0000", "5.8466"],
        ["2xyz", "1", "5.0000", "5.0000", "5.0000", "0.0000"],
        ["3mno", "20", "1.0000", "0.0000", "0.0000", "100000000.0000"]
    ]

    data = rows[1:]
    assert data == expected_data, f"Data mismatch. Expected {expected_data}, got {data}"


def _pdb_line(serial, atom, residue, residue_number, xyz):
    x, y, z = xyz
    return (
        f"ATOM  {serial:5d} {atom:^4s}{residue:>3s} A{residue_number:4d}    "
        f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C\n"
    )


def _expected_row(pdb_id, sequence, coordinates):
    count = len(coordinates)
    com = [sum(point[i] for point in coordinates) / count for i in range(3)]
    distances = [
        math.sqrt(sum((point[i] - com[i]) ** 2 for i in range(3)))
        for point in coordinates
    ]
    mean_distance = sum(distances) / count
    sigma = math.sqrt(sum((d - mean_distance) ** 2 for d in distances) / count)
    denominator = sigma if sigma > 1e-8 else sigma + 1e-8
    max_norm = max(d / denominator for d in distances)
    return [
        pdb_id,
        str(len(sequence)),
        f"{com[0]:.4f}",
        f"{com[1]:.4f}",
        f"{com[2]:.4f}",
        f"{max_norm:.4f}",
    ]


def test_script_functionally_processes_fresh_dataset():
    token = secrets.token_hex(5)
    base = secrets.randbelow(50) + 20
    datasets = {
        f"dyn_c_{token}": (
            "ACDEFGH",
            [(base + 3.0, base + 2.0, base + 1.0),
             (base + 9.0, base + 2.0, base + 1.0)],
        ),
        f"dyn_a_{token}": (
            "MNPQRS",
            [(base + 0.0, base + 1.0, base + 2.0),
             (base + 4.0, base + 1.0, base + 2.0),
             (base + 1.0, base + 7.0, base + 3.0),
             (base + 2.0, base + 2.0, base + 9.0)],
        ),
        f"dyn_b_{token}": (
            "G",
            [(base + 5.0, base + 6.0, base + 7.0)],
        ),
    }

    raw_data = Path("/home/user/raw_data")
    shutil.rmtree(raw_data)
    pdb_dir = raw_data / "pdb"
    pdb_dir.mkdir(parents=True)

    fasta_parts = []
    for pdb_id, (sequence, coordinates) in datasets.items():
        midpoint = max(1, len(sequence) // 2)
        fasta_parts.append(f">{pdb_id}\n{sequence[:midpoint]}\n{sequence[midpoint:]}\n")

        lines = []
        for index, coordinate in enumerate(coordinates, 1):
            lines.append(_pdb_line(index, "CA", "ALA", index, coordinate))
        lines.append(_pdb_line(900, "N", "ALA", 900, (999.0, 888.0, 777.0)))
        (pdb_dir / f"{pdb_id}.pdb").write_text("".join(lines))

    (raw_data / "sequences.fasta").write_text("".join(fasta_parts))

    output = Path("/home/user/features.csv")
    output.unlink(missing_ok=True)
    result = subprocess.run(
        ["/home/user/prep_env/bin/python", "/home/user/preprocess.py"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"preprocess.py failed on a fresh dataset. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert output.is_file(), "preprocess.py did not create /home/user/features.csv"

    with output.open(newline="") as f:
        actual = list(csv.reader(f))

    expected_header = ["pdb_id", "seq_length", "com_x", "com_y", "com_z", "max_norm_dist"]
    expected_data = [
        _expected_row(pdb_id, datasets[pdb_id][0], datasets[pdb_id][1])
        for pdb_id in sorted(datasets)
    ]
    assert actual == [expected_header] + expected_data, (
        f"preprocess.py produced incorrect features for a fresh dataset. "
        f"Expected {[expected_header] + expected_data}, got {actual}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
