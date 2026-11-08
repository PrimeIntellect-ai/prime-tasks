#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

RESULTS_FILE = "/home/user/pi_results.json"
FASTA_FILE = "/home/user/proteins.fasta"
CSV_FILE = "/home/user/experimental_pi.csv"

def compute_expected_pi(seq):
    pKa = {
        'N_term': 8.6, 'K': 10.8, 'R': 12.5, 'H': 6.5,
        'C_term': 3.6, 'D': 3.9, 'E': 4.1, 'C': 8.5, 'Y': 10.1
    }
    basic = ['N_term', 'K', 'R', 'H']
    acidic = ['C_term', 'D', 'E', 'C', 'Y']

    counts = {aa: seq.count(aa) for aa in ['K', 'R', 'H', 'D', 'E', 'C', 'Y']}
    counts['N_term'] = 1
    counts['C_term'] = 1

    def charge(pH):
        q_pos = sum([counts.get(aa, 0) / (1 + 10**(pH - pKa[aa])) for aa in basic])
        q_neg = sum([counts.get(aa, 0) / (1 + 10**(pKa[aa] - pH)) for aa in acidic])
        return q_pos - q_neg

    low, high = 0.0, 14.0
    for _ in range(100):
        mid = (low + high) / 2
        if charge(mid) > 0:
            low = mid
        else:
            high = mid
    return mid

def compute_t_statistic(calc_arr, exp_arr):
    d = [x - y for x, y in zip(calc_arr, exp_arr)]
    n = len(d)
    mean_d = sum(d) / n
    var_d = sum((x - mean_d)**2 for x in d) / (n - 1)
    t = mean_d / math.sqrt(var_d / n)
    return t

@pytest.fixture
def results_data():
    assert os.path.isfile(RESULTS_FILE), f"Results file missing at {RESULTS_FILE}"
    with open(RESULTS_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_FILE} is not a valid JSON.")
    return data

def test_json_structure(results_data):
    expected_keys = {"calculated_pis", "t_statistic", "p_value"}
    assert set(results_data.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}"
    assert isinstance(results_data["calculated_pis"], dict), "'calculated_pis' should be a dictionary"
    assert isinstance(results_data["t_statistic"], (int, float)), "'t_statistic' should be a number"
    assert isinstance(results_data["p_value"], (int, float)), "'p_value' should be a number"

def test_calculated_pis(results_data):
    seqs = {
        "PROT_A": "MKTVEEDC",
        "PROT_B": "RRYHHCYY",
        "PROT_C": "DDDDEEEE",
        "PROT_D": "KRKRHHH",
        "PROT_E": "MADQLTEEQIAEFKEAFSLFDKDGDGTITTKELGTVMRSL"
    }

    calc_pis = results_data["calculated_pis"]
    assert set(calc_pis.keys()) == set(seqs.keys()), "Protein IDs in 'calculated_pis' do not match the FASTA sequences."

    for prot_id, seq in seqs.items():
        expected_pi = round(compute_expected_pi(seq), 2)
        actual_pi = calc_pis[prot_id]
        assert actual_pi == expected_pi, f"Calculated pI for {prot_id} is {actual_pi}, expected {expected_pi}"

def test_statistics(results_data):
    seqs = {
        "PROT_A": "MKTVEEDC",
        "PROT_B": "RRYHHCYY",
        "PROT_C": "DDDDEEEE",
        "PROT_D": "KRKRHHH",
        "PROT_E": "MADQLTEEQIAEFKEAFSLFDKDGDGTITTKELGTVMRSL"
    }
    exp_pis = {
        "PROT_A": 4.25,
        "PROT_B": 8.50,
        "PROT_C": 3.10,
        "PROT_D": 11.20,
        "PROT_E": 4.50
    }

    ids = sorted(list(seqs.keys()))
    calc_arr = [compute_expected_pi(seqs[i]) for i in ids]
    exp_arr = [exp_pis[i] for i in ids]

    expected_t = round(compute_t_statistic(calc_arr, exp_arr), 4)
    actual_t = results_data["t_statistic"]

    assert actual_t == expected_t, f"t_statistic is {actual_t}, expected {expected_t}"

    # Check p_value (since we don't calculate CDF in stdlib, we check against the known truth for these exact inputs)
    expected_p = 0.4665
    actual_p = results_data["p_value"]
    assert actual_p == expected_p, f"p_value is {actual_p}, expected {expected_p}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
