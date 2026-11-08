#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess

SOURCE = "/home/user/spectral_analysis.c"
EXECUTABLE = "/home/user/analyzer"
PDB = "/home/user/helix.pdb"
OUTPUT = "/home/user/peak_frequency.txt"
REBUILT = "/tmp/analyzer_rebuilt"


def test_c_source_exists():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} does not exist."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {EXECUTABLE} is not a compiled ELF executable."


def test_peak_frequency_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content == "15", f"Expected peak frequency to be 15, but got '{content}'."


def pdb_line(serial, atom_name, residue, x, y, z):
    return (
        f"ATOM  {serial:5d}  {atom_name:<2s}  ALA A{residue:4d}    "
        f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n"
    )


def expected_peak_from_pdb(path):
    signal = []
    with open(path, "r") as f:
        for line in f:
            if line.startswith(("ATOM  ", "HETATM")) and len(line) >= 38:
                if line[12:16].strip() == "CA":
                    signal.append(float(line[30:38]))

    n = len(signal)
    assert n >= 4
    best_k = None
    best_power = -1.0
    for k in range(1, n // 2):
        re = 0.0
        im = 0.0
        for j, value in enumerate(signal):
            angle = 2.0 * math.pi * k * j / n
            re += value * math.cos(angle)
            im -= value * math.sin(angle)
        power = re * re + im * im
        if power > best_power:
            best_power = power
            best_k = k
    return best_k


def write_case(path, n, target, secondary, phase):
    lines = []
    serial = 1
    for i in range(n):
        # Large non-CA coordinates ensure that programs must filter atom names.
        lines.append(pdb_line(serial, "CB", i + 1, 7000.0 - i, -6000.0, 5000.0))
        serial += 1
        x = (
            2.75
            + 7.5 * math.cos(2.0 * math.pi * target * i / n + phase)
            + 1.4 * math.cos(2.0 * math.pi * secondary * i / n + 0.37)
            + 0.2 * math.sin(2.0 * math.pi * i / n)
        )
        y = 3.0 * math.sin(2.0 * math.pi * target * i / n + phase)
        z = 0.5 * i
        lines.append(pdb_line(serial, "CA", i + 1, x, y, z))
        serial += 1
    with open(path, "w") as f:
        f.writelines(lines)


def run_and_check(program, expected):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [program], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=8
    )
    assert result.returncode == 0, (
        f"{program} exited with {result.returncode}: {result.stderr}"
    )
    assert result.stdout.strip() == str(expected), (
        f"{program} printed {result.stdout!r}; expected {expected}."
    )
    assert os.path.isfile(OUTPUT), f"{program} did not create {OUTPUT}."
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content == str(expected), (
        f"{program} wrote {content!r}; expected {expected}."
    )


def test_source_and_executable_process_pdb_and_compute_dft():
    build = subprocess.run(
        ["gcc", "-O3", "-o", REBUILT, SOURCE, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert build.returncode == 0, f"C source failed to compile: {build.stderr}"

    with open(PDB, "rb") as f:
        original_pdb = f.read()
    original_output = None
    if os.path.exists(OUTPUT):
        with open(OUTPUT, "rb") as f:
            original_output = f.read()

    try:
        original_expected = expected_peak_from_pdb(PDB)
        assert original_expected == 15
        run_and_check(EXECUTABLE, original_expected)
        run_and_check(REBUILT, original_expected)

        rng = random.SystemRandom()
        for n in (48, 64, 80):
            candidates = list(range(3, n // 2 - 2))
            target = rng.choice(candidates)
            secondary = rng.choice([k for k in candidates if k != target])
            phase = rng.random() * 2.0 * math.pi
            write_case(PDB, n, target, secondary, phase)
            expected = expected_peak_from_pdb(PDB)
            assert expected == target
            run_and_check(EXECUTABLE, expected)
            run_and_check(REBUILT, expected)
    finally:
        with open(PDB, "wb") as f:
            f.write(original_pdb)
        if original_output is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
