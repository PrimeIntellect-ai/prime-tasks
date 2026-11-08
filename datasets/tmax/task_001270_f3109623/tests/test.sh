#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import stat
import subprocess
import time

import pytest

SCRIPT = "/home/user/orchestrate.sh"
FASTA = "/home/user/data/input.fasta"
PDB = "/home/user/data/structure.pdb"
TEMPLATE = "/home/user/templates/report.ipynb"
PI_FILE = "/home/user/data/pi_estimate.txt"
REPORT = "/home/user/data/final_report.ipynb"


def run_script():
    result = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


def read_pi():
    assert os.path.isfile(PI_FILE), f"File {PI_FILE} was not created."
    content = open(PI_FILE).read().strip()
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"Could not parse pi estimate as float: {content}")
    assert 3.0 <= value <= 3.3, f"Pi estimate {value} is not within expected range for Pi (3.0 - 3.3)."
    return content, value


def read_report():
    assert os.path.isfile(REPORT), f"File {REPORT} was not created."
    try:
        with open(REPORT) as handle:
            return json.load(handle)
    except json.JSONDecodeError:
        pytest.fail(f"File {REPORT} is not a valid JSON/Jupyter Notebook.")


def injected_parameters(nb):
    result = {}
    for cell in nb.get("cells", []):
        if "injected-parameters" not in cell.get("metadata", {}).get("tags", []):
            continue
        source = "".join(cell.get("source", []))
        for line in source.splitlines():
            if "=" in line and not line.strip().startswith("#"):
                key, value = line.split("=", 1)
                result[key.strip()] = value.strip()
    return result


def stream_output(nb):
    pieces = []
    for cell in nb.get("cells", []):
        for output in cell.get("outputs", []):
            text = output.get("text", "")
            pieces.append("".join(text) if isinstance(text, list) else str(text))
    return "".join(pieces)


def write_challenge_inputs(n, ca_count, token):
    fasta_lines = ["not-a-header", " >indented-decoy"]
    for i in range(n):
        fasta_lines.extend([f">challenge_{i}", "ACDEFGHIKLMNPQRSTVWY"])
    with open(FASTA, "w") as handle:
        handle.write("\n".join(fasta_lines) + "\n")

    lines = []
    serial = 1
    for residue in range(1, ca_count + 1):
        lines.append(f"ATOM  {serial:5d}  CA  ALA A{residue:4d}      10.000  11.000  12.000  1.00  0.00           C  ")
        serial += 1
        lines.append(f"ATOM  {serial:5d}  CB  ALA A{residue:4d}      10.000  11.000  12.000  1.00  0.00           C  ")
        serial += 1
    lines.extend([
        f"HETATM{serial:5d}  CA  CAL A 999      10.000  11.000  12.000  1.00  0.00          CA  ",
        f"ATOM  {serial + 1:5d} CAX  ALA A 998      10.000  11.000  12.000  1.00  0.00           C  ",
        "REMARK CA is not an ATOM record",
    ])
    with open(PDB, "w") as handle:
        handle.write("\n".join(lines) + "\n")

    notebook = {
        "cells": [
            {
                "cell_type": "code",
                "execution_count": None,
                "metadata": {"tags": ["parameters"]},
                "outputs": [],
                "source": ["ca_count = 0\n", "pi_estimate = 0.0"],
            },
            {
                "cell_type": "code",
                "execution_count": None,
                "metadata": {},
                "outputs": [],
                "source": [
                    f"print('verification-token:{token}')\n",
                    "print(f'CA Count: {ca_count}')\n",
                    "print(f'Pi Estimate: {pi_estimate}')",
                ],
            },
        ],
        "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python", "version": "3"},
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }
    with open(TEMPLATE, "w") as handle:
        json.dump(notebook, handle)


def test_complete_pipeline():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    mode = os.stat(SCRIPT).st_mode
    assert bool(mode & stat.S_IXUSR), f"Script {SCRIPT} is not executable."

    source = open(SCRIPT).read()
    active_source = "\n".join(line.split("#", 1)[0] for line in source.splitlines())
    assert "10000" in active_source, "The script does not specify the required 10000 iterations per sequence."
    assert "*" in active_source, "The script does not multiply the sequence count by 10000."

    # Preserve the original checks against the image's supplied inputs.
    run_script()
    _, original_pi = read_pi()
    original_nb = read_report()
    original_params = injected_parameters(original_nb)
    assert "ca_count" in original_params, "ca_count parameter not found in the injected parameters cell."
    assert original_params["ca_count"] == "2", f"Expected ca_count=2 based on the PDB file, got {original_params['ca_count']}."
    assert "pi_estimate" in original_params, "pi_estimate parameter not found in the injected parameters cell."
    try:
        original_injected_pi = float(original_params["pi_estimate"])
    except ValueError:
        pytest.fail(f"Could not parse injected pi_estimate as float: {original_params['pi_estimate']}")
    assert 3.0 <= original_injected_pi <= 3.3, f"Injected pi_estimate {original_injected_pi} is not within expected range."
    assert abs(original_injected_pi - original_pi) < 1e-12, "Notebook did not receive the Pi value written by the script."

    # Replace all inputs with unpredictable values and execute the artifact again.
    n = random.SystemRandom().randint(4, 9)
    ca_count = random.SystemRandom().randint(3, 8)
    token = secrets.token_hex(12)
    write_challenge_inputs(n, ca_count, token)

    estimates = []
    for attempt in range(3):
        run_script()
        pi_text, pi_value = read_pi()
        estimates.append(pi_text)

        nb = read_report()
        params = injected_parameters(nb)
        assert "ca_count" in params, "ca_count parameter not found in the injected parameters cell."
        assert params["ca_count"] == str(ca_count), (
            f"Expected ca_count={ca_count} for the challenge PDB, got {params['ca_count']}."
        )
        assert "pi_estimate" in params, "pi_estimate parameter not found in the injected parameters cell."
        try:
            injected_pi = float(params["pi_estimate"])
        except ValueError:
            pytest.fail(f"Could not parse injected pi_estimate as float: {params['pi_estimate']}")
        assert abs(injected_pi - pi_value) < 1e-12, "Notebook pi_estimate differs from pi_estimate.txt."

        papermill_metadata = nb.get("metadata", {}).get("papermill", {})
        assert papermill_metadata.get("status") == "completed", "The report does not show a completed papermill execution."
        output = stream_output(nb)
        assert f"verification-token:{token}" in output, "The challenge notebook's output cell was not executed."
        assert f"CA Count: {ca_count}" in output, "Executed notebook output contains the wrong CA count."
        match = re.search(r"Pi Estimate:\s*([-+0-9.eE]+)", output)
        assert match, "Executed notebook output does not contain the Pi estimate."
        assert abs(float(match.group(1)) - pi_value) < 1e-12, "Executed notebook output contains the wrong Pi estimate."

        if attempt < 2:
            time.sleep(1.1)

    assert len(set(estimates)) >= 2, "Repeated runs produced an identical fixed Pi value instead of Monte Carlo samples."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
