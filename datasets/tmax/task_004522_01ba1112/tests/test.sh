#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import stat
import subprocess
import sys

import h5py
import numpy as np
import pytest


def test_custom_solver_accuracy():
    agent_script = "/home/user/custom_solver.py"
    legacy_solver = "/app/bin/legacy_solver"
    hidden_input = "/tmp/hidden_test.h5"
    oracle_output = "/tmp/oracle_out.h5"
    agent_output = "/tmp/agent_out.h5"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(legacy_solver), f"Legacy solver missing at {legacy_solver}"

    # The requested artifact must be a genuine Python program, not a launcher for
    # the legacy executable.
    with open(agent_script, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=agent_script)
    except SyntaxError as e:
        pytest.fail(f"custom_solver.py is not valid Python: {e}")

    forbidden_modules = {"subprocess", "ctypes", "importlib"}
    forbidden_os_calls = {
        "system", "popen", "execl", "execle", "execlp", "execlpe",
        "execv", "execve", "execvp", "execvpe", "spawnl", "spawnle",
        "spawnlp", "spawnlpe", "spawnv", "spawnve", "spawnvp", "spawnvpe",
        "posix_spawn", "posix_spawnp"
    }
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            assert not any(alias.name.split(".")[0] in forbidden_modules for alias in node.names), \
                "custom_solver.py must implement the solver rather than launch another program"
        elif isinstance(node, ast.ImportFrom):
            assert (node.module or "").split(".")[0] not in forbidden_modules, \
                "custom_solver.py must implement the solver rather than launch another program"
            if node.module == "os":
                assert not any(alias.name in forbidden_os_calls for alias in node.names), \
                    "custom_solver.py must not launch the legacy solver"
        elif isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                assert node.func.id not in {"__import__", "eval", "exec", "compile"}, \
                    "custom_solver.py must implement the solver directly"
            elif isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
                if node.func.value.id == "os":
                    assert node.func.attr not in forbidden_os_calls, \
                        "custom_solver.py must not launch the legacy solver"

    assert "legacy_solver" not in source and "/app/bin" not in source, \
        "custom_solver.py must not invoke the legacy solver"

    for path in (hidden_input, oracle_output, agent_output):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    # Generate hidden test data, including singular values on both sides of the
    # filtering boundary and exactly at it.
    singular_values = np.array([
        2.0, 1.4, 1.0, 0.7, 0.4, 0.2, 0.1, 0.075, 0.060,
        0.050001, 0.05, 0.049999, 0.04, 0.03, 0.02, 0.01,
        0.005, 0.001, 0.0001, 0.00001
    ], dtype=np.float64)
    with h5py.File(hidden_input, "w") as f:
        for i in range(10):
            grp = f.create_group(f"system_{i}")
            rng = np.random.RandomState(42 + i)
            U, _ = np.linalg.qr(rng.randn(20, 20))
            V, _ = np.linalg.qr(rng.randn(20, 20))
            A = U @ np.diag(singular_values) @ V.T
            b = rng.randn(20)
            grp.create_dataset("A", data=A)
            grp.create_dataset("b", data=b)
    os.chmod(hidden_input, 0o644)

    # Preserve the original oracle comparison, but make both the oracle output
    # and executable unavailable to the unprivileged agent process.
    try:
        subprocess.run(
            [legacy_solver, hidden_input, oracle_output],
            check=True, capture_output=True, text=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Legacy solver failed: {e.stderr}")
    os.chmod(oracle_output, 0o600)

    old_mode = stat.S_IMODE(os.stat(legacy_solver).st_mode)
    os.chmod(legacy_solver, 0)
    try:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", sys.executable, agent_script,
             hidden_input, agent_output],
            capture_output=True, text=True
        )
    finally:
        os.chmod(legacy_solver, old_mode)

    if result.returncode != 0:
        pytest.fail(f"Agent script failed: {result.stderr}")

    assert os.path.exists(agent_output), \
        f"Agent script did not produce output file at {agent_output}"

    max_err = 0.0
    with h5py.File(hidden_input, "r") as f_in, \
         h5py.File(oracle_output, "r") as f_or, \
         h5py.File(agent_output, "r") as f_ag:
        for key in f_or.keys():
            assert key in f_ag, f"Group {key} missing in agent output."
            assert "x" in f_ag[key], \
                f"Dataset 'x' missing in group {key} of agent output."

            x_or = f_or[key]["x"][:]
            x_ag = f_ag[key]["x"][:]
            assert x_or.shape == x_ag.shape, \
                f"Shape mismatch for {key}: expected {x_or.shape}, got {x_ag.shape}"

            # Independently derive the expected result rather than trusting only
            # a program the submission might attempt to delegate to.
            A = f_in[key]["A"][:]
            b = f_in[key]["b"][:]
            U, S, Vt = np.linalg.svd(A)
            S_inv = np.zeros_like(S)
            mask = S >= 0.05
            S_inv[mask] = 1.0 / S[mask]
            expected = Vt.T @ np.diag(S_inv) @ U.T @ b

            assert np.all(np.isfinite(x_ag)), f"Non-finite values in {key}"
            assert np.max(np.abs(x_or - expected)) < 1e-10, \
                f"Oracle/reference disagreement for {key}"
            err = np.max(np.abs(x_or - x_ag))
            max_err = max(max_err, float(err))

    assert max_err < 1e-7, \
        f"Max Absolute Error {max_err} is not < 1e-7. The agent's custom_solver did not replicate the legacy solver accurately."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
