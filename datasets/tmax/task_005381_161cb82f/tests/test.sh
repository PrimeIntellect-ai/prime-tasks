#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import tempfile


def test_source_code_exists():
    """Check that the C++ source code file exists."""
    src_path = "/home/user/src/rms_calc.cpp"
    assert os.path.isfile(src_path), f"Source file {src_path} does not exist."


def test_executable_exists_and_runnable():
    """Check that the compiled executable exists and has execute permissions."""
    bin_path = "/home/user/bin/rms_calc"
    assert os.path.isfile(bin_path), f"Executable {bin_path} does not exist."
    assert os.access(bin_path, os.X_OK), f"File {bin_path} is not executable."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {bin_path} is not a compiled ELF executable."


def test_rms_result_correct():
    """Compute the expected RMS from the PDB file and verify the program output."""
    pdb_path = "/home/user/data/molecule.pdb"
    result_path = "/home/user/output/rms_result.txt"

    assert os.path.isfile(pdb_path), f"PDB file {pdb_path} is missing."
    assert os.path.isfile(result_path), f"Result file {result_path} is missing."

    sum_sq = 0.0
    count = 0
    with open(pdb_path, "r") as f:
        for line in f:
            if line.startswith("ATOM  "):
                x = float(line[30:38])
                y = float(line[38:46])
                z = float(line[46:54])
                sum_sq += x*x + y*y + z*z
                count += 1

    assert count > 0, "No ATOM records found in the PDB file."
    expected_rms = math.sqrt(sum_sq / count)
    expected_str = f"RMS: {expected_rms:.4f}"

    with open(result_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_str, (
        f"Incorrect RMS result in {result_path}. "
        f"Expected '{expected_str}', got '{actual_content}'."
    )


def test_analytical_result_correct():
    """Verify the analytical expected value is correctly written."""
    analytical_path = "/home/user/output/analytical.txt"
    assert os.path.isfile(analytical_path), f"Analytical result file {analytical_path} is missing."

    expected_analytical = "Expected: 10.0000"
    with open(analytical_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_analytical, (
        f"Incorrect analytical result in {analytical_path}. "
        f"Expected '{expected_analytical}', got '{actual_content}'."
    )


def _make_probe(rng, count):
    lines = [
        "REMARK    999.000 999.000 999.000 must not be parsed\n",
        f"HETATM{1:5d}  CA  ALA A   1    {99.0:8.3f}{98.0:8.3f}{97.0:8.3f}  1.00  0.00           C  \n",
    ]
    for i in range(1, count + 1):
        x = rng.uniform(-87.0, 93.0)
        y = rng.uniform(-61.0, 79.0)
        z = rng.uniform(-49.0, 101.0)
        lines.append(
            f"ATOM  {i:5d}  CA  ALA A   1    {x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n"
        )
    rng.shuffle(lines)

    total = 0.0
    parsed = 0
    for line in lines:
        if line.startswith("ATOM  "):
            x = float(line[30:38])
            y = float(line[38:46])
            z = float(line[46:54])
            total += x*x + y*y + z*z
            parsed += 1
    return "".join(lines), f"RMS: {math.sqrt(total / parsed):.4f}"


def _run_and_check(binary, expected):
    result_path = "/home/user/output/rms_result.txt"
    try:
        os.remove(result_path)
    except FileNotFoundError:
        pass

    proc = subprocess.run(
        [binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert proc.returncode == 0, (
        f"{binary} exited with {proc.returncode}; stderr: {proc.stderr}"
    )

    stdout_value = proc.stdout.strip()
    file_value = None
    if os.path.isfile(result_path):
        with open(result_path, "r") as f:
            file_value = f.read().strip()

    assert stdout_value == expected or file_value == expected, (
        f"{binary} did not calculate the probe RMS. Expected '{expected}', "
        f"stdout was {stdout_value!r}, output file was {file_value!r}."
    )


def test_executable_and_o3_rebuilt_source_compute_rms():
    """Execute both the submitted binary and an independent -O3 build on derived probes."""
    src_path = "/home/user/src/rms_calc.cpp"
    submitted_bin = "/home/user/bin/rms_calc"
    pdb_path = "/home/user/data/molecule.pdb"
    result_path = "/home/user/output/rms_result.txt"

    with open(pdb_path, "rb") as f:
        original_pdb = f.read()
    original_result = None
    if os.path.isfile(result_path):
        with open(result_path, "rb") as f:
            original_result = f.read()

    fd, rebuilt_bin = tempfile.mkstemp(prefix="rms_calc_o3_", dir="/tmp")
    os.close(fd)
    os.remove(rebuilt_bin)

    try:
        compile_proc = subprocess.run(
            ["g++", "-O3", src_path, "-o", rebuilt_bin],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert compile_proc.returncode == 0, (
            "Source does not compile with g++ -O3: " + compile_proc.stderr
        )
        assert os.path.isfile(rebuilt_bin) and os.access(rebuilt_bin, os.X_OK)

        rng = secrets.SystemRandom()
        for count in (7, 31):
            probe, expected = _make_probe(rng, count)
            with open(pdb_path, "w") as f:
                f.write(probe)
            _run_and_check(submitted_bin, expected)
            _run_and_check(rebuilt_bin, expected)
    finally:
        with open(pdb_path, "wb") as f:
            f.write(original_pdb)
        if original_result is None:
            try:
                os.remove(result_path)
            except FileNotFoundError:
                pass
        else:
            with open(result_path, "wb") as f:
                f.write(original_result)
        try:
            os.remove(rebuilt_bin)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
