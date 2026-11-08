#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import string
import subprocess


def test_parallel_fixed():
    parallel_script = "/app/parallel-20231022/src/parallel"
    assert os.path.isfile(parallel_script), f"GNU parallel script is missing at {parallel_script}"

    with open(parallel_script, 'r', encoding='utf-8', errors='ignore') as f:
        first_line = f.readline().strip()

    assert "pperl" not in first_line, f"The shebang in {parallel_script} still contains 'pperl'."
    assert "perl" in first_line, f"The shebang in {parallel_script} should contain 'perl'."

    result = subprocess.run([parallel_script, "--version"], capture_output=True, text=True)
    assert result.returncode == 0, f"GNU parallel failed to run. Stderr: {result.stderr}"


def generate_random_csv(num_lines):
    lines = []
    for _ in range(num_lines):
        timestamp = random.randint(1600000000, 1700000000)
        sensor_id = ''.join(random.choices(string.ascii_uppercase + string.digits, k=3))
        value = random.randint(0, 1000)
        lines.append(f"{timestamp},{sensor_id},{value}")
    return "\n".join(lines) + "\n"


def install_parallel_probe():
    parallel_script = "/app/parallel-20231022/src/parallel"
    real_parallel = "/tmp/verifier_parallel_real"
    marker = "/tmp/verifier_parallel_invocations"

    shutil.copy2(parallel_script, real_parallel)
    os.chmod(real_parallel, 0o755)

    with open(parallel_script, "w", encoding="utf-8") as f:
        f.write("#!/bin/bash\n")
        f.write(f"printf '%q ' \"$@\" >> {marker}\n")
        f.write(f"printf '\\n' >> {marker}\n")
        f.write(f"exec {real_parallel} \"$@\"\n")
    os.chmod(parallel_script, 0o755)
    return marker


def test_fuzz_equivalence():
    oracle_path = "/tests/reference_etl.sh"
    agent_path = "/home/user/etl.sh"

    assert os.path.isfile(oracle_path), f"Oracle is missing from the verifier bundle at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent script is missing at {agent_path}"
    assert os.access(agent_path, os.X_OK) or os.access(agent_path, os.R_OK), f"Agent script {agent_path} is not readable/executable."

    marker = install_parallel_probe()
    random.seed(42)
    N = 100

    for i in range(N):
        num_lines = random.randint(100, 10000)
        csv_input = generate_random_csv(num_lines)

        oracle_proc = subprocess.run(
            ["bash", oracle_path],
            input=csv_input,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}. Stderr: {oracle_proc.stderr}"
        oracle_output = oracle_proc.stdout

        if os.path.exists(marker):
            os.remove(marker)

        agent_proc = subprocess.run(
            ["bash", agent_path],
            input=csv_input,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}. Stderr: {agent_proc.stderr}"
        agent_output = agent_proc.stdout

        assert agent_output == oracle_output, (
            f"Output mismatch on iteration {i} (input lines: {num_lines}).\n"
            f"--- Oracle Output ---\n{oracle_output}\n"
            f"--- Agent Output ---\n{agent_output}\n"
        )

        assert os.path.isfile(marker) and os.path.getsize(marker) > 0, (
            "etl.sh did not invoke /app/parallel-20231022/src/parallel while processing input"
        )
        with open(marker, "r", encoding="utf-8", errors="replace") as f:
            invocations = [line.strip() for line in f if line.strip()]
        assert any(line not in ("--version", "--help", "-h") for line in invocations), (
            "etl.sh only invoked GNU Parallel for informational output, not for ETL processing"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
