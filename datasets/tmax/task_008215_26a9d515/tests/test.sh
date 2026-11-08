#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/fit_model.sh"
DATA_PATH = "/home/user/data.csv"
RESULT_PATH = "/home/user/result.txt"
OUTPUT_RE = re.compile(r"m=([+-]?\d+\.\d{6}),b=([+-]?\d+\.\d{6})\Z")


def run_script(csv_path):
    return subprocess.run(
        [SCRIPT_PATH, csv_path], capture_output=True, text=True, timeout=10
    )


def ols(rows):
    n = len(rows)
    sx = sum(x for x, _ in rows)
    sy = sum(y for _, y in rows)
    sxy = sum(x * y for x, y in rows)
    sx2 = sum(x * x for x, _ in rows)
    denominator = n * sx2 - sx * sx
    assert denominator != 0
    m = (n * sxy - sx * sy) / denominator
    b = (sy - m * sx) / n
    return m, b


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_script_uses_awk():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "awk" in content, f"Script {SCRIPT_PATH} does not appear to use 'awk' as required."

    non_comment_lines = "\n".join(
        line for line in content.splitlines() if not line.lstrip().startswith("#")
    )
    assert re.search(r"(?<![A-Za-z0-9_])(?:g?awk)(?![A-Za-z0-9_])", non_comment_lines), (
        f"Script {SCRIPT_PATH} mentions awk only in comments."
    )


def test_result_file_content():
    assert os.path.isfile(RESULT_PATH), f"Result file {RESULT_PATH} does not exist."

    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()

    expected = "m=2.000000,b=0.120000"
    assert content == expected, (
        f"Content of {RESULT_PATH} is incorrect. Expected '{expected}', got '{content}'."
    )


def test_result_was_produced_for_supplied_data():
    result = run_script(DATA_PATH)
    assert result.returncode == 0, "Script failed to execute on /home/user/data.csv."
    with open(RESULT_PATH, "r") as f:
        saved = f.read().strip()
    assert result.stdout.strip() == saved, (
        "result.txt does not match the script's output for /home/user/data.csv."
    )


def test_script_dynamic_computation():
    # Preserve the original fixed behavioral test.
    with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as tmp:
        tmp.write("x,y\n1,2\n2,4\n3,6\n")
        tmp_path = tmp.name

    try:
        result = run_script(tmp_path)
        assert result.returncode == 0, "Script failed to execute on test data."
        output = result.stdout.strip()
        expected_output = "m=2.000000,b=0.000000"
        assert output == expected_output, (
            "Script did not compute the correct OLS parameters for test data. "
            f"Expected '{expected_output}', got '{output}'."
        )
    finally:
        os.remove(tmp_path)


def test_randomized_ols_computation():
    rng = secrets.SystemRandom()

    for _ in range(12):
        count = rng.randint(4, 12)
        xs = rng.sample(range(-100, 101), count)
        rows = [(x, rng.randint(-500, 500)) for x in xs]
        expected_m, expected_b = ols(rows)

        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as tmp:
            tmp.write("x,y\n")
            for x, y in rows:
                tmp.write(f"{x},{y}\n")
            tmp_path = tmp.name

        try:
            result = run_script(tmp_path)
            assert result.returncode == 0, (
                f"Script failed on generated data: {result.stderr}"
            )
            output = result.stdout.strip()
            match = OUTPUT_RE.fullmatch(output)
            assert match, (
                "Output must be exactly m=<slope>,b=<intercept> with both values "
                f"at exactly 6 decimal places; got {output!r}."
            )
            actual_m = float(match.group(1))
            actual_b = float(match.group(2))
            assert abs(actual_m - expected_m) <= 5.1e-7, (
                f"Incorrect slope for generated rows {rows}: expected {expected_m:.6f}, "
                f"got {actual_m:.6f}."
            )
            assert abs(actual_b - expected_b) <= 5.1e-7, (
                f"Incorrect intercept for generated rows {rows}: expected {expected_b:.6f}, "
                f"got {actual_b:.6f}."
            )
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
