#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import string
import tempfile
import shutil

def generate_random_string(length):
    chars = string.ascii_letters + string.digits + string.punctuation + " \n\t"
    return ''.join(random.choice(chars) for _ in range(length))

def generate_fuzz_dir(base_dir):
    num_dirs = random.randint(1, 15)
    num_files = random.randint(1, 50)

    dirs = [base_dir]
    for _ in range(num_dirs):
        d = os.path.join(random.choice(dirs), f"dir_{random.randint(1000, 9999)}")
        os.makedirs(d, exist_ok=True)
        dirs.append(d)

    for _ in range(num_files):
        d = random.choice(dirs)
        fpath = os.path.join(d, f"file_{random.randint(10000, 99999)}.txt")
        size = random.randint(0, 10000) # up to 10KB to keep tests reasonably fast
        content = generate_random_string(size)

        if random.random() < 0.3:
            # Inject CONFIDENTIAL
            if size > 12:
                inject_pos = random.randint(0, size - 12)
                content = content[:inject_pos] + "CONFIDENTIAL" + content[inject_pos+12:]
            else:
                content += "CONFIDENTIAL"

        with open(fpath, "w") as f:
            f.write(content)

def test_packer_fuzz_equivalence():
    agent_script = "/home/user/packer.sh"
    oracle_bin = "/app/legacy_packer"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_bin), f"Oracle binary not found at {oracle_bin}"

    random.seed(42)

    for i in range(50):
        with tempfile.TemporaryDirectory() as temp_dir:
            generate_fuzz_dir(temp_dir)

            oracle_cmd = [oracle_bin, temp_dir]
            agent_cmd = ["/bin/bash", agent_script, temp_dir]

            oracle_result = subprocess.run(oracle_cmd, capture_output=True, text=False)
            agent_result = subprocess.run(agent_cmd, capture_output=True, text=False)

            assert oracle_result.returncode == 0, f"Oracle failed on iteration {i}"
            assert agent_result.returncode == 0, f"Agent script failed on iteration {i}:\n{agent_result.stderr.decode('utf-8', errors='replace')}"

            if oracle_result.stdout != agent_result.stdout:
                oracle_out = oracle_result.stdout.decode('utf-8', errors='replace')
                agent_out = agent_result.stdout.decode('utf-8', errors='replace')

                # Truncate output for error message if it's too long
                if len(oracle_out) > 1000:
                    oracle_out = oracle_out[:1000] + "\n...[truncated]"
                if len(agent_out) > 1000:
                    agent_out = agent_out[:1000] + "\n...[truncated]"

                assert False, (
                    f"Mismatch on iteration {i}!\n"
                    f"Target directory: {temp_dir}\n"
                    f"=== Oracle Output ===\n{oracle_out}\n"
                    f"=== Agent Output ===\n{agent_out}\n"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
