#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os
import stat
import pytest

RESULTS = "/app/results.json"
SIMULATOR = "/app/simulate.py"
K_DEG_TRUE = 0.284


def read_results():
    with open(RESULTS, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/app/results.json is not a valid JSON file.")


def read_gc_contents():
    gc_contents = {}
    with open("/app/sequences.fasta", "r") as f:
        seq_id = ""
        seq_data = ""
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if seq_id:
                    gc_contents[seq_id] = (seq_data.count("G") + seq_data.count("C")) / len(seq_data)
                seq_id = line[1:]
                seq_data = ""
            else:
                seq_data += line
        if seq_id:
            gc_contents[seq_id] = (seq_data.count("G") + seq_data.count("C")) / len(seq_data)
    return gc_contents


def assert_finite_number(value, name):
    assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{name} must be numeric"
    assert math.isfinite(float(value)), f"{name} must be finite"


def test_results_json_exists():
    assert os.path.isfile(RESULTS), "/app/results.json does not exist."


def test_results_json_structure():
    data = read_results()
    assert isinstance(data, dict), "results.json must contain a JSON object"
    assert "k_deg" in data, "Missing 'k_deg' in results.json"
    assert "mu" in data, "Missing 'mu' in results.json"
    assert "sigma" in data, "Missing 'sigma' in results.json"
    assert "concentrations" in data, "Missing 'concentrations' in results.json"
    assert isinstance(data["concentrations"], dict), "'concentrations' must be a dictionary"
    assert len(data["concentrations"]) == 100, f"Expected 100 concentrations, got {len(data['concentrations'])}"

    assert_finite_number(data["k_deg"], "k_deg")
    assert_finite_number(data["mu"], "mu")
    assert_finite_number(data["sigma"], "sigma")
    for sid, value in data["concentrations"].items():
        assert_finite_number(value, f"concentrations[{sid!r}]")


def test_parameters_and_distribution_fit():
    data = read_results()
    assert math.isclose(float(data["k_deg"]), K_DEG_TRUE, rel_tol=0.0, abs_tol=1e-9), \
        f"Incorrect k_deg: {data['k_deg']}"

    values = [float(v) for v in data["concentrations"].values()]
    expected_mu = sum(values) / len(values)
    expected_sigma = math.sqrt(sum((v - expected_mu) ** 2 for v in values) / len(values))

    assert math.isclose(float(data["mu"]), expected_mu, rel_tol=1e-6, abs_tol=1e-6), \
        f"mu is not the MLE mean of the reported concentrations"
    assert math.isclose(float(data["sigma"]), expected_sigma, rel_tol=1e-6, abs_tol=1e-6), \
        f"sigma is not the MLE population standard deviation of the reported concentrations"


def test_mae_metric_threshold():
    data = read_results()
    gc_contents = read_gc_contents()
    errors = []
    agent_concs = data.get("concentrations", {})

    for sid, gc in gc_contents.items():
        assert sid in agent_concs, f"Missing sequence {sid} in concentrations"
        k_syn = 5.0 * gc
        true_P = (k_syn / K_DEG_TRUE) * (1 - math.exp(-K_DEG_TRUE * 100.0))
        agent_P = float(agent_concs[sid])
        errors.append(abs(true_P - agent_P))

    mae = sum(errors) / len(errors)
    assert mae <= 0.05, f"MAE is {mae}, which is higher than the allowed threshold of 0.05"


def test_corrected_simulator_executes_accurately():
    assert os.path.exists(SIMULATOR), "/app/simulate.py does not exist"
    assert not os.path.islink(SIMULATOR), "/app/simulate.py must be a regular Python file, not a symlink"
    assert stat.S_ISREG(os.stat(SIMULATOR).st_mode), "/app/simulate.py is not a regular file"

    spec = importlib.util.spec_from_file_location("submitted_simulate", SIMULATOR)
    assert spec is not None and spec.loader is not None, "Could not load /app/simulate.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "adaptive_euler") and callable(module.adaptive_euler), \
        "simulate.py must define callable adaptive_euler"

    gc_contents = read_gc_contents()
    selected_ids = ["seq_1", "seq_37", "seq_100"]
    cases = [(5.0 * gc_contents[sid], K_DEG_TRUE) for sid in selected_ids]
    # A slower decay exposes the incorrect high-error step growth even at t_end=100.
    cases.extend((5.0 * gc_contents[sid], K_DEG_TRUE / 10.0) for sid in selected_ids)

    for k_syn, k_deg in cases:
        result = module.adaptive_euler(k_syn, k_deg, t_end=100.0)
        assert isinstance(result, (int, float)) and not isinstance(result, bool), \
            "adaptive_euler must return a numeric concentration"
        result = float(result)
        assert math.isfinite(result), "adaptive_euler returned a non-finite concentration"
        expected = (k_syn / k_deg) * (1.0 - math.exp(-k_deg * 100.0))
        assert abs(result - expected) <= 0.08, \
            f"adaptive_euler is inaccurate for k_syn={k_syn}, k_deg={k_deg}: got {result}, expected {expected}"
TEST_EOF

if timeout 120s python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
