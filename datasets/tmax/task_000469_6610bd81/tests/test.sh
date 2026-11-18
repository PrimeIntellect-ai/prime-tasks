#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import subprocess

import pytest


def run_checked(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result


def read_ci(path="/home/user/ci_results.txt"):
    assert os.path.isfile(path), f"Results file {path} was not created."
    with open(path, "r") as f:
        content = f.read().strip()
    parts = content.split(",")
    assert len(parts) == 2, f"Expected two comma-separated values in {path}, got: {content}"
    try:
        return float(parts[0]), float(parts[1])
    except ValueError:
        pytest.fail(f"Could not parse floats from {path} content: {content}")


def expected_ci(y0_vals, n_bootstrap):
    import numpy as np

    y0_vals = np.asarray(y0_vals, dtype=float)
    y5_vals = y0_vals / (2.5 * y0_vals + 1)
    np.random.seed(42)
    means = []
    for _ in range(n_bootstrap):
        sample = np.random.choice(y5_vals, size=len(y5_vals), replace=True)
        means.append(np.mean(sample))
    return np.percentile(means, 2.5), np.percentile(means, 97.5)


def test_venv_and_papermill():
    venv_papermill = "/home/user/venv/bin/papermill"
    assert os.path.isfile(venv_papermill), (
        f"papermill executable not found at {venv_papermill}. Ensure the virtual "
        "environment is created and papermill is installed."
    )
    run_checked([
        "/home/user/venv/bin/python", "-c",
        "import numpy, scipy, jupyter, papermill",
    ])


def test_notebook_structure_and_script():
    notebook_path = "/home/user/analysis.ipynb"
    assert os.path.isfile(notebook_path), f"Notebook {notebook_path} is missing."
    with open(notebook_path, "r") as f:
        notebook = json.load(f)
    assert isinstance(notebook.get("cells"), list), "analysis.ipynb is not a valid notebook"

    parameter_cells = [
        cell for cell in notebook["cells"]
        if cell.get("cell_type") == "code"
        and "parameters" in cell.get("metadata", {}).get("tags", [])
    ]
    assert parameter_cells, "Notebook has no code cell tagged 'parameters'"

    valid_default = False
    for cell in parameter_cells:
        source = "".join(cell.get("source", []))
        try:
            tree = ast.parse(source)
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if isinstance(node, (ast.Assign, ast.AnnAssign)):
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                value = node.value
                if any(isinstance(t, ast.Name) and t.id == "n_bootstrap" for t in targets):
                    if isinstance(value, ast.Constant) and type(value.value) is int and value.value == 1000:
                        valid_default = True
    assert valid_default, "The parameters cell must define integer n_bootstrap with default 1000"

    all_source = "\n".join(
        "".join(cell.get("source", []))
        for cell in notebook["cells"] if cell.get("cell_type") == "code"
    )
    assert "/home/user/y0.txt" in all_source, "Notebook does not read /home/user/y0.txt"
    assert "solve_ivp" in all_source, "Notebook does not use scipy.integrate.solve_ivp"
    assert re.search(r"(?:numpy|np)\.random\.seed\s*\(", all_source), "Notebook does not explicitly seed NumPy"
    assert re.search(r"(?:numpy|np)\.random\.choice\s*\(", all_source), "Notebook has no bootstrap sampling"
    assert re.search(r"(?:numpy|np)\.percentile\s*\(", all_source), "Notebook does not use numpy.percentile"
    assert "/home/user/ci_results.txt" in all_source, "Notebook does not write the required results path"

    script_path = "/home/user/run_analysis.sh"
    assert os.path.isfile(script_path), f"Bash script {script_path} is missing."
    with open(script_path, "r") as f:
        script = f.read()
    assert "/home/user/venv/bin/activate" in script, "run_analysis.sh does not activate the required venv"
    assert "papermill" in script, "run_analysis.sh does not invoke papermill"
    assert "/home/user/analysis.ipynb" in script, "run_analysis.sh uses the wrong input notebook"
    assert "/home/user/analysis_out.ipynb" in script, "run_analysis.sh uses the wrong output notebook"
    assert re.search(r"(?:-p|--parameters)\s+n_bootstrap(?:\s+|=)5000(?:\s|$)", script), (
        "run_analysis.sh does not pass n_bootstrap=5000 to papermill"
    )


def test_run_analysis_script():
    script_path = "/home/user/run_analysis.sh"
    assert os.path.isfile(script_path), f"Bash script {script_path} is missing."
    for path in ("/home/user/analysis_out.ipynb", "/home/user/ci_results.txt"):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"run_analysis.sh failed to execute. stderr: {result.stderr}"


def test_notebook_output_exists():
    out_notebook = "/home/user/analysis_out.ipynb"
    assert os.path.isfile(out_notebook), f"Output notebook {out_notebook} was not created."
    with open(out_notebook, "r") as f:
        notebook = json.load(f)
    assert notebook.get("cells"), "Output notebook is empty"
    assert any(
        cell.get("cell_type") == "code" and cell.get("execution_count") is not None
        for cell in notebook["cells"]
    ), "Output notebook contains no executed code cells"


def test_ci_results():
    lower_bound, upper_bound = read_ci()
    expected_lower, expected_upper = expected_ci(
        [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0], 5000
    )
    assert abs(lower_bound - expected_lower) < 1e-4, (
        f"Lower bound {lower_bound} does not match expected {expected_lower}"
    )
    assert abs(upper_bound - expected_upper) < 1e-4, (
        f"Upper bound {upper_bound} does not match expected {expected_upper}"
    )


def test_notebook_on_unseen_data_and_parameter_override(tmp_path):
    hook_dir = tmp_path / "hook"
    hook_dir.mkdir()
    log_path = tmp_path / "calls.jsonl"
    hook = r'''
import json
import os

_log_path = os.environ.get("VERIFIER_CALL_LOG")
def _log(record):
    if _log_path:
        with open(_log_path, "a") as f:
            f.write(json.dumps(record) + "\\n")

try:
    import scipy.integrate as _si
    _real_solve_ivp = _si.solve_ivp
    def _solve_ivp(*args, **kwargs):
        span = args[1] if len(args) > 1 else kwargs.get("t_span")
        method = kwargs.get("method", args[3] if len(args) > 3 else "RK45")
        _log({"event": "solve_ivp", "method": str(method), "span": list(span)})
        return _real_solve_ivp(*args, **kwargs)
    _si.solve_ivp = _solve_ivp

    import numpy as _np
    _real_seed = _np.random.seed
    _real_choice = _np.random.choice
    _real_percentile = _np.percentile
    def _seed(value=None):
        _log({"event": "seed", "value": value})
        return _real_seed(value)
    def _choice(*args, **kwargs):
        _log({"event": "choice", "replace": kwargs.get("replace", True)})
        return _real_choice(*args, **kwargs)
    def _percentile(a, q, *args, **kwargs):
        try:
            qlog = _np.asarray(q).tolist()
        except Exception:
            qlog = str(q)
        _log({"event": "percentile", "q": qlog})
        return _real_percentile(a, q, *args, **kwargs)
    _np.random.seed = _seed
    _np.random.choice = _choice
    _np.percentile = _percentile
except Exception:
    pass
'''
    (hook_dir / "sitecustomize.py").write_text(hook)

    y0_path = "/home/user/y0.txt"
    with open(y0_path, "r") as f:
        original_y0 = f.read()
    unseen = [0.4, 1.3, 2.7, 6.2, 11.0, 17.5]
    output = str(tmp_path / "parameterized_out.ipynb")
    try:
        with open(y0_path, "w") as f:
            f.write("\n".join(map(str, unseen)) + "\n")
        if os.path.exists("/home/user/ci_results.txt"):
            os.remove("/home/user/ci_results.txt")

        env = os.environ.copy()
        env["PYTHONPATH"] = str(hook_dir) + os.pathsep + env.get("PYTHONPATH", "")
        env["VERIFIER_CALL_LOG"] = str(log_path)
        run_checked([
            "/home/user/venv/bin/papermill",
            "/home/user/analysis.ipynb",
            output,
            "-p", "n_bootstrap", "37",
        ], env=env, cwd="/home/user")

        assert os.path.isfile(output), "Papermill did not create the parameterized output notebook"
        lower, upper = read_ci()
        expected_lower, expected_upper = expected_ci(unseen, 37)
        assert abs(lower - expected_lower) < 1e-4
        assert abs(upper - expected_upper) < 1e-4

        assert log_path.is_file(), "Notebook execution did not exercise the monitored scientific functions"
        records = [json.loads(line) for line in log_path.read_text().splitlines() if line.strip()]
        solve_calls = [r for r in records if r.get("event") == "solve_ivp"]
        assert len(solve_calls) >= len(unseen), "solve_ivp was not called for every initial concentration"
        assert all(r.get("method") == "Radau" for r in solve_calls), "solve_ivp was not called with method='Radau'"
        assert all(r.get("span") == [0, 5] or r.get("span") == [0.0, 5.0] for r in solve_calls), (
            "solve_ivp was not called over t=0 to t=5"
        )
        assert any(r.get("event") == "seed" and r.get("value") == 42 for r in records), (
            "Notebook did not execute numpy.random.seed(42)"
        )
        assert any(r.get("event") == "choice" and r.get("replace") is True for r in records), (
            "Notebook did not perform bootstrap sampling with replacement"
        )
        assert any(
            r.get("event") == "percentile"
            and r.get("q") in ([2.5, 97.5], 2.5, 97.5)
            for r in records
        ), "Notebook did not execute numpy.percentile for the confidence interval"
    finally:
        with open(y0_path, "w") as f:
            f.write(original_y0)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
