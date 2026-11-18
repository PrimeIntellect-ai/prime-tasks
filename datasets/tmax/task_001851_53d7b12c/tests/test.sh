#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile


def expected_output(log_content):
    total_score = 0.0
    count = 0
    for line in log_content.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split(",")
        if len(parts) == 4:
            try:
                cpu = float(parts[2])
                mem = float(parts[3])
                total_score += cpu * 0.5 + mem * 0.1
                count += 1
            except ValueError:
                pass
    assert count > 0, "No valid lines found to compute average."
    return f"{total_score / count:.2f}"


def test_solution_correctness():
    log_path = "/home/user/data/perf.log"
    assert os.path.exists(log_path), f"File {log_path} is missing."

    with open(log_path, "r") as f:
        expected_str = expected_output(f.read())

    sol_path = "/home/user/solution.txt"
    assert os.path.exists(sol_path), f"File {sol_path} is missing. Did you save the output?"

    with open(sol_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_str, (
        f"Incorrect average score in {sol_path}. "
        f"Expected '{expected_str}', but got '{actual_content}'."
    )


def test_go_mod_fixed():
    go_mod_path = "/home/user/perf-tool/go.mod"
    assert os.path.exists(go_mod_path), f"File {go_mod_path} is missing."

    with open(go_mod_path, "r") as f:
        content = f.read()

    assert "v1.9.9" not in content, "The go.mod file still contains the intentionally invalid version v1.9.9."


def test_tool_builds_and_computes_correctly():
    project = "/home/user/perf-tool"
    source = os.path.join(project, "main.go")
    assert os.path.isfile(source), f"File {source} is missing."

    with tempfile.TemporaryDirectory() as tmpdir:
        binary = os.path.join(tmpdir, "perf-tool")
        built = subprocess.run(
            ["go", "build", "-o", binary, "."],
            cwd=project,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        assert built.returncode == 0, f"The Go tool does not compile:\n{built.stdout}{built.stderr}"
        assert os.path.isfile(binary) and os.access(binary, os.X_OK), "go build did not produce an executable."

        log_path = "/home/user/data/perf.log"
        with open(log_path, "rb") as f:
            original_log = f.read()

        def run_with_log(content):
            try:
                with open(log_path, "w") as f:
                    f.write(content)
                result = subprocess.run(
                    [binary],
                    cwd=project,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=15,
                )
                assert result.returncode == 0, (
                    f"The tool failed on a valid test log (exit {result.returncode}):\n"
                    f"{result.stdout}{result.stderr}"
                )
                return result.stdout.strip()
            finally:
                with open(log_path, "wb") as f:
                    f.write(original_log)

        original_text = original_log.decode()
        assert run_with_log(original_text) == expected_output(original_text), (
            "The compiled tool does not produce the correct result for perf.log."
        )

        cases = [
            "1,svc,8,70\n",
            "1,svc,10,50\n2,svc,30,150\n3,svc,50,250\n",
            "1,svc,10,100\nmalformed,too,few\n2,svc,900,900,extra\n3,svc,30,300\n",
        ]
        for content in cases:
            expected = expected_output(content)
            actual = run_with_log(content)
            assert actual == expected, (
                "The compiled tool produced an incorrect result for a verification log. "
                f"Expected '{expected}', got '{actual}'."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
