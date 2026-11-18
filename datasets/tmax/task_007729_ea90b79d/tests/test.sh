#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import ast
import math
import os
import re
import shutil
import stat
import subprocess

HOME = '/home/user'
PIPELINE = f'{HOME}/run_pipeline.sh'
IMP = f'{HOME}/data/impressions.csv'
CONV = f'{HOME}/data/conversions.csv'
PROB = f'{HOME}/prob_B_better.txt'
PLOT = f'{HOME}/posterior_plot.png'
PLOT_SCRIPT = f'{HOME}/scripts/plot_results.py'
VENV = f'{HOME}/venv'


def run(cmd, timeout=600, env=None):
    completed = subprocess.run(
        cmd, cwd=HOME, env=env, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=timeout
    )
    assert completed.returncode == 0, (
        f"Command failed ({completed.returncode}): {' '.join(cmd)}\n"
        f"{completed.stdout[-6000:]}"
    )
    return completed.stdout


def read_probability():
    assert os.path.isfile(PROB), (
        f"File {PROB} does not exist. The Bayesian inference script may not "
        "have run or saved the output correctly."
    )
    content = open(PROB).read().strip()
    assert re.fullmatch(r'(?:0(?:\.\d+)?|1(?:\.0+)?)', content), \
        f"Invalid probability text: {content!r}"
    assert re.fullmatch(r'\d\.\d{4}', content), \
        f"Probability must be rounded to exactly four decimal places, got {content!r}"
    return content, float(content)


def pipeline_sources(pipeline_text):
    found = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d != 'venv' and not d.startswith('.')]
        if root.startswith(f'{HOME}/data'):
            continue
        for name in files:
            path = os.path.join(root, name)
            if path in (PIPELINE, PLOT_SCRIPT) or path in (PROB, PLOT):
                continue
            if name.endswith(('.py', '.R', '.r', '.js', '.jl', '.sh')):
                rel = os.path.relpath(path, HOME)
                if path in pipeline_text or rel in pipeline_text or name in pipeline_text:
                    found.append(path)
    return found


def const_eval(node, values):
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return node.value
    if isinstance(node, ast.Name):
        return values.get(node.id)
    if isinstance(node, ast.BinOp):
        left, right = const_eval(node.left, values), const_eval(node.right, values)
        if left is None or right is None:
            return None
        if isinstance(node.op, ast.Mult): return left * right
        if isinstance(node.op, ast.Pow): return left ** right
        if isinstance(node.op, ast.Add): return left + right
        if isinstance(node.op, ast.Sub): return left - right
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == 'int' and node.args:
        return int(const_eval(node.args[0], values))
    return None


def python_has_exact_sampling(path):
    try:
        tree = ast.parse(open(path, encoding='utf-8').read(), filename=path)
    except Exception:
        return False
    values = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            value = const_eval(node.value, values)
            if value is not None:
                values[node.targets[0].id] = value
    million_sample_calls = 0
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute):
            fname = node.func.attr
        elif isinstance(node.func, ast.Name):
            fname = node.func.id
        else:
            fname = ''
        if fname not in ('beta', 'rvs', 'random_sample', 'sample'):
            continue
        sizes = []
        for kw in node.keywords:
            if kw.arg in ('size', 'n', 'samples'):
                sizes.append(const_eval(kw.value, values))
        if fname == 'beta' and len(node.args) >= 3:
            sizes.append(const_eval(node.args[2], values))
        if any(v == 1000000 for v in sizes):
            million_sample_calls += 1
    return million_sample_calls >= 2


def has_exact_sampling(sources):
    for path in sources:
        if path.endswith('.py') and python_has_exact_sampling(path):
            return True
        text = open(path, encoding='utf-8', errors='ignore').read()
        million = r'(?:1_?000_?000|10\s*\*\*\s*6|1(?:\.0)?[eE]\+?6|1000\s*\*\s*1000)'
        # Non-Python implementations still must visibly configure one million samples.
        if re.search(million, text) and len(re.findall(r'(?i)(?:beta|sample|draw|r(?:beta|vs))', text)) >= 2:
            return True
    return False


def check_plot():
    assert os.path.isfile(PLOT), f"Plot file {PLOT} does not exist. The plotting script may not have run or failed."
    size = os.path.getsize(PLOT)
    assert size > 5000, f"Plot file {PLOT} is suspiciously small ({size} bytes). It might be blank or corrupted."
    with open(PLOT, 'rb') as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', f"File {PLOT} is not a valid PNG image."

    checker = r'''
import matplotlib.image as mpimg
import numpy as np
p = mpimg.imread('/home/user/posterior_plot.png')
assert p.ndim in (2, 3) and p.shape[0] >= 200 and p.shape[1] >= 300
rgb = p[..., :3] if p.ndim == 3 else p[..., None]
flat = rgb.reshape(-1, rgb.shape[-1])
q = np.round(flat * 31).astype(np.uint8)
assert np.unique(q, axis=0).shape[0] > 20, 'plot has too little visual content'
assert float(np.std(rgb)) > 0.03, 'plot appears blank or nearly uniform'
'''
    run([f'{VENV}/bin/python', '-c', checker], timeout=60)


def main():
    # Preserve the original pipeline existence and executable assertion.
    assert os.path.isfile(PIPELINE), f"Pipeline script {PIPELINE} does not exist."
    st = os.stat(PIPELINE)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"Pipeline script {PIPELINE} is not executable. Please run 'chmod +x {PIPELINE}'."

    assert os.path.isfile(PLOT_SCRIPT), f"Script {PLOT_SCRIPT} is missing."
    plot_source = open(PLOT_SCRIPT).read()
    broken_sequence = "plt.show()\nplt.savefig"
    assert broken_sequence not in plot_source.replace(" ", ""), \
        f"Script {PLOT_SCRIPT} still appears to call plt.show() immediately before plt.savefig(), which clears the canvas."

    pipeline_text = open(PIPELINE, encoding='utf-8', errors='ignore').read()
    assert re.search(r'(?i)(python3?\s+-m\s+venv|virtualenv)', pipeline_text), \
        "The pipeline does not set up the requested local virtual environment."
    assert '/home/user/venv' in pipeline_text or re.search(r'\bvenv\b', pipeline_text), \
        "The pipeline does not use /home/user/venv."
    assert re.search(r'(?i)(pip3?|python3?\s+-m\s+pip).*install', pipeline_text), \
        "The pipeline does not install its dependencies."
    assert 'plot_results.py' in pipeline_text, "The pipeline does not execute plot_results.py."

    sources = pipeline_sources(pipeline_text)
    assert sources, "The pipeline does not execute a separate data-processing/Bayesian script."
    assert has_exact_sampling(sources), \
        "The executed inference source does not generate Variant A and Variant B with exactly 1,000,000 samples each."

    original_imp = open(IMP, 'rb').read()
    original_conv = open(CONV, 'rb').read()
    alternate_imp = b'''date,variant,impressions\n2024-01-02,B,700\n2024-01-01,A,700\n2024-01-01,B,800\n2024-01-02,A,900\n'''
    alternate_conv = b'''date,variant,conversions\n2024-01-01,B,32\n2024-01-02,A,50\n2024-01-02,B,40\n2024-01-01,A,40\n'''

    # A clean run proves the pipeline itself creates the venv and outputs rather
    # than relying on artifacts that happened to exist before verification.
    shutil.rmtree(VENV, ignore_errors=True)
    for path in (PROB, PLOT):
        try: os.remove(path)
        except FileNotFoundError: pass

    try:
        open(IMP, 'wb').write(alternate_imp)
        open(CONV, 'wb').write(alternate_conv)
        run([PIPELINE])

        assert os.path.isfile(f'{VENV}/pyvenv.cfg'), "The pipeline did not create /home/user/venv."
        run([f'{VENV}/bin/python', '-c',
             'import pandas, numpy, scipy, matplotlib; '
             'assert __import__("sys").prefix == "/home/user/venv"'], timeout=60)

        _, observed = read_probability()
        expected_text = run([f'{VENV}/bin/python', '-c',
            'from scipy.stats import beta; from scipy.integrate import quad; '
            'aA,bA,aB,bB=91,1511,73,1429; '
            'print(quad(lambda x: beta.pdf(x,aB,bB)*beta.cdf(x,aA,bA),0,1,epsabs=1e-11)[0])'],
            timeout=60).strip().splitlines()[-1]
        expected = float(expected_text)
        assert abs(observed - expected) <= 0.003, (
            f"Pipeline output {observed:.4f} does not match the posterior for the "
            f"altered joined data (approximately {expected:.4f})."
        )
    finally:
        open(IMP, 'wb').write(original_imp)
        open(CONV, 'wb').write(original_conv)

    # Re-run on the supplied data and retain all original final-state checks.
    for path in (PROB, PLOT):
        try: os.remove(path)
        except FileNotFoundError: pass
    run([PIPELINE])
    content, _ = read_probability()
    assert content == "0.9413", f"Expected probability in {PROB} to be '0.9413', but got '{content}'."

    check_plot()

    # Prove the repaired plotting script itself can render headlessly, not merely
    # that the pipeline copied a prebuilt PNG.
    os.remove(PLOT)
    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    run([f'{VENV}/bin/python', PLOT_SCRIPT], timeout=120, env=env)
    check_plot()


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
