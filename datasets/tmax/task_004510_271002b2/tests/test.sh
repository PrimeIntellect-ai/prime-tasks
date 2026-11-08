#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import tempfile
import filecmp

def test_repo_id_extracted():
    repo_id_path = "/home/user/repo_id.txt"
    assert os.path.isfile(repo_id_path), f"{repo_id_path} does not exist."
    with open(repo_id_path, "r") as f:
        content = f.read().strip()

    # We can derive the ID by reading the video or just checking against the known truth
    # since deriving it from video requires cv2, let's just check the value.
    assert content == "2947528371", f"Expected repo_id to be 2947528371, got {content}."

def create_dummy_elf(path):
    c_code = """
    const int ro_var = 42;
    int rw_var = 42;
    int main() { return ro_var + rw_var; }
    """
    c_path = path + ".c"
    with open(c_path, "w") as f:
        f.write(c_code)
    subprocess.run(["gcc", "-O0", c_path, "-o", path], check=True)

def create_wal(path, repo_id):
    sections = [".text", ".data", ".rodata"]
    with open(path, "w") as f:
        f.write(f"REPO_ID {repo_id}\n")
        for _ in range(random.randint(1, 20)):
            cmd = random.choice(["PATCH_SEC", "APPEND", "TRUNCATE"])
            if cmd == "PATCH_SEC":
                sec = random.choice(sections)
                offset = random.randint(0, 10)
                hex_str = os.urandom(random.randint(1, 10)).hex()
                f.write(f"PATCH_SEC {sec} {offset} {hex_str}\n")
            elif cmd == "APPEND":
                hex_str = os.urandom(random.randint(1, 50)).hex()
                f.write(f"APPEND {hex_str}\n")
            elif cmd == "TRUNCATE":
                length = random.randint(100, 5000)
                f.write(f"TRUNCATE {length}\n")

def test_apply_wal_fuzz():
    agent_script = "/home/user/apply_wal.py"
    oracle_script = "/tests/oracle_apply_wal.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} missing."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} missing."

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(100):
            in_elf = os.path.join(tmpdir, f"in_{i}.elf")
            wal_file = os.path.join(tmpdir, f"wal_{i}.txt")
            out_elf_agent = os.path.join(tmpdir, f"out_agent_{i}.elf")
            out_elf_oracle = os.path.join(tmpdir, f"out_oracle_{i}.elf")

            create_dummy_elf(in_elf)

            repo_id = 2947528371 if random.random() > 0.2 else random.randint(1000000000, 9999999999)
            create_wal(wal_file, repo_id)

            # Run oracle
            subprocess.run(["python3", oracle_script, in_elf, wal_file, out_elf_oracle], check=True)

            # Run agent
            res = subprocess.run(["python3", agent_script, in_elf, wal_file, out_elf_agent], capture_output=True, text=True)
            assert res.returncode == 0, f"Agent script failed on iteration {i} with error:\n{res.stderr}"

            assert os.path.isfile(out_elf_agent), f"Agent did not produce output file on iteration {i}."

            with open(wal_file, "r") as f:
                wal_content = f.read()

            assert filecmp.cmp(out_elf_agent, out_elf_oracle, shallow=False), (
                f"Mismatch on iteration {i}.\n"
                f"WAL content:\n{wal_content}\n"
                "Agent output differs from Oracle output."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
