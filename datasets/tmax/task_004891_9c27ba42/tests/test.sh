#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import math
import os
import random
import re
import secrets
import stat
import subprocess
import tempfile

BASH_SCRIPT = "/home/user/run_analysis.sh"
PYTHON_SCRIPT = "/home/user/fit_kinetics.py"
RESULTS_FILE = "/home/user/results.txt"
FASTA = "/home/user/data/protein.fasta"
PDB = "/home/user/data/protein.pdb"
KINETICS = "/home/user/data/kinetics.csv"


def run_checked(command, **kwargs):
    return subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=240,
        **kwargs,
    )


def read_result():
    with open(RESULTS_FILE, "r") as f:
        content = f.read().strip()
    match = re.fullmatch(r"Estimated k: (\d+\.\d{3})", content)
    assert match is not None, (
        "results.txt must contain exactly 'Estimated k: X.XXX'; "
        f"content was: {content!r}"
    )
    return float(match.group(1))


def test_scripts_exist():
    bash_script = "/home/user/run_analysis.sh"
    python_script = "/home/user/fit_kinetics.py"

    assert os.path.isfile(bash_script), f"Bash script {bash_script} does not exist."
    assert os.access(bash_script, os.X_OK), f"Bash script {bash_script} is not executable."

    assert os.path.isfile(python_script), f"Python script {python_script} does not exist."


def test_python_source_contains_required_numerical_and_sampling_work():
    with open(PYTHON_SCRIPT, "r") as f:
        source = f.read()
    tree = ast.parse(source)

    call_names = []
    has_loop = False
    for node in ast.walk(tree):
        if isinstance(node, (ast.For, ast.While)):
            has_loop = True
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name):
                call_names.append(func.id.lower())
            elif isinstance(func, ast.Attribute):
                parts = []
                while isinstance(func, ast.Attribute):
                    parts.append(func.attr)
                    func = func.value
                if isinstance(func, ast.Name):
                    parts.append(func.id)
                call_names.append(".".join(reversed(parts)).lower())

    assert any(name.endswith("solve_ivp") or name.endswith("odeint") for name in call_names), \
        "fit_kinetics.py must actually call scipy.integrate.solve_ivp or odeint"

    lower = source.lower()
    uses_emcee = (
        any(name.endswith("ensemblesampler") for name in call_names)
        and any(name.endswith("run_mcmc") for name in call_names)
    )
    random_call = any("random" in name or name.endswith("rand") or name.endswith("randn") for name in call_names)
    custom_mh = (
        has_loop
        and random_call
        and ("metropolis" in lower or "accept" in lower)
        and ("posterior" in lower or "likelihood" in lower)
    )
    assert uses_emcee or custom_mh, \
        "fit_kinetics.py must implement MCMC using emcee or a custom Metropolis-Hastings sampler"


def test_execute_main_entry_point_and_original_result():
    run_checked([BASH_SCRIPT])

    assert os.path.isfile("/home/user/results.txt"), "The file /home/user/results.txt does not exist."
    with open("/home/user/results.txt", "r") as f:
        content = f.read().strip()

    match = re.search(r"Estimated k:\s*(\d+\.\d{3})", content)
    assert match is not None, f"Could not find 'Estimated k: X.XXX' in /home/user/results.txt. Content was: '{content}'"

    k_value = float(match.group(1))
    assert 0.110 <= k_value <= 0.130, f"Estimated k ({k_value}) is outside the acceptable range of [0.110, 0.130]."
    assert re.fullmatch(r"Estimated k: \d+\.\d{3}", content), \
        "results.txt must use the exact requested format"


def test_bash_derives_stability_factor_and_invokes_python():
    rng = secrets.SystemRandom()
    n_c = rng.randint(5, 10)
    n_sg = rng.randint(1, n_c - 1)
    expected_s = n_sg / n_c

    with open(FASTA, "rb") as f:
        old_fasta = f.read()
    with open(PDB, "rb") as f:
        old_pdb = f.read()
    with open(PYTHON_SCRIPT, "rb") as f:
        old_python = f.read()
    old_mode = stat.S_IMODE(os.stat(PYTHON_SCRIPT).st_mode)

    marker = tempfile.mktemp(prefix="stability_arg_", dir="/tmp")
    probe = (
        "import sys\n"
        f"open({marker!r}, 'w').write(sys.argv[1] if len(sys.argv) > 1 else '')\n"
    )

    try:
        with open(FASTA, "w") as f:
            f.write(">random verifier sequence\n")
            f.write("AA" + ("C" * n_c) + "GG\n")
        with open(PDB, "w") as f:
            for i in range(n_sg):
                f.write(f"ATOM  {i + 1:5d}  SG  CYS A{i + 1:4d}       0.000   0.000   0.000  1.00  0.00           S\n")
            f.write("ATOM    900  CB  CYS A 900       0.000   0.000   0.000  1.00  0.00           C\n")
            f.write("ATOM    901  SG  ALA A 901       0.000   0.000   0.000  1.00  0.00           S\n")
            f.write("HETATM  902  SG  CYS A 902       0.000   0.000   0.000  1.00  0.00           S\n")
        with open(PYTHON_SCRIPT, "w") as f:
            f.write(probe)

        run_checked([BASH_SCRIPT])
        assert os.path.isfile(marker), "run_analysis.sh did not invoke /home/user/fit_kinetics.py"
        with open(marker, "r") as f:
            supplied = f.read().strip()
        try:
            supplied_s = float(supplied)
        except ValueError:
            raise AssertionError(f"Python script received a non-numeric stability factor: {supplied!r}")
        assert math.isclose(supplied_s, expected_s, rel_tol=1e-7, abs_tol=1e-9), \
            f"Expected stability factor {n_sg}/{n_c}={expected_s}, but received {supplied_s}"
    finally:
        with open(FASTA, "wb") as f:
            f.write(old_fasta)
        with open(PDB, "wb") as f:
            f.write(old_pdb)
        with open(PYTHON_SCRIPT, "wb") as f:
            f.write(old_python)
        os.chmod(PYTHON_SCRIPT, old_mode)
        if os.path.exists(marker):
            os.unlink(marker)


def test_python_fits_verifier_generated_data_and_calls_scipy_integrator():
    rng = random.Random(secrets.randbits(64))
    stability = rng.uniform(0.22, 0.88)
    true_k = rng.uniform(0.19, 0.235)
    times = [0.0, 0.05, 0.10, 0.15, 0.25, 0.40, 0.60, 0.90,
             1.30, 1.80, 2.50, 3.50, 5.00, 7.00, 10.00]

    with open(KINETICS, "rb") as f:
        old_kinetics = f.read()

    tempdir = tempfile.mkdtemp(prefix="kinetics_verify_", dir="/tmp")
    integration_marker = os.path.join(tempdir, "integration_called")
    sitecustomize = f'''\nimport scipy.integrate as _si\n_marker = {integration_marker!r}\n_old_solve_ivp = _si.solve_ivp\n_old_odeint = _si.odeint\ndef _mark():\n    with open(_marker, "a") as _f:\n        _f.write("1")\ndef solve_ivp(*args, **kwargs):\n    _mark()\n    return _old_solve_ivp(*args, **kwargs)\ndef odeint(*args, **kwargs):\n    _mark()\n    return _old_odeint(*args, **kwargs)\n_si.solve_ivp = solve_ivp\n_si.odeint = odeint\n'''
    with open(os.path.join(tempdir, "sitecustomize.py"), "w") as f:
        f.write(sitecustomize)

    try:
        with open(KINETICS, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["time", "concentration"])
            for t in times:
                exact = 100.0 / (1.0 + (100.0 * true_k * t / (1.0 + stability)))
                observed = exact + rng.gauss(0.0, 2.0)
                writer.writerow([f"{t:.5f}", f"{observed:.8f}"])

        env = os.environ.copy()
        env["PYTHONPATH"] = tempdir + os.pathsep + env.get("PYTHONPATH", "")
        run_checked(["python3", PYTHON_SCRIPT, repr(stability)], env=env)

        assert os.path.isfile(integration_marker), \
            "fit_kinetics.py did not call scipy.integrate.solve_ivp or odeint while fitting"
        estimated = read_result()
        assert abs(estimated - true_k) <= 0.030, \
            f"For verifier-generated data with k={true_k:.5f}, the script estimated {estimated:.3f}"
        assert 0.01 <= estimated <= 0.5, "Estimated k is outside the required prior bounds"
    finally:
        with open(KINETICS, "wb") as f:
            f.write(old_kinetics)
        for name in os.listdir(tempdir):
            path = os.path.join(tempdir, name)
            if os.path.isdir(path):
                import shutil
                shutil.rmtree(path)
            else:
                os.unlink(path)
        os.rmdir(tempdir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
