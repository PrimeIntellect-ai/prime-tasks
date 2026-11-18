#!/bin/bash
mkdir -p /logs/verifier

REAL_BC="/tmp/verifier-real-bc-$$"
BC_LOG="/tmp/verifier-bc-log-$$"
export BC_LOG

if ! mv /usr/bin/bc "$REAL_BC"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat > /usr/bin/bc <<EOF
#!/bin/bash
payload=\$(cat)
{
    echo '@@BEGIN@@'
    printf '%s\n' "\$payload"
    echo '@@END@@'
} >> "\$BC_LOG"
printf '%s\n' "\$payload" | "$REAL_BC" "\$@"
EOF
chmod +x /usr/bin/bc

cleanup() {
    rm -f /usr/bin/bc
    mv "$REAL_BC" /usr/bin/bc 2>/dev/null || true
    rm -f "$BC_LOG"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from collections import Counter
from decimal import Decimal, getcontext

PIPELINE = "/home/user/sensor_pipeline/run_pipeline.sh"
INPUT_DIR = "/home/user/sensor_pipeline/input"
AGGREGATED = "/home/user/sensor_pipeline/out/aggregated.dat"
CALCULATOR = "/home/user/sensor_pipeline/calculate_convergence.sh"
RESULT = "/home/user/convergence_result.txt"
BC_LOG = os.environ["BC_LOG"]

getcontext().prec = 50


def input_paths():
    return [os.path.join(INPUT_DIR, f"chunk_{i}.dat") for i in range(1, 11)]


def expected_lines():
    values = []
    for path in input_paths():
        with open(path) as f:
            values.extend(f.read().splitlines())
    return values


def expected_after_50(lines):
    value = sum((Decimal(line.strip()) for line in lines), Decimal(0))
    for _ in range(50):
        value /= Decimal("1.05")
    return value


def verify_bc_use():
    assert os.path.isfile(BC_LOG), "The executed pipeline did not invoke bc."
    with open(BC_LOG) as f:
        log = f.read()
    payloads = re.findall(r"@@BEGIN@@\n(.*?)\n@@END@@", log, re.S)
    assert payloads, "The executed pipeline did not invoke bc."
    assert any(re.search(r"/\s*1\.05\b", payload) for payload in payloads), \
        "The executed bc calculations did not apply the required division by 1.05."
    for payload in payloads:
        assignments = re.findall(r"\bscale\s*=\s*(\d+)", payload)
        assert assignments, f"A bc command was executed without setting scale: {payload!r}"
        assert all(int(scale) >= 6 for scale in assignments), \
            f"A bc command used scale below 6: {payload!r}"


def run_and_validate():
    for path in (AGGREGATED, RESULT, BC_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    proc = subprocess.run(
        [PIPELINE], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=20, env=os.environ.copy()
    )
    assert proc.returncode == 0, (
        f"Pipeline failed with status {proc.returncode}.\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )

    wanted = expected_lines()
    assert os.path.isfile(AGGREGATED), f"Aggregated file {AGGREGATED} does not exist."
    with open(AGGREGATED) as f:
        actual = f.read().splitlines()
    assert len(actual) == 30, \
        f"Expected exactly 30 lines in {AGGREGATED}, found {len(actual)}. Race condition might not be fully fixed."
    assert Counter(actual) == Counter(wanted), \
        "Aggregated data does not contain every input line exactly once."

    assert os.path.isfile(RESULT), f"Result file {RESULT} is missing."
    with open(RESULT) as f:
        content = f.read().strip()
    assert "." in content, f"Result file {RESULT} does not contain a decimal point. Content: {content}"
    match = re.search(r"(\d+\.\d+)", content)
    assert match is not None, f"Could not find a floating-point number in {RESULT}."
    value = Decimal(match.group(1))
    expected = expected_after_50(wanted)
    assert abs(value - expected) < Decimal("0.00008"), \
        f"Result {value} is not the value produced by 50 iterations; expected approximately {expected}."
    assert Decimal("5.0") < value < Decimal("5.5"), \
        f"Converged value {value} is outside the expected range (5.0 - 5.5)."
    verify_bc_use()


def test_calculate_convergence_fixed():
    assert os.path.isfile(CALCULATOR), f"Script {CALCULATOR} is missing."
    with open(CALCULATOR) as f:
        content = f.read()
    assert re.search(r"scale\s*=\s*[6-9]|\bscale\s*=\s*[1-9][0-9]+", content), \
        "The calculate_convergence.sh script does not set scale to at least 6 in bc commands."


def test_original_data_complete_and_pipeline_reliable():
    for _ in range(5):
        run_and_validate()

    with open(AGGREGATED) as f:
        lines = f.read().splitlines()
    total_sum = sum(float(line.strip()) for line in lines if line.strip())
    assert abs(total_sum - 60.138) < 1e-6, \
        f"Expected sum of aggregated data to be 60.138, got {total_sum}."


def test_pipeline_uses_current_inputs_and_computes_result():
    backups = {}
    for path in input_paths():
        with open(path, "rb") as f:
            backups[path] = f.read()

    try:
        nonce = secrets.randbelow(700) + 100
        for i, path in enumerate(input_paths(), 1):
            values = [
                Decimal("1") + Decimal(nonce + i) / Decimal("10000"),
                Decimal("2") + Decimal(nonce + 2 * i) / Decimal("10000"),
                Decimal("3") + Decimal(nonce + 3 * i) / Decimal("10000"),
            ]
            with open(path, "w") as f:
                for value in values:
                    f.write(f"{value:.4f}\n")
        for _ in range(3):
            run_and_validate()
    finally:
        for path, data in backups.items():
            with open(path, "wb") as f:
                f.write(data)

    # Leave the requested artifact in a state corresponding to the original inputs.
    run_and_validate()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
