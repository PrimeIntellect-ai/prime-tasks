#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import subprocess
import textwrap

PYTHON = "/home/user/sim_env/bin/python"
SCRIPT = "/home/user/run_sim.py"
RESULTS = "/home/user/results.txt"
EXPECTED = "Mean: 7.9016, StdDev: 4.8878"


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=240, **kwargs)


def test_complete_simulation():
    # Preserve the original environment and artifact assertions.
    assert os.path.isfile(PYTHON), f"Virtual environment Python executable not found at {PYTHON}"
    assert os.access(PYTHON, os.X_OK), f"Python executable at {PYTHON} is not executable"
    assert os.path.isfile(SCRIPT), f"Simulation script not found at {SCRIPT}"

    # Confirm this is a real venv containing importable NumPy and SciPy installations.
    probe = run([PYTHON, "-c", textwrap.dedent("""
        import json, os, sys
        import numpy, scipy
        print(json.dumps({
            'prefix': os.path.realpath(sys.prefix),
            'numpy': os.path.realpath(numpy.__file__),
            'scipy': os.path.realpath(scipy.__file__),
        }))
    """)])
    assert probe.returncode == 0, probe.stderr
    info = json.loads(probe.stdout.strip().splitlines()[-1])
    prefix = os.path.realpath("/home/user/sim_env")
    assert info["prefix"] == prefix
    assert info["numpy"].startswith(prefix + os.sep), info
    assert info["scipy"].startswith(prefix + os.sep), info

    source = open(SCRIPT, "r", encoding="utf-8").read()
    tree = ast.parse(source, filename=SCRIPT)

    # Locate the required h=1e-5 central-difference construction. The later
    # mutation test verifies that this construction actually controls the force.
    def numeric_value(node):
        try:
            value = eval(compile(ast.Expression(node), "<constant>", "eval"),
                         {"__builtins__": {}}, {})
            return float(value) if isinstance(value, (int, float)) else None
        except Exception:
            return None

    h_names = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value_node = node.value
            value = numeric_value(value_node)
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if value is not None and math.isclose(value, 1e-5, rel_tol=0, abs_tol=1e-15):
                for target in targets:
                    if isinstance(target, ast.Name):
                        h_names.add(target.id)
    assert h_names, "No numerical central-difference step h=1e-5 was defined"

    central_difference_found = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.BinOp) or not isinstance(node.op, ast.Div):
            continue
        names = {n.id for n in ast.walk(node) if isinstance(n, ast.Name)}
        constants = [numeric_value(n) for n in ast.walk(node)
                     if isinstance(n, (ast.Constant, ast.UnaryOp, ast.BinOp))]
        has_two = any(v is not None and math.isclose(v, 2.0) for v in constants)
        numerator_subtractions = [n for n in ast.walk(node.left)
                                  if isinstance(n, ast.BinOp) and isinstance(n.op, ast.Sub)]
        for subtraction in numerator_subtractions:
            left_has_plus_h = any(
                isinstance(n, ast.BinOp) and isinstance(n.op, ast.Add) and
                any(isinstance(x, ast.Name) and x.id in h_names for x in ast.walk(n))
                for n in ast.walk(subtraction.left)
            )
            right_has_minus_h = any(
                isinstance(n, ast.BinOp) and isinstance(n.op, ast.Sub) and
                any(isinstance(x, ast.Name) and x.id in h_names for x in ast.walk(n))
                for n in ast.walk(subtraction.right)
            )
            if left_has_plus_h and right_has_minus_h and has_two and names.intersection(h_names):
                central_difference_found = True
    assert central_difference_found, "Required (V(x+h)-V(x-h))/(2*h) central difference not found"

    # Instrument an actual execution without changing its numerical behavior.
    hook_dir = "/tmp/sim_hooks"
    os.makedirs(hook_dir, exist_ok=True)
    telemetry = "/tmp/sim_telemetry.json"
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(textwrap.dedent("""
            import atexit, json, os
            import numpy as np
            import scipy.integrate as si
            events = []
            _seed = np.random.seed
            _normal = np.random.standard_normal
            _trap = si.trapezoid
            def seed(*args, **kwargs):
                events.append({'kind': 'seed', 'args': list(args)})
                return _seed(*args, **kwargs)
            def standard_normal(*args, **kwargs):
                size = args[0] if args else kwargs.get('size')
                events.append({'kind': 'normal', 'size': list(size) if isinstance(size, tuple) else size})
                return _normal(*args, **kwargs)
            def trapezoid(y, *args, **kwargs):
                dx = kwargs.get('dx', args[1] if len(args) > 1 else 1.0)
                axis = kwargs.get('axis', args[2] if len(args) > 2 else -1)
                events.append({'kind': 'trapezoid', 'shape': list(np.shape(y)), 'dx': float(dx), 'axis': int(axis)})
                return _trap(y, *args, **kwargs)
            np.random.seed = seed
            np.random.standard_normal = standard_normal
            si.trapezoid = trapezoid
            @atexit.register
            def save():
                path = os.environ.get('SIM_TELEMETRY')
                if path:
                    with open(path, 'w') as out:
                        json.dump(events, out)
        """))

    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    if os.path.exists(telemetry):
        os.remove(telemetry)
    env = os.environ.copy()
    env["PYTHONPATH"] = hook_dir
    env["SIM_TELEMETRY"] = telemetry
    execution = run([PYTHON, SCRIPT], env=env)
    assert execution.returncode == 0, execution.stdout + execution.stderr
    assert os.path.isfile(RESULTS), f"Results file not found at {RESULTS}"
    assert os.path.isfile(telemetry), "Simulation execution produced no telemetry"

    events = json.load(open(telemetry, "r", encoding="utf-8"))
    seed_events = [e for e in events if e["kind"] == "seed"]
    normal_events = [e for e in events if e["kind"] == "normal"]
    trap_events = [e for e in events if e["kind"] == "trapezoid"]
    assert seed_events and seed_events[0]["args"] == [42], events
    assert len(normal_events) == 1 and normal_events[0]["size"] == [5000, 1000], events
    assert len(trap_events) >= 1, events
    valid_trap = False
    for event in trap_events:
        shape = event["shape"]
        axis = event["axis"] % len(shape) if shape else -1
        if (sorted(shape) == [1001, 5000] and shape[axis] == 1001 and
                math.isclose(event["dx"], 0.01, rel_tol=0, abs_tol=1e-15)):
            valid_trap = True
    assert valid_trap, "scipy.integrate.trapezoid was not called on 5000 paths of 1001 points with dx=0.01"

    # Preserve the original exact result assertion after freshly executing the script.
    with open(RESULTS, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content == EXPECTED, f"Results file content is incorrect. Expected '{EXPECTED}', but got '{content}'"

    # Change only the central-difference step in a temporary copy. A genuine
    # numerical-force implementation must follow this changed value; an analytic
    # force or hardcoded output will not.
    class ChangeH(ast.NodeTransformer):
        def __init__(self):
            self.changed = 0
        def visit_Assign(self, node):
            self.generic_visit(node)
            targets = [t.id for t in node.targets if isinstance(t, ast.Name)]
            if h_names.intersection(targets):
                node.value = ast.copy_location(ast.Constant(value=0.5), node.value)
                self.changed += 1
            return node
        def visit_AnnAssign(self, node):
            self.generic_visit(node)
            if isinstance(node.target, ast.Name) and node.target.id in h_names:
                node.value = ast.copy_location(ast.Constant(value=0.5), node.value)
                self.changed += 1
            return node

    changer = ChangeH()
    mutant_tree = ast.fix_missing_locations(changer.visit(ast.parse(source)))
    assert changer.changed > 0
    mutant = "/tmp/run_sim_h_mutant.py"
    with open(mutant, "w", encoding="utf-8") as f:
        f.write(ast.unparse(mutant_tree) + "\n")

    oracle = "/tmp/oracle_h_mutant.py"
    with open(oracle, "w", encoding="utf-8") as f:
        f.write(textwrap.dedent("""
            import numpy as np
            from scipy.integrate import trapezoid
            np.random.seed(42)
            npaths, nsteps, dt, D, h = 5000, 1000, 0.01, 0.5, 0.5
            Z = np.random.standard_normal((npaths, nsteps))
            x = np.empty((npaths, nsteps + 1))
            x[:, 0] = -1.0
            def V(q): return 0.25*q**4 - 0.5*q**2
            for i in range(nsteps):
                force = -(V(x[:, i] + h) - V(x[:, i] - h)) / (2*h)
                x[:, i+1] = x[:, i] + force*dt + np.sqrt(2*D*dt)*Z[:, i]
            y = trapezoid(x*x, dx=dt, axis=1)
            print(f'Mean: {np.mean(y):.4f}, StdDev: {np.std(y, ddof=1):.4f}')
        """))
    oracle_run = run([PYTHON, oracle])
    assert oracle_run.returncode == 0, oracle_run.stderr
    mutant_expected = oracle_run.stdout.strip()

    mutant_run = run([PYTHON, mutant])
    assert mutant_run.returncode == 0, mutant_run.stdout + mutant_run.stderr
    assert os.path.isfile(RESULTS)
    mutant_actual = open(RESULTS, "r", encoding="utf-8").read().strip()
    assert mutant_actual == mutant_expected, (
        "Changing h did not produce the independently derived central-difference result: "
        f"expected {mutant_expected!r}, got {mutant_actual!r}"
    )

    # Leave the requested normal result as the final artifact.
    final_run = run([PYTHON, SCRIPT])
    assert final_run.returncode == 0, final_run.stdout + final_run.stderr
    assert open(RESULTS, "r", encoding="utf-8").read().strip() == EXPECTED
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
