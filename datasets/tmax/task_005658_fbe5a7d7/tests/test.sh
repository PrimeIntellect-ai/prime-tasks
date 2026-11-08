#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import pwd
import re
import shutil
import subprocess
import tempfile

HOME = "/home/user"
PDB_PATH = "/home/user/data/input.pdb"
RESULTS_PATH = "/home/user/regression_results.txt"
PROFILE_PATH = "/home/user/profile.txt"


def _profile_executable():
    with open(PROFILE_PATH, "r") as f:
        content = f.read()

    paths = re.findall(r"/home/user/[^\s\"'`]+", content)
    paths = [p.rstrip(".,;:)]}") for p in paths]
    candidates = []
    for path in paths:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            with open(path, "rb") as f:
                if f.read(4) == b"\x7fELF":
                    candidates.append(path)

    assert candidates, "profile.txt must name an existing compiled ELF executable under /home/user."
    return candidates[0]


def _pdb_atom(serial, atom_name, residue, b_factor, record="ATOM"):
    line = [" "] * 80
    line[0:6] = list(f"{record:<6}"[:6])
    line[6:11] = list(f"{serial:5d}")
    line[12:16] = list(atom_name)
    line[17:20] = list("ALA")
    line[21] = "A"
    line[22:26] = list(f"{residue:4d}")
    line[30:38] = list(f"{serial * 0.7:8.3f}")
    line[38:46] = list(f"{serial * 0.4:8.3f}")
    line[46:54] = list(f"{serial * 0.2:8.3f}")
    line[54:60] = list(f"{1.0:6.2f}")
    line[60:66] = list(f"{b_factor:6.2f}")
    return "".join(line) + "\n"


def _write_case(xs, ys):
    lines = []
    serial = 1
    for x, y in zip(xs, ys):
        lines.append(_pdb_atom(serial, " N  ", x, y + 100.0))
        serial += 1
        lines.append(_pdb_atom(serial, " CA ", x, y))
        serial += 1
        lines.append(_pdb_atom(serial, " CB ", x, y + 200.0))
        serial += 1
    lines.append(_pdb_atom(serial, " CA ", 999, 999.0, record="HETATM"))
    with open(PDB_PATH, "w") as f:
        f.writelines(lines)


def _expected(xs, ys):
    smoothed = []
    for i in range(len(ys)):
        start = max(0, i - 2)
        end = min(len(ys), i + 3)
        smoothed.append(sum(ys[start:end]) / (end - start))
    x_mean = sum(xs) / len(xs)
    y_mean = sum(smoothed) / len(smoothed)
    numerator = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, smoothed))
    denominator = sum((x - x_mean) ** 2 for x in xs)
    slope = numerator / denominator
    return slope, y_mean - slope * x_mean


def _run_as_user(executable):
    user = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    return subprocess.run(
        [executable], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, preexec_fn=demote
    )


def _exercise(executable, cases):
    for xs, ys in cases:
        _write_case(xs, ys)
        if os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)
        proc = _run_as_user(executable)
        assert proc.returncode == 0, (
            f"{executable} failed with exit status {proc.returncode}: "
            + proc.stderr.decode(errors="replace")
        )
        assert os.path.isfile(RESULTS_PATH), f"{executable} did not generate {RESULTS_PATH}."
        with open(RESULTS_PATH, "r") as f:
            content = f.read()
        slope_match = re.search(r"Slope:\s*(-?\d+\.\d+)", content)
        intercept_match = re.search(r"Intercept:\s*(-?\d+\.\d+)", content)
        assert slope_match is not None, f"Could not parse Slope produced by {executable}."
        assert intercept_match is not None, f"Could not parse Intercept produced by {executable}."
        expected_slope, expected_intercept = _expected(xs, ys)
        actual_slope = float(slope_match.group(1))
        actual_intercept = float(intercept_match.group(1))
        assert abs(actual_slope - expected_slope) < 1e-3, (
            f"{executable} produced slope {actual_slope}; expected {expected_slope:.4f}."
        )
        assert abs(actual_intercept - expected_intercept) < 1e-3, (
            f"{executable} produced intercept {actual_intercept}; expected {expected_intercept:.4f}."
        )


def test_profile_txt_exists_and_completed():
    """Check if profile.txt exists and contains COMPLETED."""
    profile_path = "/home/user/profile.txt"
    assert os.path.isfile(profile_path), f"{profile_path} is missing."
    with open(profile_path, "r") as f:
        content = f.read()
    assert "COMPLETED" in content, f"'COMPLETED' not found in {profile_path}."

    executable = _profile_executable()
    assert executable in content, "The profiled executable path is not present in profile.txt."
    timing = re.search(
        r"(?i)\b(?:elapsed|real|user|sys|time|duration)\b[^\r\n0-9]{0,20}\d|"
        r"\d+(?:\.\d+)?\s*(?:seconds?|secs?|ms|milliseconds?|us|microseconds?)\b",
        content,
    )
    assert timing is not None, "profile.txt must include a numeric timing measurement from profiling."


def test_c_source_compiles_o3_and_program_generates_results():
    sources = sorted(glob.glob("/home/user/**/*.c", recursive=True))
    assert sources, "No C source file exists under /home/user."

    executable = _profile_executable()
    cases = [
        ([4, 9, 15, 22, 31, 43, 58], [31.25, 4.50, 18.75, 7.00, 42.25, 13.50, 27.75]),
        ([2, 5, 11, 18, 29, 44, 62, 83], [8.10, 22.40, 3.30, 51.20, 16.60, 39.90, 5.50, 28.80]),
    ]

    with open(PDB_PATH, "rb") as f:
        original_pdb = f.read()

    build_dir = tempfile.mkdtemp(prefix="verifier_o3_", dir="/tmp")
    os.chmod(build_dir, 0o755)
    compiled = []
    attempts = [[source] for source in sources]
    if len(sources) > 1:
        attempts.append(sources)

    try:
        for index, source_group in enumerate(attempts):
            output = os.path.join(build_dir, f"program_{index}")
            proc = subprocess.run(
                ["gcc", "-O3", *source_group, "-lm", "-o", output],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
            )
            if proc.returncode == 0:
                os.chmod(output, 0o755)
                compiled.append(output)

        assert compiled, "The submitted C source could not be compiled with gcc -O3."

        _exercise(executable, cases)

        compiled_passed = False
        errors = []
        for candidate in compiled:
            try:
                _exercise(candidate, cases)
                compiled_passed = True
                break
            except AssertionError as exc:
                errors.append(str(exc))
        assert compiled_passed, "No gcc -O3 compiled submission passed the behavioral tests: " + "; ".join(errors)
    finally:
        with open(PDB_PATH, "wb") as f:
            f.write(original_pdb)
        if os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)
        restore_proc = _run_as_user(executable)
        assert restore_proc.returncode == 0, "The profiled executable failed on the original input."
        shutil.rmtree(build_dir, ignore_errors=True)


def test_regression_results():
    """Check if regression_results.txt contains the correct derived slope and intercept."""
    pdb_path = "/home/user/data/input.pdb"
    assert os.path.isfile(pdb_path), f"{pdb_path} is missing."

    x_vals = []
    y_raw = []

    # Parse PDB for CA atoms
    with open(pdb_path, "r") as f:
        for line in f:
            if line.startswith("ATOM") and line[12:16] == " CA ":
                res_seq = int(line[22:26].strip())
                b_factor = float(line[60:66].strip())
                x_vals.append(res_seq)
                y_raw.append(b_factor)

    assert len(x_vals) > 0, "No CA atoms found in PDB file."

    # Apply SMA with window size 5
    n = len(y_raw)
    y_smoothed = []
    for i in range(n):
        start = max(0, i - 2)
        end = min(n, i + 3)
        window = y_raw[start:end]
        y_smoothed.append(sum(window) / len(window))

    # Linear regression
    x_mean = sum(x_vals) / n
    y_mean = sum(y_smoothed) / n

    numerator = sum((x - x_mean) * (y - y_mean) for x, y in zip(x_vals, y_smoothed))
    denominator = sum((x - x_mean) ** 2 for x in x_vals)

    expected_slope = numerator / denominator
    expected_intercept = y_mean - expected_slope * x_mean

    results_path = "/home/user/regression_results.txt"
    assert os.path.isfile(results_path), f"{results_path} is missing."

    with open(results_path, "r") as f:
        content = f.read()

    slope_match = re.search(r"Slope:\s*(-?\d+\.\d+)", content)
    intercept_match = re.search(r"Intercept:\s*(-?\d+\.\d+)", content)

    assert slope_match is not None, "Could not parse Slope from regression_results.txt"
    assert intercept_match is not None, "Could not parse Intercept from regression_results.txt"

    actual_slope = float(slope_match.group(1))
    actual_intercept = float(intercept_match.group(1))

    assert abs(actual_slope - expected_slope) < 1e-3, f"Expected slope {expected_slope:.4f}, got {actual_slope}"
    assert abs(actual_intercept - expected_intercept) < 1e-3, f"Expected intercept {expected_intercept:.4f}, got {actual_intercept}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
