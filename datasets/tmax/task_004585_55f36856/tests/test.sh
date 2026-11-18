#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import json
import os
import random
import subprocess
import sys
import tempfile

import numpy as np
import pytest
import scipy.stats as st


def test_fisher_package_installed():
    """Verify that the repaired vendored fisher package is installed and usable."""
    try:
        import fisher
        import fisher.cfisher as cfisher
    except ImportError as e:
        pytest.fail(f"The 'fisher' package is not installed or failed to import. Error: {e}")

    assert callable(fisher.pvalue)
    assert cfisher.__file__ is not None
    assert any(cfisher.__file__.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        "fisher.cfisher is not a compiled extension"

    setup_path = "/app/fisher-0.1.9/setup.py"
    assert os.path.isfile(setup_path), "Vendored fisher setup.py is missing"
    with open(setup_path, "r", encoding="utf-8") as f:
        assert "-O99" not in f.read(), "The invalid compiler flag was not repaired"

    for table in (
        [[1, 9], [11, 3]],
        [[8, 2], [1, 5]],
        [[0, 7], [4, 2]],
        [[20, 15], [12, 18]],
    ):
        expected = st.fisher_exact(table, alternative="two-sided").pvalue
        actual = fisher.pvalue(table[0][0], table[0][1], table[1][0], table[1][1]).two_tail
        assert actual == pytest.approx(expected, abs=1e-12)


def reference_output(data):
    cat1 = data[:, 0]
    cat2 = data[:, 1]
    table = [
        [int(np.sum((cat1 == 0) & (cat2 == 0))), int(np.sum((cat1 == 0) & (cat2 == 1)))],
        [int(np.sum((cat1 == 1) & (cat2 == 0))), int(np.sum((cat1 == 1) & (cat2 == 1)))],
    ]
    pval = st.fisher_exact(table, alternative="two-sided").pvalue

    vals = data[:, 2:5]
    centered = vals - np.mean(vals, axis=0)
    _, _, vt = np.linalg.svd(centered, full_matrices=False)
    pc1 = vt[0, :]
    if pc1[0] < 0:
        pc1 = -pc1

    val1 = data[:, 2]
    mean_val1 = np.mean(val1)
    sem_val1 = st.sem(val1, ddof=1)
    ci_lower, ci_upper = st.t.interval(
        0.95, df=len(val1) - 1, loc=mean_val1, scale=sem_val1
    )

    return json.dumps({
        "fisher_p": round(float(pval), 4),
        "pc1": [round(float(x), 4) for x in pc1],
        "val1_ci": [round(float(ci_lower), 4), round(float(ci_upper), 4)],
    })


def test_fuzz_equivalence():
    """Exercise the submitted script against independently derived results."""
    agent_path = "/home/user/process_dataset.py"
    assert os.path.isfile(agent_path), f"Agent program not found at {agent_path}"

    np.random.seed(42)
    random.seed(42)

    for i in range(100):
        num_rows = random.randint(10, 100)
        data = np.column_stack([
            np.random.choice([0, 1], size=num_rows),
            np.random.choice([0, 1], size=num_rows),
            np.random.uniform(-100.0, 100.0, size=num_rows),
            np.random.uniform(-100.0, 100.0, size=num_rows),
            np.random.uniform(-100.0, 100.0, size=num_rows),
        ])

        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write("cat1,cat2,val1,val2,val3\n")
            for row in data:
                f.write(f"{int(row[0])},{int(row[1])},{row[2]},{row[3]},{row[4]}\n")
            csv_path = f.name

        try:
            expected = reference_output(data)
            agent_res = subprocess.run(
                [sys.executable, agent_path, csv_path],
                capture_output=True,
                text=True,
                timeout=20,
            )

            if agent_res.returncode != 0:
                with open(csv_path, "r", encoding="utf-8") as f_csv:
                    csv_content = f_csv.read()
                pytest.fail(
                    f"Agent script failed on fuzz input {i + 1}/100.\n"
                    f"Input CSV:\n{csv_content}\nError output:\n{agent_res.stderr}"
                )

            actual = agent_res.stdout.strip()
            if actual != expected:
                with open(csv_path, "r", encoding="utf-8") as f_csv:
                    csv_content = f_csv.read()
                pytest.fail(
                    f"Output mismatch on fuzz input {i + 1}/100.\n"
                    f"Input CSV:\n{csv_content}\n"
                    f"Expected output: {expected}\nAgent output:    {actual}"
                )
        finally:
            os.remove(csv_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
