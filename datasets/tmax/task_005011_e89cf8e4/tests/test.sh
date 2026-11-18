#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import shutil
import string
import subprocess
import tempfile
import pytest

SOURCE_DIR = "/app/datamash-1.8"


def generate_csv(num_lines):
    lines = []
    exp_ids = [f"exp{chr(65+i)}" for i in range(10)]
    for _ in range(num_lines):
        log_id = ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(5, 10)))
        exp_id = random.choice(exp_ids)
        inf_time = round(random.uniform(1.0, 100.0), 2)
        gt = random.choice([0, 1])
        if random.random() < 0.1:
            pred = ""
        else:
            pred = random.choice([0, 1])
        lines.append(f"{log_id},{exp_id},{inf_time},{gt},{pred}")
    return "\n".join(lines) + "\n"


def is_elf(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def test_datamash_installed():
    """Verify the perturbed vendored source was repaired, built, and installed."""
    makefile_in = os.path.join(SOURCE_DIR, "Makefile.in")
    configured_makefile = os.path.join(SOURCE_DIR, "Makefile")
    assert os.path.isfile(makefile_in), "Vendored Makefile.in is missing."
    assert os.path.isfile(configured_makefile), "Vendored source was not configured."

    with open(makefile_in, encoding="utf-8", errors="replace") as f:
        assert "CC = /bin/false" not in f.read(), "The deliberate Makefile.in perturbation was not repaired."

    installed = shutil.which("datamash")
    assert installed is not None, "datamash executable not found in PATH."
    installed = os.path.realpath(installed)

    result = subprocess.run([installed, "--version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert result.returncode == 0, f"datamash is not working correctly. Stderr: {result.stderr}"
    assert "1.8" in result.stdout, f"Expected GNU datamash 1.8, got: {result.stdout}"

    object_files = []
    built_binaries = []
    for root, _, files in os.walk(SOURCE_DIR):
        for name in files:
            path = os.path.join(root, name)
            if name.endswith(".o"):
                object_files.append(path)
            if name == "datamash" and is_elf(path):
                built_binaries.append(path)

    assert object_files, "No compiled object files were found in the vendored source tree."
    assert built_binaries, "No compiled datamash binary was found in the vendored source tree."
    assert any(filecmp.cmp(installed, candidate, shallow=False) for candidate in built_binaries), (
        "The datamash in PATH does not match the binary compiled from /app/datamash-1.8."
    )


def test_eval_tracker_fuzz_equivalence():
    """Fuzz the agent's script against the verification-only oracle."""
    agent_script = "/home/user/eval_tracker.sh"
    oracle_script = "/tests/eval_tracker_oracle.sh"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."

    random.seed(42)

    for i in range(50):
        num_lines = random.randint(10, 1000)
        csv_content = generate_csv(num_lines)

        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.csv') as tmp:
            tmp.write(csv_content)
            tmp_path = tmp.name

        try:
            oracle_proc = subprocess.run(["bash", oracle_script, tmp_path], capture_output=True, text=True)
            agent_proc = subprocess.run(["bash", agent_script, tmp_path], capture_output=True, text=True)

            assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}. Stderr: {oracle_proc.stderr}"
            assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}.\nStderr: {agent_proc.stderr}"

            assert agent_proc.stdout == oracle_proc.stdout, (
                f"Mismatch on iteration {i} (CSV lines: {num_lines}).\n"
                f"Input CSV excerpt:\n{csv_content[:300]}...\n\n"
                f"Oracle Output:\n{oracle_proc.stdout}\n"
                f"Agent Output:\n{agent_proc.stdout}"
            )
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
