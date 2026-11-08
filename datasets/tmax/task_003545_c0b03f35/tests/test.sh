#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import runpy
import subprocess
import tempfile
from unittest import mock

import pytest
import setuptools


def test_seq_affinity_installed():
    try:
        import seq_affinity
    except ImportError as e:
        pytest.fail(f"seq_affinity package is not installed or importable. Error: {e}")


def test_setup_has_openmp_flags():
    package_dir = "/app/seq_affinity-0.2.1"
    setup_path = os.path.join(package_dir, "setup.py")
    assert os.path.isfile(setup_path), f"setup.py missing at {setup_path}"

    captured = {}

    def capture_setup(*args, **kwargs):
        captured["kwargs"] = kwargs

    old_cwd = os.getcwd()
    try:
        os.chdir(package_dir)
        with mock.patch.object(setuptools, "setup", capture_setup):
            runpy.run_path(setup_path, run_name="__main__")
    finally:
        os.chdir(old_cwd)

    assert "kwargs" in captured, "setup.py did not call setuptools.setup()"
    extensions = captured["kwargs"].get("ext_modules", [])
    matching = [ext for ext in extensions if getattr(ext, "name", None) == "seq_affinity"]
    assert matching, "setup.py does not define the seq_affinity extension"

    extension = matching[0]
    compile_args = extension.extra_compile_args or []
    link_args = extension.extra_link_args or []
    assert "-fopenmp" in compile_args, "seq_affinity is missing -fopenmp in extra_compile_args"
    assert "-fopenmp" in link_args, "seq_affinity is missing -fopenmp in extra_link_args"


def test_fuzz_equivalence():
    agent_script = "/home/user/analyze.py"
    oracle_script = "/tests/oracle_analyze.py"

    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing at {oracle_script}"

    random.seed(42)
    num_iterations = 20

    for i in range(num_iterations):
        num_seqs = random.randint(50, 200)
        seqs = []
        for _ in range(num_seqs):
            length = random.randint(20, 50)
            seq = "".join(random.choices(["A", "C", "G", "T"], k=length))
            seqs.append(seq)

        with tempfile.NamedTemporaryFile(mode="w", delete=False) as f:
            f.write("\n".join(seqs) + "\n")
            input_path = f.name

        try:
            oracle_res = subprocess.run(
                ["python3", oracle_script, input_path],
                capture_output=True, text=True
            )
            assert oracle_res.returncode == 0, f"Oracle script failed on fuzz input {i}:\n{oracle_res.stderr}"

            agent_res = subprocess.run(
                ["python3", agent_script, input_path],
                capture_output=True, text=True
            )
            assert agent_res.returncode == 0, f"Agent script failed on fuzz input {i}:\n{agent_res.stderr}"

            oracle_out = oracle_res.stdout.strip()
            agent_out = agent_res.stdout.strip()

            assert agent_out == oracle_out, (
                f"Output mismatch on fuzz input {i}.\n"
                f"Input details: {num_seqs} sequences.\n"
                f"Oracle output: {oracle_out}\n"
                f"Agent output:  {agent_out}"
            )
        finally:
            os.remove(input_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
