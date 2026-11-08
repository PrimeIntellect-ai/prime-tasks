#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from collections import Counter

STD_AA = "ARNDCQEGHILKMFPSTWYV"
AA3_TO_1 = {
    "ALA": "A", "ARG": "R", "ASN": "N", "ASP": "D", "CYS": "C",
    "GLN": "Q", "GLU": "E", "GLY": "G", "HIS": "H", "ILE": "I",
    "LEU": "L", "LYS": "K", "MET": "M", "PHE": "F", "PRO": "P",
    "SER": "S", "THR": "T", "TRP": "W", "TYR": "Y", "VAL": "V"
}
AA1_TO_3 = {v: k for k, v in AA3_TO_1.items()}


def expected_tvd(fasta_path, pdb_path):
    fasta_counts = Counter()
    with open(fasta_path, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                continue
            for char in line:
                if char in set(STD_AA):
                    fasta_counts[char] += 1

    total_fasta = sum(fasta_counts.values())
    p = {aa: (fasta_counts[aa] / total_fasta if total_fasta > 0 else 0.0)
         for aa in STD_AA}

    pdb_counts = Counter()
    with open(pdb_path, "r") as f:
        for line in f:
            if line.startswith("ATOM"):
                atom_name = line[12:16].strip()
                if atom_name == "CA":
                    res_name = line[17:20].strip()
                    if res_name in AA3_TO_1:
                        pdb_counts[AA3_TO_1[res_name]] += 1

    total_pdb = sum(pdb_counts.values())
    q = {aa: (pdb_counts[aa] / total_pdb if total_pdb > 0 else 0.0)
         for aa in STD_AA}
    tvd = 0.5 * sum(abs(p[aa] - q[aa]) for aa in STD_AA)
    return f"{tvd:.4f}"


def pdb_line(serial, atom, residue, record="ATOM", residue_number=1):
    return (f"{record:<6}{serial:5d} {atom:>4} {residue:>3} A{residue_number:4d}"
            "      11.000   6.000  -5.000  1.00  0.00           C\n")


def test_analyze_cpp_exists():
    path = "/home/user/analyze.cpp"
    assert os.path.exists(path), f"Source file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."


def test_analyze_executable_exists():
    path = "/home/user/analyze"
    assert os.path.exists(path), f"Executable {path} is missing. Did you compile the code?"
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled native executable."


def test_result_txt_content():
    fasta_path = "/home/user/sequences.fasta"
    pdb_path = "/home/user/structure.pdb"
    result_path = "/home/user/result.txt"
    assert os.path.exists(result_path), f"Result file {result_path} is missing."

    expected_result = expected_tvd(fasta_path, pdb_path)
    with open(result_path, "r") as f:
        actual_result = f.read().strip()

    assert actual_result == expected_result, (
        f"Expected TVD {expected_result} in {result_path}, but got {actual_result}"
    )


def test_program_and_source_on_generated_inputs():
    fasta_path = "/home/user/sequences.fasta"
    pdb_path = "/home/user/structure.pdb"
    result_path = "/home/user/result.txt"
    source_path = "/home/user/analyze.cpp"
    submitted_binary = "/home/user/analyze"
    rebuilt_binary = "/tmp/analyze_from_source"

    subprocess.run(
        ["g++", "-std=c++17", "-O2", source_path, "-o", rebuilt_binary],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        timeout=30
    )

    backups = {}
    for path in (fasta_path, pdb_path, result_path):
        backups[path] = open(path, "rb").read() if os.path.exists(path) else None

    rng = random.SystemRandom()
    try:
        for case_number in range(3):
            fasta_chars = []
            for aa in STD_AA:
                fasta_chars.extend([aa] * rng.randint(0, 9))
            if not fasta_chars:
                fasta_chars.append("A")
            rng.shuffle(fasta_chars)
            split = max(1, len(fasta_chars) // 2)
            fasta_text = (
                ">generated header ARNDCQEGHILKMFPSTWYV\n"
                + "".join(fasta_chars[:split]) + "xyz-*\n"
                + "".join(fasta_chars[split:]) + "\n"
            )

            residues = []
            for aa in STD_AA:
                residues.extend([AA1_TO_3[aa]] * rng.randint(0, 8))
            if not residues:
                residues.append("GLY")
            rng.shuffle(residues)

            pdb_lines = []
            serial = 1
            for residue in residues:
                pdb_lines.append(pdb_line(serial, "CA", residue, residue_number=serial))
                serial += 1
            # These records must all be ignored by a conforming parser.
            pdb_lines.append(pdb_line(serial, "CB", "ALA", residue_number=900)); serial += 1
            pdb_lines.append(pdb_line(serial, "CA", "MSE", residue_number=901)); serial += 1
            pdb_lines.append(pdb_line(serial, "CA", "ARG", record="HETATM", residue_number=902))
            rng.shuffle(pdb_lines)

            with open(fasta_path, "w") as f:
                f.write(fasta_text)
            with open(pdb_path, "w") as f:
                f.writelines(pdb_lines)

            expected = expected_tvd(fasta_path, pdb_path)

            for executable in (submitted_binary, rebuilt_binary):
                # Rewrite inputs before each run so each executable sees the same case.
                with open(fasta_path, "w") as f:
                    f.write(fasta_text)
                with open(pdb_path, "w") as f:
                    f.writelines(pdb_lines)
                if os.path.exists(result_path):
                    os.remove(result_path)

                subprocess.run(
                    [executable], cwd="/home/user", check=True,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                    timeout=10
                )
                assert os.path.isfile(result_path), (
                    f"{executable} did not create {result_path} for generated case {case_number}."
                )
                with open(result_path, "r") as f:
                    actual = f.read().strip()
                assert re.fullmatch(r"[0-9]+\.[0-9]{4}", actual), (
                    f"{executable} did not write a value formatted to exactly 4 decimal places: {actual!r}"
                )
                assert actual == expected, (
                    f"{executable} produced {actual} for generated case {case_number}; expected {expected}."
                )
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
        if os.path.exists(rebuilt_binary):
            os.remove(rebuilt_binary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
