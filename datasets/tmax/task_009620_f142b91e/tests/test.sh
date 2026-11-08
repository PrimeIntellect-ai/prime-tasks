#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import random
import re
import shlex
import stat
import subprocess
import pytest

WORKSPACE = "/home/user/workspace"
SOLVER_C = os.path.join(WORKSPACE, "solver.c")
PIPELINE_NB = os.path.join(WORKSPACE, "pipeline.ipynb")
RUN_SCRIPT = os.path.join(WORKSPACE, "run_pipeline.sh")
SOLVER_BIN = os.path.join(WORKSPACE, "solver")
RESULTS_JSON = os.path.join(WORKSPACE, "results.json")


def test_files_exist():
    assert os.path.isfile(SOLVER_C), f"Expected C program {SOLVER_C} to exist."
    assert os.path.isfile(PIPELINE_NB), f"Expected Jupyter notebook {PIPELINE_NB} to exist."
    assert os.path.isfile(RUN_SCRIPT), f"Expected bash script {RUN_SCRIPT} to exist."


def test_script_executable():
    assert os.access(RUN_SCRIPT, os.X_OK), f"Expected {RUN_SCRIPT} to be executable."


def expected_solution(values):
    a00, a01, a10, a11, b0, b1, lam = values
    a00 += lam
    a11 += lam
    det = a00 * a11 - a01 * a10
    return ((b0 * a11 - a01 * b1) / det,
            (a00 * b1 - b0 * a10) / det)


def run_solver(binary, values):
    proc = subprocess.run(
        [binary] + [format(v, ".17g") for v in values],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert proc.returncode == 0, (
        f"Solver failed for {values}. STDOUT: {proc.stdout!r} STDERR: {proc.stderr!r}"
    )
    match = re.fullmatch(
        r"\s*([+-]?\d+\.\d{6})\s+([+-]?\d+\.\d{6})\s*", proc.stdout
    )
    assert match, f"Solver output must be two floats with 6 decimal places, got {proc.stdout!r}"
    return float(match.group(1)), float(match.group(2))


def test_pipeline_execution(tmp_path):
    # Clean up artifacts if they exist to ensure the script actually builds/runs them.
    if os.path.exists(SOLVER_BIN):
        os.remove(SOLVER_BIN)
    if os.path.exists(RESULTS_JSON):
        os.remove(RESULTS_JSON)

    try:
        result = subprocess.run(
            [RUN_SCRIPT],
            cwd=WORKSPACE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
            timeout=180,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"{RUN_SCRIPT} failed to execute properly.\nSTDOUT: {e.stdout}\nSTDERR: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"{RUN_SCRIPT} timed out")

    assert os.path.isfile(SOLVER_BIN), f"Expected {SOLVER_BIN} to be compiled and exist after running the script."
    assert os.path.isfile(RESULTS_JSON), f"Expected {RESULTS_JSON} to be created after running the script."

    with open(RESULTS_JSON, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS_JSON} is not a valid JSON file.")

    assert "x0" in data, "JSON result is missing key 'x0'"
    assert "x1" in data, "JSON result is missing key 'x1'"

    x0 = float(data["x0"])
    x1 = float(data["x1"])
    expected_x0 = 0.598802
    expected_x1 = 1.197605
    assert abs(x0 - expected_x0) < 1e-4, f"Expected x0 to be near {expected_x0}, but got {x0}"
    assert abs(x1 - expected_x1) < 1e-4, f"Expected x1 to be near {expected_x1}, but got {x1}"

    # Independently compile solver.c so a script-created stand-in cannot hide an
    # incorrect C implementation.
    rebuilt_solver = str(tmp_path / "solver_from_source")
    compile_result = subprocess.run(
        ["gcc", SOLVER_C, "-o", rebuilt_solver],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compile_result.returncode == 0, f"solver.c did not compile:\n{compile_result.stderr}"

    # Exercise both the script-produced executable and independently compiled
    # source on verifier-generated cases rather than only the published example.
    rng = random.SystemRandom()
    cases = []
    while len(cases) < 10:
        values = (
            rng.uniform(-5, 5), rng.uniform(-5, 5),
            rng.uniform(-5, 5), rng.uniform(-5, 5),
            rng.uniform(-5, 5), rng.uniform(-5, 5),
            rng.uniform(0.01, 2.0),
        )
        a00, a01, a10, a11, _, _, lam = values
        det = (a00 + lam) * (a11 + lam) - a01 * a10
        if abs(det) > 0.3:
            expected = expected_solution(values)
            if all(math.isfinite(v) and abs(v) < 10000 for v in expected):
                cases.append(values)

    for binary in (SOLVER_BIN, rebuilt_solver):
        for values in cases:
            actual = run_solver(binary, values)
            expected = expected_solution(values)
            assert abs(actual[0] - expected[0]) < 2e-6, (
                f"Incorrect x0 for inputs {values}: expected {expected[0]}, got {actual[0]}"
            )
            assert abs(actual[1] - expected[1]) < 2e-6, (
                f"Incorrect x1 for inputs {values}: expected {expected[1]}, got {actual[1]}"
            )


def test_notebook_uses_subprocess_and_parses_solver_output(tmp_path):
    with open(PIPELINE_NB, "r", encoding="utf-8") as f:
        notebook = json.load(f)

    trees = []
    for cell in notebook.get("cells", []):
        if cell.get("cell_type") != "code":
            continue
        source = cell.get("source", "")
        if isinstance(source, list):
            source = "".join(source)
        try:
            trees.append(ast.parse(source))
        except SyntaxError:
            pass

    module_aliases = set()
    function_aliases = set()
    for tree in trees:
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    if alias.name == "subprocess":
                        module_aliases.add(alias.asname or "subprocess")
            elif isinstance(node, ast.ImportFrom) and node.module == "subprocess":
                for alias in node.names:
                    function_aliases.add(alias.asname or alias.name)

    assert module_aliases or function_aliases, "Notebook must import the subprocess module"
    has_subprocess_call = False
    for tree in trees:
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            if isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
                has_subprocess_call |= node.func.value.id in module_aliases
            elif isinstance(node.func, ast.Name):
                has_subprocess_call |= node.func.id in function_aliases
    assert has_subprocess_call, "Notebook must call the solver through subprocess"

    # Replace the executable temporarily with an unpredictable test double. A
    # correct notebook must pass the prescribed arguments and parse its output.
    solver_bytes = open(SOLVER_BIN, "rb").read()
    solver_mode = stat.S_IMODE(os.stat(SOLVER_BIN).st_mode)
    notebook_bytes = open(PIPELINE_NB, "rb").read()
    results_bytes = open(RESULTS_JSON, "rb").read() if os.path.exists(RESULTS_JSON) else None
    arg_log = str(tmp_path / "solver_args")
    rng = random.SystemRandom()
    emitted_x0 = round(rng.uniform(20.0, 80.0), 6)
    emitted_x1 = round(rng.uniform(-80.0, -20.0), 6)
    wrapper = (
        "#!/bin/sh\n"
        f"printf '%s\\n' \"$@\" > {shlex.quote(arg_log)}\n"
        f"printf '{emitted_x0:.6f} {emitted_x1:.6f}\\n'\n"
    )

    try:
        with open(SOLVER_BIN, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(SOLVER_BIN, 0o755)
        if os.path.exists(RESULTS_JSON):
            os.remove(RESULTS_JSON)

        proc = subprocess.run(
            ["jupyter", "nbconvert", "--execute", "--to", "notebook", "--inplace", PIPELINE_NB],
            cwd=WORKSPACE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        assert proc.returncode == 0, f"Notebook execution failed.\nSTDOUT: {proc.stdout}\nSTDERR: {proc.stderr}"
        assert os.path.isfile(arg_log), "Notebook did not invoke /home/user/workspace/solver"

        with open(arg_log, "r", encoding="utf-8") as f:
            args = [line.rstrip("\n") for line in f]
        assert len(args) == 7, f"Notebook passed {len(args)} arguments instead of 7: {args}"
        expected_args = [1.0, 2.0, 2.0, 4.0, 3.0, 6.0, 0.01]
        try:
            numeric_args = [float(value) for value in args]
        except ValueError:
            pytest.fail(f"Notebook passed non-numeric solver arguments: {args}")
        assert numeric_args == expected_args, f"Notebook passed wrong solver arguments: {args}"

        assert os.path.isfile(RESULTS_JSON), "Notebook did not create results.json"
        with open(RESULTS_JSON, "r", encoding="utf-8") as f:
            dynamic_data = json.load(f)
        assert "x0" in dynamic_data and "x1" in dynamic_data
        assert abs(float(dynamic_data["x0"]) - emitted_x0) < 1e-9, (
            "Notebook did not parse x0 from the solver's captured output"
        )
        assert abs(float(dynamic_data["x1"]) - emitted_x1) < 1e-9, (
            "Notebook did not parse x1 from the solver's captured output"
        )
    finally:
        with open(SOLVER_BIN, "wb") as f:
            f.write(solver_bytes)
        os.chmod(SOLVER_BIN, solver_mode)
        with open(PIPELINE_NB, "wb") as f:
            f.write(notebook_bytes)
        if results_bytes is None:
            if os.path.exists(RESULTS_JSON):
                os.remove(RESULTS_JSON)
        else:
            with open(RESULTS_JSON, "wb") as f:
                f.write(results_bytes)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
