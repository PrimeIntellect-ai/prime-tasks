#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import subprocess
import tempfile


def parse_csv(path):
    with open(path, "r") as f:
        header = f.readline()
        rows = []
        for line in f:
            if line.strip():
                x, y = map(float, line.strip().split(','))
                rows.append((x, y))
    return header, rows


def expected_smoothed_bytes(input_path, window):
    header, rows = parse_csv(input_path)
    output = [header]
    half = window // 2
    for i, (x, _) in enumerate(rows):
        lo = max(0, i - half)
        hi = min(len(rows) - 1, i + half)
        avg = sum(rows[j][1] for j in range(lo, hi + 1)) / (hi - lo + 1)
        output.append(f"{x:.2f},{avg:.4f}\n")
    return ''.join(output).encode()


def parse_best_fit(path):
    with open(path, "r") as f:
        content = f.read().strip()
    match = re.match(r"^mu1=(\d+),mu2=(\d+),mse=([0-9.]+)$", content)
    assert match is not None, (
        f"Content of {path} does not match the required format: "
        "mu1=[BEST_MU1],mu2=[BEST_MU2],mse=[MIN_MSE]. "
        f"Found: {content}"
    )
    return content, int(match.group(1)), int(match.group(2)), float(match.group(3))


def independently_calculate_mse(path, mu1, mu2):
    _, rows = parse_csv(path)
    total = 0.0
    for x, y_true in rows:
        y_pred = (
            10.0 * math.exp(-0.5 * ((x - mu1) / 15.0) ** 2)
            + 8.0 * math.exp(-0.5 * ((x - mu2) / 20.0) ** 2)
        )
        total += (y_true - y_pred) ** 2
    return total / len(rows)


# Original assertions retained.
def test_smoother_compiled():
    smoother_path = "/home/user/bin/smoother"
    assert os.path.isfile(smoother_path), f"Executable {smoother_path} is missing."
    assert os.access(smoother_path, os.X_OK), f"File {smoother_path} is not executable."


def test_processed_data_exists():
    processed_file = "/home/user/data/processed/spectrum_smoothed.csv"
    assert os.path.isfile(processed_file), f"Processed data file {processed_file} is missing."
    with open(processed_file, "r") as f:
        lines = f.readlines()
    assert len(lines) > 1, f"Processed data file {processed_file} does not contain enough data."
    assert "wavelength,intensity" in lines[0], "Header missing in smoothed CSV."


def test_optimize_script_exists():
    script_path = "/home/user/optimize.sh"
    assert os.path.isfile(script_path), f"Bash script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Bash script {script_path} is not executable."


def test_best_fit_output():
    best_fit_file = "/home/user/best_fit.txt"
    assert os.path.isfile(best_fit_file), f"Output file {best_fit_file} is missing."
    _, mu1, mu2, mse = parse_best_fit(best_fit_file)
    assert mu1 == 126, f"Expected mu1 to be 126, but got {mu1}."
    assert mu2 == 344, f"Expected mu2 to be 344, but got {mu2}."
    assert 0.40 < mse < 0.42, f"Expected mse to be around 0.4079, but got {mse}."


def test_smoother_is_native_and_behaves_as_moving_average():
    smoother = "/home/user/bin/smoother"
    with open(smoother, "rb") as f:
        assert f.read(4) == b"\x7fELF", "smoother is not a compiled native executable."

    datasets = [
        [(0.0, 3.5), (1.0, -2.0), (2.0, 8.25), (3.0, 1.0), (4.0, 9.0), (5.0, -4.5)],
        [(11.25, 1.1), (12.5, 7.7), (18.0, -3.2), (22.0, 4.4), (31.75, 12.3), (40.0, 0.2), (55.0, 6.6)],
    ]
    for window, rows in zip((3, 7), datasets):
        with tempfile.TemporaryDirectory() as td:
            input_path = os.path.join(td, "input.csv")
            with open(input_path, "w") as f:
                f.write("wavelength,intensity\n")
                for x, y in rows:
                    f.write(f"{x},{y}\n")
            result = subprocess.run(
                [smoother, str(window), input_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
            assert result.stdout == expected_smoothed_bytes(input_path, window)


def test_processed_file_is_actual_window_five_output():
    smoother = "/home/user/bin/smoother"
    raw = "/home/user/data/raw/spectrum.csv"
    processed = "/home/user/data/processed/spectrum_smoothed.csv"
    result = subprocess.run(
        [smoother, "5", raw],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    with open(processed, "rb") as f:
        saved = f.read()
    assert saved == result.stdout, "Processed CSV is not the smoother's current window-5 output."
    assert saved == expected_smoothed_bytes(raw, 5), "Processed CSV does not contain the required moving average."


def test_optimize_performs_complete_grid_search_and_then_real_search():
    script = "/home/user/optimize.sh"
    evaluator = "/home/user/src/eval_mse.py"
    output = "/home/user/best_fit.txt"
    log = "/tmp/grid_search_calls.log"

    subprocess.run(["bash", "-n", script], check=True)

    with open(evaluator, "rb") as f:
        original_evaluator = f.read()
    original_mode = stat.S_IMODE(os.stat(evaluator).st_mode)

    shim = f'''import sys
mu1 = int(sys.argv[2])
mu2 = int(sys.argv[3])
with open({log!r}, "a") as f:
    f.write(f"{{mu1}},{{mu2}}\\n")
value = 0.123456 + ((mu1 - 129) ** 2) * 0.01 + ((mu2 - 347) ** 2) * 0.001
print(f"{{value:.6f}}")
'''

    try:
        with open(evaluator, "w") as f:
            f.write(shim)
        os.chmod(evaluator, original_mode)
        if os.path.exists(log):
            os.unlink(log)
        if os.path.exists(output):
            os.unlink(output)

        subprocess.run(["bash", script], cwd="/home/user", check=True, timeout=60)
        assert os.path.isfile(log), "optimize.sh did not invoke the required evaluator."
        with open(log, "r") as f:
            calls = [tuple(map(int, line.strip().split(','))) for line in f if line.strip()]

        expected_points = {(a, b) for a in range(120, 131) for b in range(340, 351)}
        assert set(calls) == expected_points, "optimize.sh did not evaluate every point in the required grid."
        content, mu1, mu2, _ = parse_best_fit(output)
        assert content == "mu1=129,mu2=347,mse=0.123456"
        assert (mu1, mu2) == (129, 347)
    finally:
        with open(evaluator, "wb") as f:
            f.write(original_evaluator)
        os.chmod(evaluator, original_mode)

    if os.path.exists(output):
        os.unlink(output)
    subprocess.run(["bash", script], cwd="/home/user", check=True, timeout=60)

    processed = "/home/user/data/processed/spectrum_smoothed.csv"
    expected = None
    for mu1 in range(120, 131):
        for mu2 in range(340, 351):
            printed = f"{independently_calculate_mse(processed, mu1, mu2):.6f}"
            candidate = (float(printed), mu1, mu2, printed)
            if expected is None or candidate[0] < expected[0]:
                expected = candidate

    content, mu1, mu2, _ = parse_best_fit(output)
    assert content == f"mu1={expected[1]},mu2={expected[2]},mse={expected[3]}"
    assert (mu1, mu2) == (expected[1], expected[2])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
