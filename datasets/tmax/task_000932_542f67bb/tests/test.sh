#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/verifier_hook

cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import json
import os
import scipy.integrate

_original_solve_ivp = scipy.integrate.solve_ivp
_log_path = os.environ.get("VERIFY_SOLVE_IVP_LOG")

def _plain(value):
    try:
        return value.tolist()
    except AttributeError:
        try:
            return list(value)
        except TypeError:
            return value

def _recording_solve_ivp(fun, t_span, y0, *args, **kwargs):
    record = {
        "t_span": _plain(t_span),
        "y0": _plain(y0),
        "method": kwargs.get("method", "RK45"),
        "derivatives": {},
    }
    for value in (10.0, 400.0, 800.0):
        try:
            result = fun(0.0, [value])
            result = _plain(result)
            if isinstance(result, list):
                result = result[0]
            record["derivatives"][str(value)] = float(result)
        except Exception as exc:
            record["derivatives"][str(value)] = {"error": repr(exc)}

    if _log_path:
        records = []
        try:
            with open(_log_path, "r") as handle:
                records = json.load(handle)
        except Exception:
            pass
        records.append(record)
        with open(_log_path, "w") as handle:
            json.dump(records, handle)

    return _original_solve_ivp(fun, t_span, y0, *args, **kwargs)

scipy.integrate.solve_ivp = _recording_solve_ivp
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess

import nbformat
import pytest
from scipy.integrate import solve_ivp

INPUT_NB = "/home/user/analysis.ipynb"
OUTPUT_NB = "/home/user/analysis_out.ipynb"
RESULTS = "/home/user/results.json"
CALL_LOG = "/tmp/solve_ivp_calls.json"


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_notebook():
    assert os.path.exists(INPUT_NB), f"Expected notebook {INPUT_NB} is missing."
    assert os.path.isfile(INPUT_NB), f"{INPUT_NB} is not a file."

    try:
        with open(INPUT_NB, "r", encoding="utf-8") as handle:
            submitted = nbformat.read(handle, as_version=4)
    except Exception as exc:
        pytest.fail(f"{INPUT_NB} is not a valid Jupyter notebook: {exc}")

    submitted_sources = [cell.source for cell in submitted.cells]
    assert any(cell.cell_type == "code" and cell.source.strip() for cell in submitted.cells), \
        "analysis.ipynb contains no executable code."

    for path in (OUTPUT_NB, RESULTS, CALL_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = "/tmp/verifier_hook" + (os.pathsep + old_pythonpath if old_pythonpath else "")
    env["VERIFY_SOLVE_IVP_LOG"] = CALL_LOG

    proc = subprocess.run(
        [
            "jupyter", "nbconvert", "--to", "notebook", "--execute",
            "--ExecutePreprocessor.timeout=300",
            "--output", OUTPUT_NB,
            INPUT_NB,
        ],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=360,
    )
    assert proc.returncode == 0, "Headless notebook execution failed:\n" + proc.stdout

    return submitted_sources


def test_notebooks_exist(execute_submitted_notebook):
    """Verify that the input and freshly executed output notebooks exist and are valid."""
    assert os.path.exists(INPUT_NB), f"Expected notebook {INPUT_NB} is missing."
    assert os.path.isfile(INPUT_NB), f"{INPUT_NB} is not a file."
    assert os.path.exists(OUTPUT_NB), f"Expected executed notebook {OUTPUT_NB} is missing."
    assert os.path.isfile(OUTPUT_NB), f"{OUTPUT_NB} is not a file."

    with open(INPUT_NB, "r", encoding="utf-8") as handle:
        current_input = nbformat.read(handle, as_version=4)
    with open(OUTPUT_NB, "r", encoding="utf-8") as handle:
        executed = nbformat.read(handle, as_version=4)

    assert [cell.source for cell in current_input.cells] == execute_submitted_notebook, \
        "The submitted notebook changed itself during verification."
    assert [cell.source for cell in executed.cells] == execute_submitted_notebook, \
        "The executed notebook does not correspond to analysis.ipynb."

    code_cells = [cell for cell in executed.cells if cell.cell_type == "code" and cell.source.strip()]
    assert code_cells, "The executed notebook contains no code cells."
    assert all(cell.execution_count is not None for cell in code_cells), \
        "Not all non-empty code cells were executed."
    assert not any(
        output.get("output_type") == "error"
        for cell in code_cells
        for output in cell.get("outputs", [])
    ), "The executed notebook contains an error output."


def test_ode_was_solved_with_required_model(execute_submitted_notebook):
    """Confirm that execution actually called solve_ivp with the requested ODE."""
    assert os.path.isfile(CALL_LOG), "Notebook execution did not call scipy.integrate.solve_ivp."
    with open(CALL_LOG, "r", encoding="utf-8") as handle:
        calls = json.load(handle)

    def matching(call):
        try:
            span = [float(x) for x in call["t_span"]]
            y0 = [float(x) for x in call["y0"]]
            deriv = call["derivatives"]
            method = str(call["method"]).upper()
            return (
                span == [0.0, 100.0]
                and y0 == [10.0]
                and method == "RK45"
                and math.isclose(float(deriv["10.0"]), 3.95, rel_tol=0, abs_tol=1e-10)
                and math.isclose(float(deriv["400.0"]), 80.0, rel_tol=0, abs_tol=1e-10)
                and math.isclose(float(deriv["800.0"]), 0.0, rel_tol=0, abs_tol=1e-10)
            )
        except (KeyError, TypeError, ValueError):
            return False

    assert any(matching(call) for call in calls), \
        "No solve_ivp call used t_span=(0,100), V(0)=10, default RK45, and the required differential equation."


def test_primer_workflow_is_present(execute_submitted_notebook):
    """Reject a notebook that only emits the hardcoded primer answer."""
    source = "\n".join(execute_submitted_notebook)
    assert "ATGGCCGCCATATTGAGCGGCCGCATTAG" in source, "The required viral sequence is not used."
    assert re.search(r"\b(for|while)\b", source), "No sliding-window iteration is present."
    assert re.search(r"\[[^\]\n]*:[^\]\n]*\]", source), "No contiguous sequence slicing is present."
    gc_evidence = (
        re.search(r"\.count\s*\(\s*['\"]G['\"]\s*\)", source)
        and re.search(r"\.count\s*\(\s*['\"]C['\"]\s*\)", source)
    ) or re.search(r"\bin\s*['\"](?:GC|CG)['\"]", source)
    assert gc_evidence, "No computation of G/C content is present."


def test_results_json(execute_submitted_notebook):
    """Verify that fresh results contain the independently derived correct values."""
    assert os.path.exists(RESULTS), f"Expected results file {RESULTS} is missing."
    assert os.path.isfile(RESULTS), f"{RESULTS} is not a file."

    with open(RESULTS, "r", encoding="utf-8") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS} is not valid JSON.")

    assert "final_V" in data, "Key 'final_V' is missing from results.json."
    assert "best_primer" in data, "Key 'best_primer' is missing from results.json."
    assert set(data) == {"final_V", "best_primer"}, "results.json must contain exactly the required keys."

    def ode(t, y):
        return 0.5 * y[0] * (1 - y[0] / 1000.0) - 0.1 * y[0]

    expected_v = float(round(float(solve_ivp(ode, (0, 100), [10]).y[0, -1]), 2))
    sequence = "ATGGCCGCCATATTGAGCGGCCGCATTAG"
    windows = [sequence[i:i + 8] for i in range(len(sequence) - 8 + 1)]
    expected_primer = max(windows, key=lambda window: sum(base in "GC" for base in window))

    assert isinstance(data["final_V"], float), \
        f"'final_V' must be a float, got {type(data['final_V']).__name__}."
    assert data["final_V"] == expected_v, \
        f"Expected 'final_V' to be {expected_v}, got {data['final_V']}."
    assert data["final_V"] == 800.0, f"Expected 'final_V' to be 800.0, got {data['final_V']}."

    assert data["best_primer"] == expected_primer, \
        f"Expected 'best_primer' to be '{expected_primer}', got '{data['best_primer']}'."
    assert data["best_primer"] == "GCGGCCGC", \
        f"Expected 'best_primer' to be 'GCGGCCGC', got '{data['best_primer']}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
