#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import string
import subprocess
import tempfile


def generate_random_csv(path):
    """Generate a random CSV file according to the fuzz input distribution."""
    num_rows = random.randint(20, 100)
    with open(path, 'w') as f:
        for _ in range(num_rows):
            id_len = random.randint(5, 10)
            row_id = ''.join(random.choices(string.ascii_letters + string.digits, k=id_len))

            dim = random.randint(5, 10)
            vec_a = ':'.join(f"{random.uniform(-1.0, 1.0):.6f}" for _ in range(dim))
            vec_b = ':'.join(f"{random.uniform(-1.0, 1.0):.6f}" for _ in range(dim))

            f.write(f"{row_id},{vec_a},{vec_b}\n")


def expected_pipeline_output(path):
    """Derive the required output independently from the submitted artifacts."""
    output = []
    with open(path, 'r') as f:
        for line in f:
            row_id, vec_a_text, vec_b_text = line.rstrip('\n').split(',')
            vec_a = [float(value) for value in vec_a_text.split(':')]
            vec_b = [float(value) for value in vec_b_text.split(':')]

            dot = sum(a * b for a, b in zip(vec_a, vec_b))
            norm_a = sum(a * a for a in vec_a)
            norm_b = sum(b * b for b in vec_b)

            if norm_a == 0.0 or norm_b == 0.0:
                score = "0.0000"
            else:
                score = f"{dot / (math.sqrt(norm_a) * math.sqrt(norm_b)):.4f}"

            # The reference pipeline compares the utility's four-decimal output.
            if float(score) >= 0.5000:
                output.append(f"{row_id},{score}")

    return '\n'.join(output)


def test_cosine_sim_executable_exists():
    """Check if the vendored C utility was successfully compiled."""
    path = "/app/lib-embed-tools/bin/cosine_sim"
    assert os.path.isfile(path), f"Executable {path} does not exist. Did you fix the Makefile and run make?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_pipeline_script_exists():
    """Check if the pipeline Bash script exists and is executable."""
    path = "/home/user/pipeline.sh"
    assert os.path.isfile(path), f"Script {path} does not exist."
    assert os.access(path, os.X_OK), f"Script {path} is not executable. Did you run chmod +x?"


def test_fuzz_equivalence():
    """Test the agent's pipeline script on N=20 random inputs."""
    random.seed(42)
    agent_script = "/home/user/pipeline.sh"

    for i in range(20):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as tmp:
            csv_path = tmp.name

        try:
            generate_random_csv(csv_path)
            expected_out = expected_pipeline_output(csv_path)

            agent_cmd = ["/bin/bash", agent_script, csv_path]
            agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)

            assert agent_proc.returncode == 0, f"Agent script failed on input {csv_path}:\n{agent_proc.stderr}"

            agent_out = agent_proc.stdout.strip()

            if expected_out != agent_out:
                with open(csv_path, 'r') as f:
                    csv_content = f.read()
                assert False, (
                    f"Mismatch on random input {i+1}/20.\n\n"
                    f"Input CSV content:\n{csv_content}\n"
                    f"Expected output:\n{expected_out}\n\n"
                    f"Actual output (Agent):\n{agent_out}\n"
                )
        finally:
            if os.path.exists(csv_path):
                os.remove(csv_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
