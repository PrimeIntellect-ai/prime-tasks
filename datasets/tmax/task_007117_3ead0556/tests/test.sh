#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_mcmc_traced.py
import json
import os
import runpy
import sys
import numpy as np

trace_path = os.environ["MCMC_TRACE_PATH"]
script_path = sys.argv[1]
trace = {
    "seed_calls": [],
    "normal_calls": 0,
    "normal_bad_scale": 0,
    "normal_sized_calls": 0,
    "rand_calls": 0,
}

_original_seed = np.random.seed
_original_normal = np.random.normal
_original_rand = np.random.rand

def traced_seed(*args, **kwargs):
    if args:
        try:
            trace["seed_calls"].append(int(args[0]))
        except Exception:
            trace["seed_calls"].append(repr(args[0]))
    elif "seed" in kwargs:
        try:
            trace["seed_calls"].append(int(kwargs["seed"]))
        except Exception:
            trace["seed_calls"].append(repr(kwargs["seed"]))
    else:
        trace["seed_calls"].append(None)
    return _original_seed(*args, **kwargs)

def traced_normal(*args, **kwargs):
    trace["normal_calls"] += 1
    if len(args) >= 2:
        scale = args[1]
    else:
        scale = kwargs.get("scale", 1.0)
    try:
        if abs(float(scale) - 0.05) > 1e-12:
            trace["normal_bad_scale"] += 1
    except Exception:
        trace["normal_bad_scale"] += 1

    size = args[2] if len(args) >= 3 else kwargs.get("size", None)
    if size is not None:
        trace["normal_sized_calls"] += 1
    return _original_normal(*args, **kwargs)

def traced_rand(*args, **kwargs):
    trace["rand_calls"] += 1
    return _original_rand(*args, **kwargs)

np.random.seed = traced_seed
np.random.normal = traced_normal
np.random.rand = traced_rand

try:
    runpy.run_path(script_path, run_name="__main__")
finally:
    with open(trace_path, "w") as f:
        json.dump(trace, f)
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import secrets
import subprocess

import numpy as np
import pytest

SCRIPT_PATH = "/home/user/mcmc.py"
OUTPUT_PATH = "/home/user/mcmc_gc_mean.txt"
FASTA_PATH = "/home/user/sequences.fasta"
RUNNER_PATH = "/tmp/run_mcmc_traced.py"


def test_mcmc_py_exists():
    """Check if the mcmc.py script was created."""
    script_path = "/home/user/mcmc.py"
    assert os.path.exists(script_path), f"The script {script_path} is missing."
    assert os.path.isfile(script_path), f"The path {script_path} is not a regular file."


def test_mcmc_gc_mean_txt():
    """Check if mcmc_gc_mean.txt exists and contains a valid mean within the expected range."""
    output_path = "/home/user/mcmc_gc_mean.txt"
    assert os.path.exists(output_path), f"The output file {output_path} is missing."
    assert os.path.isfile(output_path), f"The path {output_path} is not a regular file."

    with open(output_path, "r") as f:
        content = f.read().strip()

    assert content, f"The file {output_path} is empty."

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"The content of {output_path} ('{content}') cannot be parsed as a float.")

    assert 0.540 <= val <= 0.555, f"The estimated mean {val} is outside the acceptable range [0.540, 0.555]."


def parse_target(data):
    name = None
    records = {}
    for raw_line in data.decode("ascii").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith(">"):
            name = line[1:].split()[0]
            records.setdefault(name, [])
        else:
            assert name is not None
            records[name].append(line)
    assert "target_gene" in records
    return "".join(records["target_gene"])


def reference_mean(n, k):
    np.random.seed(42)
    theta = 0.5
    samples = []

    def log_posterior(value):
        return (k + 1) * math.log(value) + (n - k + 1) * math.log(1.0 - value)

    for _ in range(10000):
        proposal = np.random.normal(theta, 0.05)
        if 0.0 < proposal < 1.0:
            log_acceptance = log_posterior(proposal) - log_posterior(theta)
            if math.log(np.random.rand()) < log_acceptance:
                theta = proposal
        samples.append(theta)

    return round(float(np.mean(samples[1000:])), 3)


def run_submission(expected):
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    trace_path = f"/tmp/mcmc_trace_{secrets.token_hex(8)}.json"
    env = os.environ.copy()
    env["MCMC_TRACE_PATH"] = trace_path
    try:
        result = subprocess.run(
            ["python3", RUNNER_PATH, SCRIPT_PATH],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            "mcmc.py failed when executed:\n"
            + result.stdout
            + "\n"
            + result.stderr
        )
        assert os.path.isfile(OUTPUT_PATH), "Running mcmc.py did not create mcmc_gc_mean.txt."
        content = open(OUTPUT_PATH, "r").read().strip()
        assert content, "Running mcmc.py created an empty output file."
        try:
            actual = float(content)
        except ValueError:
            pytest.fail(f"Running mcmc.py produced a non-numeric value: {content!r}")
        assert math.isfinite(actual)
        assert abs(actual - expected) < 1e-12, (
            f"mcmc.py produced {actual}, but the specified seeded sampler produces {expected}."
        )

        assert os.path.isfile(trace_path), "Execution trace was not produced."
        with open(trace_path, "r") as f:
            trace = json.load(f)
        assert trace["seed_calls"] == [42], "The script must seed NumPy exactly once with numpy.random.seed(42)."
        assert trace["normal_calls"] == 10000, "The script must perform exactly 10,000 proposal steps."
        assert trace["normal_bad_scale"] == 0, "Every proposal must use standard deviation 0.05."
        assert trace["normal_sized_calls"] == 0, "Each proposal must be drawn from the current scalar state."
        assert trace["rand_calls"] > 0, "The script must use numpy.random.rand for acceptance decisions."
    finally:
        if os.path.exists(trace_path):
            os.remove(trace_path)


def make_fasta(n, k):
    bases = ["G" if i % 2 == 0 else "C" for i in range(k)]
    bases += ["A" if i % 2 == 0 else "T" for i in range(n - k)]
    random.SystemRandom().shuffle(bases)
    sequence = "".join(bases)
    wrapped = "\n".join(sequence[i:i + 13] for i in range(0, len(sequence), 13))
    return (
        ">decoy_target_gene\nGGGGCCCCAAAA\n"
        ">target_gene test record\n" + wrapped + "\n"
        ">other\nATATGCGC\n"
    ).encode("ascii")


def test_script_executes_and_implements_required_sampler():
    with open(FASTA_PATH, "rb") as f:
        original_fasta = f.read()

    original_sequence = parse_target(original_fasta).upper()
    original_expected = reference_mean(
        len(original_sequence),
        original_sequence.count("G") + original_sequence.count("C"),
    )

    try:
        run_submission(original_expected)

        # Additional records prevent a stale or hard-coded answer from passing and
        # exercise exact target-record parsing over multiline FASTA input.
        for n, k in ((47, 17), (83, 49), (131, 91)):
            challenge = make_fasta(n, k)
            with open(FASTA_PATH, "wb") as f:
                f.write(challenge)
            run_submission(reference_mean(n, k))
    finally:
        with open(FASTA_PATH, "wb") as f:
            f.write(original_fasta)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
