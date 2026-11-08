#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import inspect
import json
import math
import os
import random
import subprocess
import tempfile

import numpy as np


def test_integrator_fixed():
    integrator_path = "/app/adaptive_solve/adaptive_solve/integrator.py"
    assert os.path.isfile(integrator_path), f"File {integrator_path} is missing."
    with open(integrator_path, "r") as f:
        content = f.read()

    assert "h = h * (tol / err)**0.5" in content, "The integrator.py file does not contain the fixed logic."
    assert "h = h * (err / tol)**0.5" not in content, "The integrator.py file still contains the perturbed logic."


def test_package_is_installed_with_fix():
    importlib.metadata.distribution("adaptive_solve")
    proc = subprocess.run(
        [
            "python3",
            "-c",
            "import inspect, adaptive_solve.integrator as i; print(inspect.getsource(i.integrate_logistic))",
        ],
        cwd="/tmp",
        capture_output=True,
        text=True,
        env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"},
    )
    assert proc.returncode == 0, f"The installed adaptive_solve package cannot be imported: {proc.stderr}"
    assert "h = h * (tol / err)**0.5" in proc.stdout, "The installed package does not contain the fixed adaptation logic."
    assert "h = h * (err / tol)**0.5" not in proc.stdout, "The installed package still contains the broken adaptation logic."


def lcs(x, y):
    row = [0] * (len(y) + 1)
    for a in x:
        new = [0]
        for j, b in enumerate(y, 1):
            new.append(row[j - 1] + 1 if a == b else max(row[j], new[-1]))
        row = new
    return row[-1]


def test_script_uses_package_integrator():
    agent_script = "/home/user/solve.py"
    assert os.path.isfile(agent_script), f"Agent script {agent_script} is missing."

    with tempfile.TemporaryDirectory() as hook_dir:
        marker = os.path.join(hook_dir, "called.json")
        with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
            f.write("""import json
import os
import adaptive_solve
import adaptive_solve.integrator

def fake(r, y0=0.5, t_end=10.0, tol=1e-5):
    with open(os.environ['ADAPTIVE_CALL_MARKER'], 'w') as out:
        json.dump([float(r), y0, t_end, tol], out)
    return 1.23456789, 4242

adaptive_solve.integrate_logistic = fake
adaptive_solve.integrator.integrate_logistic = fake
""")

        seqs = ["ACGTAC", "AGTTC", "CCCCAA"]
        env = os.environ.copy()
        env["PYTHONPATH"] = hook_dir
        env["ADAPTIVE_CALL_MARKER"] = marker
        proc = subprocess.run(
            ["python3", agent_script] + seqs,
            capture_output=True,
            text=True,
            env=env,
        )
        assert proc.returncode == 0, f"Agent script failed while checking package use: {proc.stderr}"
        assert proc.stdout.strip() == "y_final: 1.234568, steps: 4242", "The script did not use adaptive_solve.integrator.integrate_logistic or formatted its result incorrectly."
        assert os.path.isfile(marker), "The package integrator was not called."

        with open(marker) as f:
            r, y0, t_end, tol = json.load(f)
        matrix = np.array([[lcs(x, y) for y in seqs] for x in seqs], dtype=float)
        expected_r = float(np.linalg.svd(matrix, compute_uv=False)[0])
        assert math.isclose(r, expected_r, rel_tol=1e-12, abs_tol=1e-12), "The largest singular value was not passed as r."
        assert y0 == 0.5 and t_end == 10.0 and tol == 1e-5, "The required integrator arguments were not used."


def test_fuzz_equivalence():
    agent_script = "/home/user/solve.py"
    oracle_script = "/tests/solve.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} is missing."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} is missing."

    random.seed(42)
    bases = ['A', 'C', 'G', 'T']

    for i in range(30):
        num_args = random.randint(3, 6)
        args = []
        for _ in range(num_args):
            length = random.randint(5, 15)
            seq = "".join(random.choices(bases, k=length))
            args.append(seq)

        agent_cmd = ["python3", agent_script] + args
        oracle_cmd = ["python3", oracle_script] + args

        agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)
        oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)

        assert agent_proc.returncode == 0, f"Agent script failed on input {args}. Stderr: {agent_proc.stderr}"
        assert oracle_proc.returncode == 0, f"Oracle script failed on input {args}. Stderr: {oracle_proc.stderr}"

        agent_out = agent_proc.stdout.strip()
        oracle_out = oracle_proc.stdout.strip()

        assert agent_out == oracle_out, f"Mismatch on input {args}.\nExpected:\n{oracle_out}\nGot:\n{agent_out}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
