#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess

import nbformat
import numpy as np
from scipy import stats
from scipy.integrate import quad

EXECUTED_NB = "/home/user/bfactor_workflow_executed.ipynb"
SOURCE_NB = "/home/user/bfactor_workflow.ipynb"
RESULTS = "/home/user/results.txt"
PDB = "/home/user/protein.pdb"


def expected_ca_values_and_integral():
    values = []
    with open(PDB, "r") as f:
        for line in f:
            if line.startswith("ATOM") and line[12:16].strip() == "CA":
                values.append(float(line[60:66].strip()))
    values = np.asarray(values)
    assert len(values) > 1, "Reference PDB did not contain enough CA atoms."
    expected_kde = stats.gaussian_kde(values, bw_method="scott")
    expected_integral, _ = quad(expected_kde.evaluate, 10.0, 50.0, limit=50)
    return values, float(expected_integral)


def test_executed_notebook_exists_and_fixed():
    assert os.path.exists(EXECUTED_NB), f"Executed notebook not found at {EXECUTED_NB}"

    with open(EXECUTED_NB, "r") as f:
        try:
            nb_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{EXECUTED_NB} is not a valid JSON file."

    assert "cells" in nb_data, "Executed notebook does not contain 'cells'."

    # Preserve the original source assertions.
    found_scott = False
    found_ca_filter = False
    code_cells = []
    for cell in nb_data["cells"]:
        if cell.get("cell_type") == "code":
            code_cells.append(cell)
            source = "".join(cell.get("source", []))
            if "bw_method='scott'" in source.replace('"', "'"):
                found_scott = True
            if "atom_name == 'CA'" in source.replace('"', "'"):
                found_ca_filter = True

    assert found_scott, "The KDE bandwidth method was not changed to 'scott' in the notebook."
    assert found_ca_filter, "The filtering for 'CA' atoms was lost or altered."

    # Confirm this is a genuinely executed papermill artifact, not source-only JSON.
    assert code_cells, "Executed notebook contains no code cells."
    assert all(cell.get("execution_count") is not None for cell in code_cells), \
        "One or more code cells in the executed notebook were not executed."
    papermill_metadata = nb_data.get("metadata", {}).get("papermill")
    assert isinstance(papermill_metadata, dict), \
        "Executed notebook does not contain papermill execution metadata."
    assert not papermill_metadata.get("exception"), \
        "Papermill metadata reports that notebook execution failed."


def test_results_file_and_value():
    assert os.path.exists(SOURCE_NB), f"Source notebook not found at {SOURCE_NB}"

    expected_values, expected_integral = expected_ca_values_and_integral()

    # Add a verifier-only final cell which inspects the state produced by the
    # submitted workflow. Papermill then executes the complete submitted notebook.
    nb = nbformat.read(SOURCE_NB, as_version=4)
    validation_source = f'''\nimport numpy as _verifier_np\nassert "b_factors" in globals(), "Workflow did not produce b_factors"\nassert "kde" in globals(), "Workflow did not produce kde"\n_verifier_expected = _verifier_np.array({expected_values.tolist()!r}, dtype=float)\n_verifier_actual = _verifier_np.asarray(b_factors, dtype=float)\nassert _verifier_actual.shape == _verifier_expected.shape, "Incorrect number of CA B-factors"\nassert _verifier_np.allclose(_verifier_actual, _verifier_expected, rtol=0, atol=1e-12), "b_factors were not extracted only from CA atoms"\nassert hasattr(kde, "dataset") and _verifier_np.allclose(_verifier_np.sort(_verifier_np.ravel(kde.dataset)), _verifier_np.sort(_verifier_expected), rtol=0, atol=1e-12), "KDE was not fitted to the extracted CA B-factors"\nassert _verifier_np.isclose(float(kde.factor), float(kde.scotts_factor()), rtol=1e-12, atol=1e-12), "KDE does not use Scott's bandwidth"\n'''
    nb.cells.append(nbformat.v4.new_code_cell(validation_source))
    verifier_input = "/tmp/verifier_bfactor_input.ipynb"
    verifier_output = "/tmp/verifier_bfactor_executed.ipynb"
    nbformat.write(nb, verifier_input)

    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    completed = subprocess.run(
        ["papermill", verifier_input, verifier_output, "-k", "python3"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert completed.returncode == 0, \
        f"Papermill could not execute the fixed workflow:\n{completed.stdout}"
    assert os.path.exists(verifier_output), "Papermill did not create an executed verifier notebook."
    assert os.path.exists(RESULTS), f"Results file not found at {RESULTS} after notebook execution"

    with open(RESULTS, "r") as f:
        content = f.read().strip()

    # Preserve the original format and broad-range assertions.
    match = re.search(r"Integral:\s*([0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)", content)
    assert match is not None, \
        f"Results file does not contain a valid 'Integral: <value>' string. Content: {content}"
    integral_val = float(match.group(1))
    assert 0.9 < integral_val <= 1.0, \
        f"Calculated integral {integral_val} is out of expected bounds (0.9, 1.0]. The KDE fix might not be applied correctly."

    assert np.isclose(integral_val, expected_integral, rtol=1e-9, atol=1e-10), \
        f"Integral {integral_val} does not match the independently calculated Scott-KDE integral {expected_integral}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
