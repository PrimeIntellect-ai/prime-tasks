#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess

SCRIPT_PATH = "/home/user/pipeline.sh"
DATA_PATH = "/home/user/dna_sequences.txt"
OUTPUT_PATH = "/home/user/total_energy.txt"
PATTERN = re.compile(r"GATA[ATCG]{5,10}CACA")


def expected_output(dataset):
    lengths = []
    for line in dataset.decode("ascii").splitlines():
        lengths.extend(len(match.group(0)) for match in PATTERN.finditer(line))

    awk_program = r'''
BEGIN { seed = 123; total_energy = 0 }
{
    L = $1
    sum_y = 0
    for (i = 0; i < 1000; i++) {
        seed = (1103515245 * seed + 12345) % 2147483648
        r = seed / 2147483648
        x = r * L
        y = (x * x) / L
        sum_y += y
    }
    total_energy += (sum_y / 1000) * L
}
END { printf "%.2f\n", total_energy }
'''
    input_data = "".join(f"{length}\n" for length in lengths)
    result = subprocess.run(
        ["gawk", awk_program],
        input=input_data,
        text=True,
        capture_output=True,
        check=True,
        env={**os.environ, "LC_ALL": "C"},
    )
    return result.stdout.strip()


def run_pipeline_and_check(dataset):
    with open(DATA_PATH, "wb") as f:
        f.write(dataset)

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=30,
        env={**os.environ, "LC_ALL": "C"},
    )
    assert result.returncode == 0, (
        f"pipeline.sh exited with {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."

    with open(OUTPUT_PATH, "r") as f:
        raw_content = f.read()
    content = raw_content.strip()

    assert re.fullmatch(r"[0-9]+\.[0-9]{2}\n?", raw_content), (
        "Output must contain only one non-negative number rounded to exactly two decimal places."
    )
    expected = expected_output(dataset)
    assert content == expected, (
        f"Output file {OUTPUT_PATH} contains '{content}', expected '{expected}'."
    )


def test_pipeline_script_exists_and_executable():
    """Test that pipeline.sh exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    st = os.stat(SCRIPT_PATH)
    is_executable = bool(st.st_mode & stat.S_IXUSR)
    assert is_executable, f"Script {SCRIPT_PATH} is not executable."


def test_total_energy_output():
    """Execute the pipeline and verify dynamically derived results."""
    with open(DATA_PATH, "rb") as f:
        original_dataset = f.read()

    alternate_dataset = (
        b"TT" + b"GATA" + b"A" * 5 + b"CACA" + b"GG\n"
        + b"GATA" + b"ACGTACGTAC" + b"CACA"
        + b"GATA" + b"TGCAT" + b"CACA\n"
        + b"GATA" + b"A" * 4 + b"CACA\n"
    )

    try:
        run_pipeline_and_check(alternate_dataset)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_dataset)

    # Leave and verify the required output for the supplied dataset.
    run_pipeline_and_check(original_dataset)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
