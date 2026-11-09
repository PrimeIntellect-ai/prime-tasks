#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import shutil
import stat
import subprocess
import tempfile


def run_checked(path):
    return subprocess.run([path], capture_output=True, text=True, check=True, timeout=15)


def reference_slope(rows):
    awk_program = r'''{
        sum_x+=$1; sum_y+=$2; sum_xy+=$1*$2; sum_xx+=$1*$1; n++
    } END {
        slope=(n*sum_xy - sum_x*sum_y)/(n*sum_xx - sum_x*sum_x);
        printf "%.5f\n", slope
    }'''
    payload = "".join(f"{x},{y}\n" for x, y in rows)
    result = subprocess.run(
        ["gawk", "-F,", awk_program],
        input=payload,
        capture_output=True,
        text=True,
        check=True,
        timeout=10,
    )
    return result.stdout.strip()


def python_slope(rows):
    sx = sy = sxy = sxx = 0.0
    for x_text, y_text in rows:
        x = float(x_text)
        y = float(y_text)
        sx += x
        sy += y
        sxy += x * y
        sxx += x * x
    n = float(len(rows))
    denominator = n * sxx - sx * sx
    if denominator == 0.0:
        return None
    value = (n * sxy - sx * sy) / denominator
    if not math.isfinite(value):
        return None
    return format(value, ".5f")


def make_order_sensitive_dataset():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    names = [f"trial_{letter}.csv" for letter in "ABCDEF"]

    for _ in range(20000):
        files = {}
        for name in names:
            rows = []
            for __ in range(4):
                x = 100000000 + rng.randint(-1000, 1000)
                y = 2.3 * x + rng.randint(-5000, 5000) + rng.random()
                rows.append((str(x), f"{y:.6f}"))
            files[name] = rows

        sorted_rows = [row for name in sorted(names) for row in files[name]]
        reverse_rows = [row for name in reversed(sorted(names)) for row in files[name]]
        a = python_slope(sorted_rows)
        b = python_slope(reverse_rows)
        if a is None or b is None or a == b:
            continue

        try:
            expected = reference_slope(sorted_rows)
            reverse_expected = reference_slope(reverse_rows)
        except subprocess.CalledProcessError:
            continue
        if expected != reverse_expected:
            return files, expected

    raise AssertionError("Could not construct an order-sensitive regression dataset")


def install_dataset(data_path, files, creation_order):
    shutil.rmtree(data_path)
    os.mkdir(data_path)
    for name in creation_order:
        with open(os.path.join(data_path, name), "w") as f:
            f.write("x,y\n")
            for x, y in files[name]:
                f.write(f"{x},{y}\n")


def test_complete_task():
    process_path = "/home/user/process_binding.sh"
    hypothesis_path = "/home/user/test_hypothesis.sh"
    result_path = "/home/user/result.txt"
    data_path = "/home/user/data"

    # Preserve the original verifier's assertions.
    assert os.path.isfile(process_path), f"Script {process_path} is missing."
    assert os.access(process_path, os.X_OK), f"Script {process_path} is not executable."
    with open(process_path, "r") as f:
        process_content = f.read()
    assert "sort" in process_content or "ls " in process_content or "*.csv" in process_content.replace('"', ''), \
        f"Script {process_path} does not seem to contain sorting logic (e.g., 'sort')."

    result = run_checked(process_path)
    assert result.stdout.strip() == "1.18571", \
        f"Expected script to output '1.18571', but got {result.stdout.strip()!r}"

    assert os.path.isfile(hypothesis_path), f"Script {hypothesis_path} is missing."
    assert os.access(hypothesis_path, os.X_OK), f"Script {hypothesis_path} is not executable."
    assert os.path.isfile(result_path), f"File {result_path} is missing."
    with open(result_path, "r") as f:
        content = f.read()
    assert content == "H0: Weak Binding\n", \
        f"Expected result.txt to contain exactly 'H0: Weak Binding\\n', but got {content!r}"

    backup_root = tempfile.mkdtemp(prefix="binding-verifier-")
    data_backup = os.path.join(backup_root, "data")
    process_backup = os.path.join(backup_root, "process_binding.sh")
    result_backup = os.path.join(backup_root, "result.txt")
    shutil.copytree(data_path, data_backup)
    shutil.copy2(process_path, process_backup)
    had_result = os.path.exists(result_path)
    if had_result:
        shutil.copy2(result_path, result_backup)

    try:
        # Exercise process_binding.sh on a newly generated dataset for which
        # alphabetical and reverse file orders produce different awk results.
        files, expected = make_order_sensitive_dataset()
        names = sorted(files)
        for creation_order in (list(reversed(names)), names):
            install_dataset(data_path, files, creation_order)
            observed = run_checked(process_path).stdout.strip()
            assert observed == expected, (
                "process_binding.sh did not produce the regression result obtained "
                f"from strict alphabetical filename order: expected {expected!r}, got {observed!r}"
            )

        # Verify that test_hypothesis.sh really executes process_binding.sh and
        # classifies its captured value, including the equality boundary.
        marker = os.path.join(backup_root, "process-was-run")
        cases = [
            ("1.50000", "H1: Strong Binding\n"),
            ("1.49999", "H0: Weak Binding\n"),
            (f"{random.uniform(1.6, 9.0):.6f}", "H1: Strong Binding\n"),
            (f"{random.uniform(-3.0, 1.4):.6f}", "H0: Weak Binding\n"),
        ]
        random.SystemRandom().shuffle(cases)

        for slope, expected_hypothesis in cases:
            with open(process_path, "w") as f:
                f.write("#!/bin/bash\n")
                f.write(f"printf x >> {marker!r}\n")
                f.write(f"printf '%s\\n' {slope!r}\n")
            os.chmod(process_path, 0o755)
            if os.path.exists(marker):
                os.unlink(marker)
            if os.path.exists(result_path):
                os.unlink(result_path)

            run_checked(hypothesis_path)
            assert os.path.isfile(marker), \
                "test_hypothesis.sh did not execute /home/user/process_binding.sh"
            assert os.path.isfile(result_path), \
                "test_hypothesis.sh did not generate /home/user/result.txt"
            with open(result_path, "r") as f:
                observed = f.read()
            assert observed == expected_hypothesis, (
                f"For slope {slope}, expected {expected_hypothesis!r}, got {observed!r}"
            )
    finally:
        if os.path.exists(data_path):
            shutil.rmtree(data_path)
        shutil.copytree(data_backup, data_path)
        shutil.copy2(process_backup, process_path)
        if had_result:
            shutil.copy2(result_backup, result_path)
        elif os.path.exists(result_path):
            os.unlink(result_path)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
