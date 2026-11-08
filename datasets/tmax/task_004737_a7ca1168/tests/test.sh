#!/bin/bash
mkdir -p /logs/verifier

H5DUMP="$(command -v h5dump)"
REAL_H5DUMP="${H5DUMP}.verifier-real"

mv "$H5DUMP" "$REAL_H5DUMP"
cat > "$H5DUMP" <<EOF
#!/bin/bash
printf 'called\n' >> /tmp/verifier_h5dump_calls
exec "$REAL_H5DUMP" "\$@"
EOF
chmod +x "$H5DUMP"

restore_h5dump() {
    rm -f "$H5DUMP"
    mv "$REAL_H5DUMP" "$H5DUMP"
}
trap restore_h5dump EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

import h5py
import numpy as np
import pytest

SCRIPT = "/home/user/analyze.sh"
WEIGHTS = "/home/user/weights.txt"
NORM = "/home/user/norm.txt"
H5_LOG = "/tmp/verifier_h5dump_calls"


def run_script():
    for path in (WEIGHTS, NORM, H5_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"analyze.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(H5_LOG) and os.path.getsize(H5_LOG) > 0, (
        "analyze.sh did not invoke h5dump."
    )


def read_weights():
    assert os.path.isfile(WEIGHTS), f"Weights file {WEIGHTS} does not exist."
    with open(WEIGHTS, "r") as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]
    assert len(lines) == 3, f"Expected 3 weights, found {len(lines)} in {WEIGHTS}."
    try:
        return [float(x) for x in lines]
    except ValueError:
        pytest.fail(f"Could not parse weights as floats in {WEIGHTS}.")


def test_analyze_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_execute_script_on_original_inputs():
    run_script()


def test_weights_file():
    weights = read_weights()
    expected_weights = [10.0, 0.0, 20.0]
    for i, (w, ew) in enumerate(zip(weights, expected_weights)):
        assert abs(w - ew) < 1e-4, f"Weight {i+1} is {w}, expected approximately {ew}."


def test_norm_file():
    assert os.path.isfile(NORM), f"Norm file {NORM} does not exist."
    with open(NORM, "r") as f:
        content = f.read().strip()
    assert content == "22.36", f"Expected norm to be '22.36', but got '{content}'."


def test_dynamic_inputs_are_parsed_and_solved():
    rng = secrets.SystemRandom()
    a, b, c = [rng.randint(1, 6) for _ in range(3)]
    X = np.array(
        [[float(a), 1.0, 0.0],
         [0.0, float(b), 1.0],
         [1.0, 0.0, float(c)]],
        dtype=np.float64,
    )
    lengths = [rng.randint(7, 37) for _ in range(3)]

    with open("/home/user/seqs.fasta", "w") as f:
        for i, length in enumerate(lengths, 1):
            f.write(f">dynamic_seq_{i}\n")
            f.write(("ACGT" * ((length + 3) // 4))[:length] + "\n")

    with h5py.File("/home/user/data.h5", "w") as f:
        f.create_dataset("/X", data=X)

    expected = np.linalg.solve(X, np.asarray(lengths, dtype=np.float64))
    expected_norm = f"{np.linalg.norm(expected):.2f}"

    run_script()
    actual = read_weights()
    for i, (value, wanted) in enumerate(zip(actual, expected)):
        assert abs(value - wanted) < 1e-4, (
            f"Dynamic weight {i+1} is {value}, expected approximately {wanted}."
        )

    assert os.path.isfile(NORM), f"Norm file {NORM} does not exist."
    with open(NORM, "r") as f:
        content = f.read().strip()
    assert re.fullmatch(r"[+-]?(?:\d+\.\d{2})", content), (
        f"Norm must be rounded to exactly 2 decimal places, got '{content}'."
    )
    assert content == expected_norm, (
        f"Expected dynamic norm '{expected_norm}', but got '{content}'."
    )
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit "$status"
