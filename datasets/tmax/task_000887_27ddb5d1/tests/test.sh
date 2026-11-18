#!/bin/bash
set -u
mkdir -p /logs/verifier
reward=0
trap 'printf "%s\n" "$reward" > /logs/verifier/reward.txt' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import subprocess

import h5py


def generate_random_sequence(length):
    return ''.join(random.choice(['A', 'C', 'G', 'T']) for _ in range(length))


def collect_hdf5_strings(group):
    values = []
    for item in group.values():
        if isinstance(item, h5py.Group):
            values.extend(collect_hdf5_strings(item))
        elif isinstance(item, h5py.Dataset):
            for value in item[...].reshape(-1):
                if isinstance(value, bytes):
                    try:
                        value = value.decode('ascii')
                    except UnicodeDecodeError:
                        continue
                elif not isinstance(value, str):
                    continue
                values.append(value)
    return values


def test_required_artifacts_and_fuzz_equivalence():
    oracle_path = "/app/seq_evaluator"
    agent_code_path = "/home/user/evaluator.go"
    samples_path = "/home/user/samples.h5"
    notebook_path = "/home/user/analysis.ipynb"

    assert os.path.isfile(oracle_path), f"Oracle binary missing: {oracle_path}"
    assert os.path.isfile(agent_code_path), f"Agent Go code missing: {agent_code_path}"
    assert os.path.isfile(samples_path), f"HDF5 samples missing: {samples_path}"
    assert os.path.isfile(notebook_path), f"Analysis notebook missing: {notebook_path}"

    with h5py.File(samples_path, "r") as h5:
        sequences = collect_hdf5_strings(h5)
    valid_sequences = [s for s in sequences if s and set(s).issubset(set("ACGT"))]
    assert len(valid_sequences) >= 100, "samples.h5 must contain a large collection of DNA sequences"
    assert len(set(valid_sequences)) >= 10, "samples.h5 does not contain varied Monte Carlo samples"

    with open(notebook_path, "r", encoding="utf-8") as handle:
        notebook = json.load(handle)
    assert isinstance(notebook.get("cells"), list) and notebook["cells"], "Notebook has no cells"
    text = "\n".join(
        "".join(cell.get("source", [])) if isinstance(cell.get("source", []), list)
        else str(cell.get("source", ""))
        for cell in notebook["cells"]
    ).lower()
    assert "trapezoid" in text and "integration" in text, "Notebook must document the integration method"
    assert "0.5" in text, "Notebook must document endpoint weights"
    assert "-1" in text and "1.5" in text, "Notebook must document the nucleotide values"
    assert all(re.search(rf"\b{base.lower()}\b", text) for base in "ACGT"), "Notebook must discuss A/C/G/T weights"
    assert "random" in text or "monte carlo" in text, "Notebook must document the exploratory sampling process"

    sandbox = "/tmp/evaluator-sandbox"
    shutil.rmtree(sandbox, ignore_errors=True)
    os.mkdir(sandbox, 0o755)
    sandbox_binary = os.path.join(sandbox, "evaluator")
    build_env = os.environ.copy()
    build_env["CGO_ENABLED"] = "0"
    build = subprocess.run(
        ["go", "build", "-o", sandbox_binary, agent_code_path],
        capture_output=True,
        text=True,
        timeout=30,
        env=build_env,
    )
    assert build.returncode == 0, f"Failed to compile evaluator.go: {build.stderr}"
    os.chmod(sandbox_binary, 0o555)
    os.chmod(sandbox, 0o555)

    random.seed(42)
    test_sequences = [generate_random_sequence(random.randint(10, 100)) for _ in range(500)]
    expected_outputs = []
    for seq in test_sequences:
        oracle_result = subprocess.run(
            [oracle_path, seq],
            capture_output=True,
            text=True,
            check=True,
            timeout=2,
        )
        expected_outputs.append(oracle_result.stdout.strip())

    # The submitted program is executed only after the oracle has been removed,
    # and inside a read-only chroot containing no helper binaries or agent files.
    os.remove(oracle_path)

    for seq, oracle_output in zip(test_sequences, expected_outputs):
        agent_result = subprocess.run(
            ["chroot", "--userspec=65534:65534", sandbox, "/evaluator", seq],
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert agent_result.returncode == 0, (
            f"Agent program failed on input {seq}: {agent_result.stderr}"
        )
        agent_output = agent_result.stdout.strip()
        assert agent_output == oracle_output, (
            f"Output mismatch on input {seq}.\n"
            f"Oracle output: '{oracle_output}'\n"
            f"Agent output:  '{agent_output}'"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
exit 0
