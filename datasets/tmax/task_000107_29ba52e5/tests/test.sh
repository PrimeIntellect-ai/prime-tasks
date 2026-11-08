#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile
from collections import defaultdict

DATA_PATH = "/home/user/data.csv"
SOURCE_PATH = "/home/user/etl_processor.cpp"
PROCESSOR_PATH = "/home/user/etl_processor"
TUNE_PATH = "/home/user/tune.sh"
BEST_PATH = "/home/user/best_param.txt"


def read_data(data_path):
    data = []
    with open(data_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            data.append((int(parts[0]), float(parts[1]), float(parts[2])))
    return data


def compute_score(data, p):
    sums = defaultdict(lambda: [0.0, 0.0])
    for uid, v1, v2 in data:
        sums[uid][0] += v1 ** p
        sums[uid][1] += v2 ** p
    return sum(math.sqrt(s1 ** 2 + s2 ** 2) for s1, s2 in sums.values())


def compute_expected_best_param(data_path, target=150.0):
    data = read_data(data_path)
    best_p = None
    best_score = None
    min_diff = float("inf")
    for p in [1, 2, 3, 4, 5]:
        score = compute_score(data, p)
        diff = abs(score - target)
        if diff < min_diff:
            min_diff = diff
            best_p = p
            best_score = score
    return best_p, f"{best_score:.4f}"


def run_and_check_processor(executable, data, p):
    result = subprocess.run(
        [executable, str(p)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} failed for p={p}: {result.stderr}"
    )
    output = result.stdout.strip()
    assert re.fullmatch(r"-?(?:\d+)\.\d{4}", output), (
        f"Processor output must contain only a number with exactly four decimal "
        f"places; got {result.stdout!r}"
    )
    expected = compute_score(data, p)
    assert abs(float(output) - expected) <= 0.000051, (
        f"Wrong score for p={p}: got {output}, expected {expected:.4f}"
    )


def make_random_data():
    rows = []
    count = 9 + secrets.randbelow(5)
    for i in range(count):
        uid = 1 + secrets.randbelow(4)
        # Nonzero signed decimal values exercise powers and grouped aggregation.
        n1 = secrets.randbelow(51) - 25
        n2 = secrets.randbelow(51) - 25
        if n1 == 0:
            n1 = 1
        if n2 == 0:
            n2 = -1
        rows.append((uid, n1 / 10.0, n2 / 10.0))
    # Guarantee repeated IDs regardless of the random choices.
    rows.extend([(7, 1.3, -0.8), (7, -0.4, 1.7)])
    return rows


def write_data(rows):
    with open(DATA_PATH, "w") as f:
        for uid, v1, v2 in rows:
            f.write(f"{uid},{v1:.1f},{v2:.1f}\n")


def test_etl_processor_cpp_exists():
    assert os.path.isfile(SOURCE_PATH), f"C++ source code is missing at {SOURCE_PATH}"


def test_etl_processor_executable_exists():
    assert os.path.isfile(PROCESSOR_PATH), f"Compiled executable is missing at {PROCESSOR_PATH}"
    assert os.access(PROCESSOR_PATH, os.X_OK), f"File {PROCESSOR_PATH} is not executable"
    with open(PROCESSOR_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{PROCESSOR_PATH} is not a compiled executable"


def test_tune_sh_exists():
    assert os.path.isfile(TUNE_PATH), f"Bash script is missing at {TUNE_PATH}"


def test_best_param_txt_correct():
    assert os.path.isfile(BEST_PATH), f"Output file is missing at {BEST_PATH}"
    assert os.path.isfile(DATA_PATH), f"Input data file missing at {DATA_PATH}"
    best_p, best_score_str = compute_expected_best_param(DATA_PATH)
    expected_content = f"p={best_p},score={best_score_str}"
    with open(BEST_PATH, "r") as f:
        content = f.read().strip()
    assert content == expected_content, (
        f"Content of {BEST_PATH} is {content!r}, expected {expected_content!r}"
    )


def test_submitted_executable_and_cpp_source_on_generated_inputs():
    original_data = open(DATA_PATH, "rb").read()
    rebuilt = tempfile.NamedTemporaryFile(prefix="rebuilt_etl_", delete=False)
    rebuilt.close()
    try:
        compile_result = subprocess.run(
            ["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", rebuilt.name],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            f"C++ source does not compile with g++: {compile_result.stderr}"
        )
        os.chmod(rebuilt.name, 0o755)

        for _ in range(3):
            rows = make_random_data()
            write_data(rows)
            for p in [1, 2, 3, 4, 5]:
                run_and_check_processor(PROCESSOR_PATH, rows, p)
                run_and_check_processor(rebuilt.name, rows, p)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if os.path.exists(rebuilt.name):
            os.unlink(rebuilt.name)


def test_tune_script_invokes_processor_for_grid_and_uses_returned_scores():
    original_processor = open(PROCESSOR_PATH, "rb").read()
    original_mode = stat.S_IMODE(os.stat(PROCESSOR_PATH).st_mode)
    original_best = open(BEST_PATH, "rb").read() if os.path.exists(BEST_PATH) else None
    token = secrets.token_hex(8)
    log_path = f"/tmp/etl_calls_{token}"

    # These runtime-generated scores have a unique optimum, so a script that
    # ignores processor output or reuses the fixed dataset's answer cannot pass.
    best_p = 1 + secrets.randbelow(5)
    scores = {}
    for p in range(1, 6):
        scores[p] = 150.0 + (p + 3) * 7.0
    scores[best_p] = 150.125

    cases = "\n".join(
        f"  {p}) printf '%0.4f\\n' {scores[p]} ;;" for p in range(1, 6)
    )
    wrapper = f"""#!/bin/bash
printf '%s\\n' "$1" >> {log_path}
case "$1" in
{cases}
  *) exit 2 ;;
esac
"""

    try:
        with open(PROCESSOR_PATH, "w") as f:
            f.write(wrapper)
        os.chmod(PROCESSOR_PATH, 0o755)
        if os.path.exists(BEST_PATH):
            os.unlink(BEST_PATH)

        result = subprocess.run(
            ["bash", TUNE_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, f"tune.sh failed: {result.stderr}"
        assert os.path.isfile(log_path), "tune.sh did not invoke /home/user/etl_processor"
        with open(log_path, "r") as f:
            calls = [line.strip() for line in f if line.strip()]
        for p in range(1, 6):
            assert str(p) in calls, f"tune.sh did not run etl_processor for p={p}"

        assert os.path.isfile(BEST_PATH), "tune.sh did not generate best_param.txt"
        with open(BEST_PATH, "r") as f:
            content = f.read().strip()
        expected = f"p={best_p},score={scores[best_p]:.4f}"
        assert content == expected, (
            f"tune.sh wrote {content!r}; expected {expected!r} from processor outputs"
        )
    finally:
        with open(PROCESSOR_PATH, "wb") as f:
            f.write(original_processor)
        os.chmod(PROCESSOR_PATH, original_mode)
        if original_best is None:
            if os.path.exists(BEST_PATH):
                os.unlink(BEST_PATH)
        else:
            with open(BEST_PATH, "wb") as f:
                f.write(original_best)
        if os.path.exists(log_path):
            os.unlink(log_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
