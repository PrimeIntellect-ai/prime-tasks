#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import json
import os
import re
import secrets
import subprocess
import tempfile

import numpy as np


def test_setup_py_fixed():
    """Test that setup.py has been fixed to allow installation."""
    setup_path = "/app/phys_fit-1.2.0/setup.py"
    assert os.path.isfile(setup_path), f"{setup_path} is missing"

    with open(setup_path, "r") as f:
        content = f.read()

    # Preserve the original check.
    stripped = content.replace(" ", "").replace("'", "").replace('"', "")
    assert "numpyscipy" not in stripped, "setup.py still contains the missing comma bug causing 'numpyscipy'"

    # Exercise the packaging configuration and inspect the dependencies it emits.
    with tempfile.TemporaryDirectory() as egg_base:
        result = subprocess.run(
            ["/home/user/venv/bin/python", setup_path, "egg_info", "--egg-base", egg_base],
            cwd="/app/phys_fit-1.2.0",
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"setup.py cannot generate package metadata:\n{result.stderr}"
        req_files = glob.glob(os.path.join(egg_base, "*.egg-info", "requires.txt"))
        assert len(req_files) == 1, "setup.py did not emit dependency metadata"
        with open(req_files[0]) as f:
            requirements = {
                re.match(r"[A-Za-z0-9_.-]+", line.strip()).group(0).lower().replace("_", "-")
                for line in f
                if line.strip() and not line.startswith("[")
            }
        assert "numpy" in requirements, "numpy is missing from install_requires"
        assert "scipy" in requirements, "scipy is missing from install_requires"
        assert "numpyscipy" not in requirements, "numpy and scipy are still concatenated"


def test_venv_and_package_installed():
    """Test that the virtual environment exists and phys_fit is installed."""
    python_path = "/home/user/venv/bin/python"
    assert os.path.isfile(python_path), f"Virtual environment Python not found at {python_path}"
    assert os.path.isfile("/home/user/venv/pyvenv.cfg"), "The requested virtual environment was not created"

    # Preserve the original import check.
    result = subprocess.run(
        [python_path, "-c", "import phys_fit.oscillator"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Failed to import phys_fit in the venv. Did you install it?\nStderr: {result.stderr}"

    # Verify that an installed distribution, with the corrected dependency metadata,
    # is present in this venv rather than merely relying on an incidental import path.
    probe = """
import importlib.metadata as md, json, os, sys
D = md.distribution('phys_fit')
import phys_fit.oscillator as osc
print(json.dumps({'version': D.version, 'requires': D.requires or [],
                  'prefix': sys.prefix, 'oscillator': os.path.realpath(osc.__file__)}))
"""
    result = subprocess.run([python_path, "-c", probe], capture_output=True, text=True)
    assert result.returncode == 0, f"phys_fit distribution metadata is unavailable:\n{result.stderr}"
    info = json.loads(result.stdout.strip().splitlines()[-1])
    assert info["version"] == "1.2.0"
    assert os.path.realpath(info["prefix"]) == os.path.realpath("/home/user/venv")
    names = {
        re.match(r"[A-Za-z0-9_.-]+", req).group(0).lower().replace("_", "-")
        for req in info["requires"]
    }
    assert {"numpy", "scipy"}.issubset(names), f"Installed dependency metadata is incorrect: {info['requires']}"
    assert "numpyscipy" not in names


def run_classifier(python_path, script_path, input_dir, output_json, env=None):
    result = subprocess.run(
        [python_path, script_path, "--input-dir", input_dir, "--output-json", output_json],
        capture_output=True,
        text=True,
        env=env,
    )
    assert result.returncode == 0, f"classify_sims.py failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    assert os.path.isfile(output_json), "Output JSON was not created"
    with open(output_json) as f:
        return json.load(f)


def test_classify_sims_script():
    """Preserve the original corpus assertions."""
    script_path = "/home/user/classify_sims.py"
    assert os.path.isfile(script_path), f"Script missing at {script_path}"

    python_path = "/home/user/venv/bin/python"
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"
    assert os.path.isdir(clean_dir), f"Clean corpus missing at {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus missing at {evil_dir}"

    with tempfile.TemporaryDirectory() as tmpdir:
        clean_json = os.path.join(tmpdir, "clean.json")
        evil_json = os.path.join(tmpdir, "evil.json")
        clean_results = run_classifier(python_path, script_path, clean_dir, clean_json)
        evil_results = run_classifier(python_path, script_path, evil_dir, evil_json)

        clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".csv")]
        evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".csv")]
        clean_failed = [f for f in clean_files if not clean_results.get(f, False)]
        evil_failed = [f for f in evil_files if evil_results.get(f, True)]

        err_msgs = []
        if clean_failed:
            err_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
        if evil_failed:
            err_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failed)}")
        assert not err_msgs, " | ".join(err_msgs)


def trajectory_hash(t, x):
    h = hashlib.sha256()
    h.update(np.asarray(t, dtype=np.float64).tobytes())
    h.update(b"|")
    h.update(np.asarray(x, dtype=np.float64).tobytes())
    return h.hexdigest()


def test_randomized_mixed_inputs_and_required_fit_calls():
    """Use unpredictable names in one directory and verify both rules and fit calls."""
    python_path = "/home/user/venv/bin/python"
    script_path = "/home/user/classify_sims.py"

    with tempfile.TemporaryDirectory() as tmpdir:
        input_dir = os.path.join(tmpdir, "batch_" + secrets.token_hex(6))
        hook_dir = os.path.join(tmpdir, "hook")
        os.mkdir(input_dir)
        os.mkdir(hook_dir)
        marker = os.path.join(tmpdir, "fit_calls.jsonl")
        output_json = os.path.join(tmpdir, "result.json")

        rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
        t = np.linspace(0.0, 8.0, 161)
        cases = []

        # Smooth damped trajectories: low acceleration and positive fitted gamma.
        for gamma in (0.18 + rng.uniform(0.02, 0.08), 0.32 + rng.uniform(0.02, 0.08)):
            A = rng.uniform(1.2, 2.4)
            omega = rng.uniform(1.4, 2.3)
            phi = rng.uniform(-0.4, 0.4)
            x = A * np.exp(-gamma * t) * np.cos(omega * t + phi)
            cases.append((x, True))

        # An undamped/runaway trajectory whose acceleration remains far below 50.
        gamma = -rng.uniform(0.10, 0.18)
        A = rng.uniform(0.5, 0.9)
        omega = rng.uniform(1.5, 2.0)
        phi = rng.uniform(-0.3, 0.3)
        runaway = A * np.exp(-gamma * t) * np.cos(omega * t + phi)
        cases.append((runaway, False))

        # Positive damping but an unmistakable numerical acceleration glitch.
        gamma = rng.uniform(0.2, 0.35)
        glitched = 1.5 * np.exp(-gamma * t) * np.cos(1.8 * t + 0.1)
        glitched[len(t) // 2] += rng.uniform(4.0, 7.0)
        cases.append((glitched, False))

        rng.shuffle(cases)
        expected = {}
        expected_hashes = set()
        for x, valid in cases:
            name = "traj_" + secrets.token_hex(8) + ".csv"
            np.savetxt(os.path.join(input_dir, name), np.column_stack((t, x)), delimiter=",", header="t,x", comments="")
            expected[name] = valid
            expected_hashes.add(trajectory_hash(t, x))

        # Sanity-check that the generated acceleration cases have large margins.
        smooth_max = [np.max(np.abs(np.gradient(np.gradient(x, t), t))) for x, valid in cases if valid]
        invalid_spike_max = max(np.max(np.abs(np.gradient(np.gradient(x, t), t))) for x, valid in cases if not valid)
        assert max(smooth_max) < 20.0
        assert invalid_spike_max > 100.0

        # sitecustomize wraps the installed function before the submitted script
        # imports it, recording the actual t/x values supplied to every call.
        hook = r'''
import hashlib, json, os
import numpy as np
import phys_fit.oscillator as _osc
_marker = os.environ.get("PHYS_FIT_CALL_LOG")
_original = _osc.fit_damped_curve
def _wrapped(t, x):
    ta = np.asarray(t, dtype=np.float64)
    xa = np.asarray(x, dtype=np.float64)
    h = hashlib.sha256()
    h.update(ta.tobytes()); h.update(b"|"); h.update(xa.tobytes())
    result = _original(t, x)
    with open(_marker, "a") as f:
        f.write(json.dumps({"hash": h.hexdigest(), "gamma": float(result["gamma"])}) + "\n")
    return result
_osc.fit_damped_curve = _wrapped
'''
        with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
            f.write(hook)

        env = os.environ.copy()
        env["PYTHONPATH"] = hook_dir
        env["PHYS_FIT_CALL_LOG"] = marker
        actual = run_classifier(python_path, script_path, input_dir, output_json, env=env)

        assert set(actual) == set(expected), "Output must contain exactly one entry for every CSV basename"
        assert all(type(value) is bool for value in actual.values()), "Every output value must be a JSON boolean"
        assert actual == expected, f"Incorrect classifications for randomized mixed inputs: {actual}"

        assert os.path.isfile(marker), "fit_damped_curve was never called"
        with open(marker) as f:
            calls = [json.loads(line) for line in f if line.strip()]
        called_hashes = {call["hash"] for call in calls}
        assert expected_hashes.issubset(called_hashes), "fit_damped_curve was not called with every input trajectory"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
