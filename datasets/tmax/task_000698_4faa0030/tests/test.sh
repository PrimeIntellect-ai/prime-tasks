#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import random
import stat
import string
import subprocess
import tempfile


def generate_random_text(length):
    chars = string.ascii_letters + string.digits + string.punctuation + ' \t\n\r'
    return ''.join(random.choice(chars) for _ in range(length))


def test_fuzz_equivalence():
    agent_script = "/home/user/run_minidiff.py"
    oracle_script = "/app/oracle/minidiff_oracle.pyc"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing: {oracle_script}"

    random.seed(42)
    num_iterations = 100

    with tempfile.TemporaryDirectory() as tmpdir:
        file1 = os.path.join(tmpdir, "file1.txt")
        file2 = os.path.join(tmpdir, "file2.txt")

        for i in range(num_iterations):
            len1 = random.randint(0, 5000)
            len2 = random.randint(0, 5000)

            text1 = generate_random_text(len1)
            text2 = generate_random_text(len2)

            with open(file1, "wb") as f:
                f.write(text1.encode("utf-8"))
            with open(file2, "wb") as f:
                f.write(text2.encode("utf-8"))

            agent_cmd = ["python3", agent_script, file1, file2]
            oracle_cmd = ["python3", oracle_script, file1, file2]

            agent_proc = subprocess.run(agent_cmd, capture_output=True)
            oracle_proc = subprocess.run(oracle_cmd, capture_output=True)

            assert agent_proc.returncode == oracle_proc.returncode, (
                f"Return code mismatch on iteration {i}.\n"
                f"Agent exit code: {agent_proc.returncode}\n"
                f"Oracle exit code: {oracle_proc.returncode}\n"
                f"Agent stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"
            )

            if oracle_proc.returncode == 0:
                assert agent_proc.stdout == oracle_proc.stdout, (
                    f"Output mismatch on iteration {i}.\n"
                    f"File 1 length: {len1}, File 2 length: {len2}\n"
                    f"Agent output length: {len(agent_proc.stdout)}\n"
                    f"Oracle output length: {len(oracle_proc.stdout)}"
                )


def test_source_fix_and_wrapper_without_oracle():
    agent_script = "/home/user/run_minidiff.py"
    core_path = "/app/minidiff-v1.2/minidiff/core.py"
    oracle_path = "/app/oracle/minidiff_oracle.pyc"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert not os.path.islink(agent_script), "Agent script must be a real wrapper script"
    assert os.path.isfile(core_path), f"Core source missing: {core_path}"
    assert not os.path.islink(core_path), "Core source must be a real Python source file"
    assert os.path.isfile(oracle_path), f"Oracle script missing: {oracle_path}"

    oracle_bytes = open(oracle_path, "rb").read()
    oracle_mode = stat.S_IMODE(os.stat(oracle_path).st_mode)
    os.unlink(oracle_path)

    try:
        # Load the submitted source directly so fixing only the wrapper cannot pass.
        spec = importlib.util.spec_from_file_location("submitted_minidiff_core", core_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        cases = [
            ("", ""),
            ("ignored", "\n"),
            ("ignored", "\n\n"),
            ("a\nb", "alpha\nbeta\n"),
            ("x", "one\n\nthree\n\n"),
            ("x", "no trailing newline"),
        ]
        rng = random.Random(8675309)
        for _ in range(100):
            cases.append((generate_random_text(rng.randint(0, 300)),
                          generate_random_text(rng.randint(0, 300))))

        for text1, text2 in cases:
            expected = "DELTA:" + "|".join(text2.split("\n"))
            assert module.generate_delta(text1, text2) == expected

        # The wrapper must also work when the oracle is absent, proving it does not
        # merely exec or invoke the reference executable.
        with tempfile.TemporaryDirectory() as tmpdir:
            file1 = os.path.join(tmpdir, "file1.txt")
            file2 = os.path.join(tmpdir, "file2.txt")
            wrapper_cases = cases[:6] + cases[-20:]
            for i, (text1, text2) in enumerate(wrapper_cases):
                with open(file1, "w", encoding="utf-8", newline="") as f:
                    f.write(text1)
                with open(file2, "w", encoding="utf-8", newline="") as f:
                    f.write(text2)

                proc = subprocess.run(
                    ["python3", agent_script, file1, file2],
                    capture_output=True,
                    timeout=10,
                )
                assert proc.returncode == 0, (
                    f"Wrapper failed without oracle on case {i}: "
                    f"{proc.stderr.decode('utf-8', errors='replace')}"
                )
                with open(file2, "r", encoding="utf-8") as f:
                    normalized_text2 = f.read()
                expected_stdout = (
                    "DELTA:" + "|".join(normalized_text2.split("\n")) + "\n"
                ).encode("utf-8")
                assert proc.stdout == expected_stdout, (
                    f"Wrapper output mismatch without oracle on case {i}"
                )
    finally:
        with open(oracle_path, "wb") as f:
            f.write(oracle_bytes)
        os.chmod(oracle_path, oracle_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
