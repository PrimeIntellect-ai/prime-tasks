#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shutil
import stat
import subprocess
import tempfile

import numpy as np
import pytest

PROJECT = "/home/user/sim_project"
MAIN_RS = os.path.join(PROJECT, "src/main.rs")
RESULTS = "/home/user/results.csv"
BOOTSTRAP = "/home/user/bootstrap.py"
CI_FILE = "/home/user/bootstrap_ci.txt"
RELEASE_BIN = os.path.join(PROJECT, "target/release/sim_project")


def solve_ode(y0):
    y = float(y0)
    dt = 0.1
    for _ in range(100):
        y += -0.1 * y * dt
    return y


def assert_simulation_output(text):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    assert len(lines) == 5000, f"Expected exactly 5000 results, found {len(lines)}."
    for i, line in enumerate(lines):
        try:
            actual = float(line)
        except ValueError:
            pytest.fail(f"Could not parse line {i + 1} as float: {line}")
        expected = solve_ode(i)
        assert math.isclose(actual, expected, rel_tol=1e-5), \
            f"Value mismatch at line {i + 1}. Expected approx {expected}, got {actual}. Ensure deterministic ordering."


def run_binary(path):
    env = os.environ.copy()
    env["RAYON_NUM_THREADS"] = "8"
    proc = subprocess.run([path], cwd=PROJECT, env=env, capture_output=True,
                          text=True, timeout=60, check=True)
    assert proc.stderr == "", f"Simulation wrote unexpected stderr: {proc.stderr}"
    return proc.stdout


def expected_ci(values):
    np.random.seed(42)
    boot_means = []
    for _ in range(1000):
        sample = np.random.choice(values, size=len(values), replace=True)
        boot_means.append(np.mean(sample))
    lower = np.percentile(boot_means, 2.5)
    upper = np.percentile(boot_means, 97.5)
    return f"95% CI: [{lower:.4f}, {upper:.4f}]"


def test_rust_code_modified():
    assert os.path.isfile(MAIN_RS), f"The file {MAIN_RS} is missing."
    with open(MAIN_RS, "r") as f:
        content = f.read()
    assert "rayon" in content, "The Rust code must still use the 'rayon' crate."
    assert "par_iter" in content or "par_bridge" in content or "spawn" in content, \
        "The Rust code must still use parallelization."


def test_release_binary_was_built_and_generated_results():
    assert os.path.isfile(RELEASE_BIN), "The optimized release binary is missing."
    assert os.stat(RELEASE_BIN).st_mode & stat.S_IXUSR, "The release artifact is not executable."
    with open(RELEASE_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The release artifact is not a compiled ELF executable."

    assert os.path.isfile(RESULTS), f"The file {RESULTS} is missing."
    with open(RESULTS, "r") as f:
        saved_results = f.read()

    outputs = [run_binary(RELEASE_BIN) for _ in range(3)]
    assert outputs[0] == outputs[1] == outputs[2], \
        "The release simulation output is not reproducible across parallel runs."
    assert saved_results == outputs[0], \
        "results.csv is not the output produced by the optimized release binary."
    assert_simulation_output(outputs[0])


def test_current_source_builds_and_runs_deterministically_in_release_mode():
    target_dir = tempfile.mkdtemp(prefix="sim-release-")
    try:
        env = os.environ.copy()
        env.update({
            "PATH": "/home/user/.cargo/bin:" + env.get("PATH", ""),
            "CARGO_HOME": "/home/user/.cargo",
            "RUSTUP_HOME": "/home/user/.rustup",
            "CARGO_TARGET_DIR": target_dir,
        })
        subprocess.run(["/home/user/.cargo/bin/cargo", "build", "--release"],
                       cwd=PROJECT, env=env, capture_output=True, text=True,
                       timeout=240, check=True)
        binary = os.path.join(target_dir, "release/sim_project")
        assert os.path.isfile(binary)
        env["RAYON_NUM_THREADS"] = "8"
        outputs = []
        for _ in range(3):
            proc = subprocess.run([binary], cwd=PROJECT, env=env,
                                  capture_output=True, text=True, timeout=60, check=True)
            outputs.append(proc.stdout)
        assert outputs[0] == outputs[1] == outputs[2], \
            "A fresh release build does not produce deterministic output."
        assert_simulation_output(outputs[0])
    finally:
        shutil.rmtree(target_dir, ignore_errors=True)


def test_results_csv_correct():
    assert os.path.isfile(RESULTS), f"The file {RESULTS} is missing."
    with open(RESULTS, "r") as f:
        text = f.read()
    assert_simulation_output(text)


def test_bootstrap_script_exists():
    assert os.path.isfile(BOOTSTRAP), f"The file {BOOTSTRAP} is missing."


def test_bootstrap_ci_txt_correct():
    assert os.path.isfile(CI_FILE), f"The file {CI_FILE} is missing."
    with open(CI_FILE, "r") as f:
        actual_content = f.read().strip()
    values = np.array([solve_ode(i) for i in range(5000)])
    assert actual_content == expected_ci(values), \
        f"The content of {CI_FILE} does not match the expected format or value."


def test_bootstrap_script_executes_and_implements_required_sampling():
    # Use a verifier-generated input so a script that merely leaves a precomputed
    # bootstrap_ci.txt in place cannot pass.
    original_results = open(RESULTS, "rb").read() if os.path.exists(RESULTS) else None
    original_ci = open(CI_FILE, "rb").read() if os.path.exists(CI_FILE) else None
    trace_dir = tempfile.mkdtemp(prefix="np-trace-")
    trace_path = os.path.join(trace_dir, "trace.jsonl")
    sitecustomize = r'''
import json, os
import numpy as np
_p = os.environ["NP_TRACE_PATH"]
_seed = np.random.seed
_choice = np.random.choice
_percentile = np.percentile

def log(obj):
    with open(_p, "a") as f:
        f.write(json.dumps(obj) + "\\n")

def seed(*args, **kwargs):
    log({"call":"seed", "args":list(args), "kwargs":kwargs})
    return _seed(*args, **kwargs)

def choice(*args, **kwargs):
    size = kwargs.get("size", args[1] if len(args) > 1 else None)
    explicit = "replace" in kwargs or len(args) > 2
    replace = kwargs.get("replace", args[2] if len(args) > 2 else True)
    if isinstance(size, tuple): size = list(size)
    log({"call":"choice", "size":size, "replace":bool(replace), "explicit_replace":explicit})
    return _choice(*args, **kwargs)

def percentile(*args, **kwargs):
    q = kwargs.get("q", args[1] if len(args) > 1 else None)
    try: q = np.asarray(q).tolist()
    except Exception: pass
    custom_method = "method" in kwargs or "interpolation" in kwargs or len(args) > 5
    log({"call":"percentile", "q":q, "custom_method":custom_method})
    return _percentile(*args, **kwargs)

np.random.seed = seed
np.random.choice = choice
np.percentile = percentile
'''
    with open(os.path.join(trace_dir, "sitecustomize.py"), "w") as f:
        f.write(sitecustomize)

    # Exactly 5000 nontrivial values prevents assumptions about the ODE sequence.
    controlled = np.array([math.sin(i * 0.017) * 700.0 + (i % 37) * 0.125
                           for i in range(5000)], dtype=float)
    try:
        np.savetxt(RESULTS, controlled, fmt="%.17g")
        controlled = np.loadtxt(RESULTS)
        if os.path.exists(CI_FILE):
            os.remove(CI_FILE)
        env = os.environ.copy()
        env["NP_TRACE_PATH"] = trace_path
        env["PYTHONPATH"] = trace_dir + os.pathsep + env.get("PYTHONPATH", "")
        proc = subprocess.run(["python3", BOOTSTRAP], cwd="/home/user", env=env,
                              capture_output=True, text=True, timeout=120)
        assert proc.returncode == 0, f"bootstrap.py failed when executed: {proc.stderr}"
        assert os.path.isfile(CI_FILE), "bootstrap.py did not create bootstrap_ci.txt."
        with open(CI_FILE, "r") as f:
            actual = f.read().strip()
        assert actual == expected_ci(controlled), \
            "bootstrap.py did not compute the required CI for its input data."

        assert os.path.isfile(trace_path), "bootstrap.py did not use the required NumPy APIs."
        with open(trace_path) as f:
            calls = [json.loads(line) for line in f if line.strip()]
        seeds = [c for c in calls if c.get("call") == "seed"]
        choices = [c for c in calls if c.get("call") == "choice"]
        percentiles = [c for c in calls if c.get("call") == "percentile"]
        assert seeds and seeds[0]["args"] == [42], "bootstrap.py must call numpy.random.seed(42)."
        assert choices, "bootstrap.py must draw samples with numpy.random.choice."
        assert all(c["replace"] and c["explicit_replace"] for c in choices), \
            "Every bootstrap draw must explicitly use replace=True."

        drawn_samples = 0
        for c in choices:
            size = c["size"]
            if isinstance(size, list):
                count = math.prod(size)
            elif isinstance(size, int):
                count = size
            else:
                pytest.fail("numpy.random.choice must specify the bootstrap sample size.")
            assert count % len(controlled) == 0
            drawn_samples += count // len(controlled)
        assert drawn_samples == 1000, f"Expected exactly 1000 bootstrap samples, got {drawn_samples}."

        qs = []
        for c in percentiles:
            assert not c["custom_method"], "numpy.percentile must use its default interpolation."
            q = c["q"]
            qs.extend(q if isinstance(q, list) else [q])
        assert 2.5 in qs and 97.5 in qs, \
            "bootstrap.py must use numpy.percentile at 2.5 and 97.5."
    finally:
        if original_results is None:
            if os.path.exists(RESULTS): os.remove(RESULTS)
        else:
            with open(RESULTS, "wb") as f: f.write(original_results)
        if original_ci is None:
            if os.path.exists(CI_FILE): os.remove(CI_FILE)
        else:
            with open(CI_FILE, "wb") as f: f.write(original_ci)
        shutil.rmtree(trace_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
