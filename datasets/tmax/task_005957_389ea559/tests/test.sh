#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_network_diffusion.py
import glob
import json
import math
import os
import re
import subprocess
import sys
import tempfile

import numpy as np

HOME = "/home/user"
SRC = os.path.join(HOME, "network_diffusion.c")
RESULT = os.path.join(HOME, "result.txt")
PLOT = os.path.join(HOME, "plot.png")
EXPERIMENTAL = np.array([0.370, 0.286, 0.205, 0.139], dtype=float)


def simulate(beta):
    L = np.array([[1, -1, 0, 0],
                  [-1, 2, -1, 0],
                  [0, -1, 2, -1],
                  [0, 0, -1, 1]], dtype=float)
    x = np.array([1.0, 0.0, 0.0, 0.0], dtype=float)
    dt = 0.01
    for _ in range(int(5.0 / dt)):
        x = x - dt * beta * L.dot(x)
    return x


def expected_optimum():
    best_beta = None
    best_kl = float("inf")
    for i in range(10, 101):
        beta = i / 100.0
        q = simulate(beta)
        kl = float(np.sum(EXPERIMENTAL * np.log(EXPERIMENTAL / q)))
        if kl < best_kl:
            best_kl = kl
            best_beta = beta
    return best_beta


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//.*", "", text)


def function_bodies(source):
    bodies = []
    pattern = re.compile(r"\b([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{")
    excluded = {"if", "for", "while", "switch"}
    for match in pattern.finditer(source):
        name = match.group(1)
        if name in excluded:
            continue
        start = match.end() - 1
        depth = 0
        for pos in range(start, len(source)):
            if source[pos] == "{":
                depth += 1
            elif source[pos] == "}":
                depth -= 1
                if depth == 0:
                    bodies.append((name, source[start + 1:pos]))
                    break
    return bodies


def test_complete_workflow():
    assert os.path.isfile(SRC), f"Expected {SRC} to exist."
    with open(SRC, "r", encoding="utf-8", errors="replace") as f:
        source = strip_comments(f.read())

    dt_values = [float(v) for v in re.findall(r"\bdt\s*=\s*([0-9]+(?:\.[0-9]*)?|\.[0-9]+)", source)]
    assert dt_values and all(abs(v - 0.01) < 1e-12 for v in dt_values), \
        f"The C integrator must assign dt = 0.01; found {dt_values}."
    t_values = [float(v) for v in re.findall(r"\bT\s*=\s*([0-9]+(?:\.[0-9]*)?|\.[0-9]+)", source)]
    assert t_values and any(abs(v - 5.0) < 1e-12 for v in t_values), "T must remain 5.0."

    numeric_tokens = [float(v) for v in re.findall(r"(?<![A-Za-z_])(?:\d+\.\d+|\.\d+)(?![A-Za-z_])", source)]
    for value in [0.10, 1.00, 0.370, 0.286, 0.205, 0.139]:
        assert any(abs(token - value) < 1e-12 for token in numeric_tokens), \
            f"Missing required model-fitting constant {value}."
    assert re.search(r"\b(for|while)\s*\(", source), "The C program must contain a search loop."

    bodies = function_bodies(source)
    assert any(name != "main" and re.search(r"\blog\s*\(", body) for name, body in bodies), \
        "KL divergence must be implemented as a function using log()."

    binary = "/tmp/network_diffusion_submission"
    compile_run = subprocess.run(
        ["gcc", "-std=c11", "-O2", SRC, "-lm", "-o", binary],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
    assert compile_run.returncode == 0, f"network_diffusion.c did not compile:\n{compile_run.stderr}"

    if os.path.lexists(RESULT):
        os.remove(RESULT)
    run = subprocess.run([binary], cwd=HOME, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True, timeout=30)
    assert run.returncode == 0, f"Compiled C program failed:\n{run.stderr}"

    # Preserve the original result assertions, now checked on freshly generated output.
    assert os.path.exists(RESULT), f"Expected {RESULT} to exist."
    assert os.path.isfile(RESULT), f"Expected {RESULT} to be a file."
    with open(RESULT, "r") as f:
        content = f.read().strip()
    assert expected_optimum() == 0.45
    assert content == "0.45", \
        f"Expected optimal beta in result.txt to be '0.45', but got '{content}'."

    scripts = sorted(glob.glob(os.path.join(HOME, "*.py")))
    assert scripts, "Expected a Python visualization script in /home/user/."

    hook_dir = tempfile.mkdtemp(prefix="plot_hook_")
    calls_path = os.path.join(hook_dir, "bar_calls.jsonl")
    hook = r'''
import json, os
try:
    from matplotlib.axes import Axes
    _original_bar = Axes.bar
    def _recording_bar(self, x, height, *args, **kwargs):
        try:
            import numpy as _np
            rec = {"x": _np.asarray(x, dtype=float).reshape(-1).tolist(),
                   "height": _np.asarray(height, dtype=float).reshape(-1).tolist()}
            with open(os.environ["BAR_CALL_LOG"], "a") as f:
                f.write(json.dumps(rec) + "\n")
        except Exception:
            pass
        return _original_bar(self, x, height, *args, **kwargs)
    Axes.bar = _recording_bar
except Exception:
    pass
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
        f.write(hook)

    successful_script = None
    for script in scripts:
        if os.path.lexists(PLOT):
            os.remove(PLOT)
        if os.path.exists(calls_path):
            os.remove(calls_path)
        env = os.environ.copy()
        env["MPLBACKEND"] = "Agg"
        env["BAR_CALL_LOG"] = calls_path
        env["PYTHONPATH"] = hook_dir + os.pathsep + env.get("PYTHONPATH", "")
        proc = subprocess.run([sys.executable, script], cwd=HOME, env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, timeout=30)
        if proc.returncode == 0 and os.path.isfile(PLOT) and os.path.getsize(PLOT) > 0:
            successful_script = script
            break

    assert successful_script is not None, \
        "No Python script successfully generated /home/user/plot.png."

    # Preserve the original plot assertions.
    assert os.path.exists(PLOT), f"Expected {PLOT} to exist."
    assert os.path.isfile(PLOT), f"Expected {PLOT} to be a file."
    assert os.path.getsize(PLOT) > 0, f"Expected {PLOT} to be a non-empty file."

    import matplotlib.image as mpimg
    image = mpimg.imread(PLOT)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100, \
        "plot.png must be a valid, nontrivial PNG image."

    records = []
    if os.path.exists(calls_path):
        with open(calls_path) as f:
            for line in f:
                try:
                    records.append(json.loads(line))
                except Exception:
                    pass
    vectors = [np.asarray(r.get("height", []), dtype=float) for r in records]
    vectors = [v for v in vectors if v.size == 4 and np.all(np.isfinite(v))]
    simulated = simulate(expected_optimum())
    assert any(np.allclose(v, EXPERIMENTAL, atol=0.002, rtol=0) for v in vectors), \
        "Grouped bar chart must include the four experimental values."
    assert any(np.allclose(v, simulated, atol=0.015, rtol=0) for v in vectors), \
        "Grouped bar chart must include the simulated distribution at the optimal beta."
TEST_EOF

if python3 -m pytest /tmp/test_network_diffusion.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
