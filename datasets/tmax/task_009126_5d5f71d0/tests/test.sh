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
import time

import pytest

SCRIPTS = [
    "/home/user/kde.sh",
    "/home/user/prob.sh",
    "/home/user/analyze.sh",
]


def expected_kde(data, x):
    h = 0.5
    return sum(
        math.exp(-(((x - xi) / h) ** 2) / 2.0) / 2.506628
        for xi in data
    ) / (len(data) * h)


def expected_prob(data, start, end, steps):
    dx = (end - start) / steps
    return sum(expected_kde(data, start + j * dx) * dx for j in range(steps))


def get_expected_probs():
    expected = {}
    for i in range(1, 5):
        trace_file = f"/home/user/traces/trace_{i}.txt"
        if not os.path.isfile(trace_file):
            continue
        with open(trace_file) as f:
            data = [float(line.strip()) for line in f if line.strip()]
        expected[f"trace_{i}.txt"] = expected_prob(data, 2.0, 5.0, 100)
    return expected


def run(args, timeout=30):
    return subprocess.run(
        args,
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def replace_script(path, contents):
    original = open(path, "rb").read()
    mode = stat.S_IMODE(os.stat(path).st_mode)
    with open(path, "w") as f:
        f.write(contents)
    os.chmod(path, 0o755)
    return original, mode


def restore_script(path, saved):
    contents, mode = saved
    with open(path, "wb") as f:
        f.write(contents)
    os.chmod(path, mode)


def test_scripts_exist_and_executable():
    """Ensure the required scripts exist and are executable."""
    for script in SCRIPTS:
        assert os.path.isfile(script), f"Required script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."


def test_kde_and_prob_on_hidden_input():
    rng = secrets.SystemRandom()
    data = [rng.uniform(-1.0, 9.0) for _ in range(23)]
    x = rng.uniform(0.25, 7.5)

    with tempfile.NamedTemporaryFile(mode="w", delete=False) as f:
        input_path = f.name
        for value in data:
            f.write(f"{value:.10f}\n")

    try:
        result = run(["/home/user/kde.sh", input_path, f"{x:.10f}"])
        assert result.returncode == 0, result.stderr
        try:
            actual_kde = float(result.stdout.strip())
        except ValueError:
            pytest.fail(f"kde.sh did not print one numeric density: {result.stdout!r}")
        assert math.isfinite(actual_kde)
        assert abs(actual_kde - expected_kde(data, x)) <= 0.0002

        start = rng.uniform(-0.25, 1.0)
        end = rng.uniform(5.5, 8.0)
        steps = rng.randrange(31, 58)
        result = run([
            "/home/user/prob.sh", input_path,
            f"{start:.10f}", f"{end:.10f}", str(steps),
        ])
        assert result.returncode == 0, result.stderr
        output = result.stdout.strip()
        assert re.fullmatch(r"-?[0-9]+\.[0-9]{4}", output), (
            f"prob.sh must print only one value rounded to four decimals, got {result.stdout!r}"
        )
        actual_prob = float(output)
        wanted = expected_prob(data, start, end, steps)
        assert abs(actual_prob - wanted) <= 0.0002
    finally:
        os.unlink(input_path)


def test_prob_composes_kde_script():
    log_path = f"/tmp/kde_calls_{secrets.token_hex(8)}"
    saved = replace_script(
        "/home/user/kde.sh",
        "#!/bin/bash\n"
        f"printf '%s\\n' \"$*\" >> {log_path!s}\n"
        "printf '0.25\\n'\n",
    )
    try:
        result = run([
            "/home/user/prob.sh", "/home/user/traces/trace_1.txt",
            "1", "3", "7",
        ])
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == "0.5000", (
            "prob.sh did not integrate values obtained from kde.sh"
        )
        assert os.path.isfile(log_path), "prob.sh never invoked kde.sh"
        with open(log_path) as f:
            calls = [line.strip() for line in f if line.strip()]
        assert len(calls) == 7, f"Expected one kde.sh call per integration step, got {len(calls)}"
        for call in calls:
            assert call.split()[0] == "/home/user/traces/trace_1.txt"
    finally:
        restore_script("/home/user/kde.sh", saved)
        if os.path.exists(log_path):
            os.unlink(log_path)


def verify_parallel_orchestration():
    log_path = f"/tmp/prob_calls_{secrets.token_hex(8)}"
    wrapper = f'''#!/bin/bash
now=$(date +%s%N)
printf 'START %s %s %s %s %s %s\\n' "$$" "$now" "$(basename "$1")" "$2" "$3" "$4" >> "{log_path}"
sleep 1
printf '0.1234\\n'
now=$(date +%s%N)
printf 'END %s %s\\n' "$$" "$now" >> "{log_path}"
'''
    saved = replace_script("/home/user/prob.sh", wrapper)
    try:
        result = run(["/home/user/analyze.sh"])
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(log_path), "analyze.sh did not invoke prob.sh"
        with open(log_path) as f:
            records = [line.strip().split() for line in f if line.strip()]

        starts = [r for r in records if r[0] == "START"]
        ends = [r for r in records if r[0] == "END"]
        assert len(starts) == 4, f"analyze.sh must invoke prob.sh four times, got {len(starts)}"
        assert len(ends) == 4, "analyze.sh returned without waiting for all background jobs"
        assert sorted(r[3] for r in starts) == [f"trace_{i}.txt" for i in range(1, 5)]
        assert all(r[4:] == ["2.0", "5.0", "100"] or r[4:] == ["2", "5", "100"] for r in starts), (
            "analyze.sh used incorrect integration arguments"
        )
        start_times = [int(r[2]) for r in starts]
        end_times = [int(r[2]) for r in ends]
        assert max(start_times) < min(end_times), (
            "prob.sh jobs were not all running concurrently; analyze.sh must use background jobs"
        )
    finally:
        restore_script("/home/user/prob.sh", saved)
        if os.path.exists(log_path):
            os.unlink(log_path)


def test_results_file():
    """Execute analyze.sh, then ensure its generated result has the correct format and values."""
    verify_parallel_orchestration()

    rng = secrets.SystemRandom()
    backup_dir = tempfile.mkdtemp(prefix="trace_backup_")
    trace_paths = [f"/home/user/traces/trace_{i}.txt" for i in range(1, 5)]
    try:
        for path in trace_paths:
            assert os.path.isfile(path), f"Trace file {path} is missing."
            shutil.copy2(path, os.path.join(backup_dir, os.path.basename(path)))
            with open(path, "w") as f:
                for _ in range(50):
                    f.write(f"{rng.uniform(-0.75, 10.0):.10f}\n")

        results_file = "/home/user/results/probs.txt"
        if os.path.exists(results_file):
            os.unlink(results_file)

        result = run(["/home/user/analyze.sh"])
        assert result.returncode == 0, f"analyze.sh failed: {result.stderr}"
        assert os.path.isfile(results_file), f"Results file {results_file} does not exist."

        expected_probs = get_expected_probs()
        assert len(expected_probs) == 4, "Trace files missing, unable to compute expected probabilities."

        with open(results_file) as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]
        assert len(lines) == 4, f"Expected exactly 4 lines in {results_file}, found {len(lines)}."

        parsed_results = {}
        filenames = []
        for line in lines:
            parts = line.split(":")
            assert len(parts) == 2, f"Invalid format in line: '{line}'. Expected 'trace_N.txt: <value>'."
            filename = parts[0].strip()
            filenames.append(filename)
            try:
                val = float(parts[1].strip())
            except ValueError:
                pytest.fail(f"Invalid probability value in line: '{line}'.")
            parsed_results[filename] = val

        assert filenames == sorted(filenames), "Results are not sorted alphabetically by filename."
        assert len(parsed_results) == 4, "Results contain duplicate filenames."

        for filename, expected_val in expected_probs.items():
            assert filename in parsed_results, f"Missing result for {filename}."
            actual_val = parsed_results[filename]
            assert abs(actual_val - expected_val) <= 0.0002, (
                f"Value for {filename} is incorrect. "
                f"Expected approx {expected_val:.4f}, got {actual_val:.4f}."
            )
    finally:
        for path in trace_paths:
            backup = os.path.join(backup_dir, os.path.basename(path))
            if os.path.exists(backup):
                shutil.copy2(backup, path)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
