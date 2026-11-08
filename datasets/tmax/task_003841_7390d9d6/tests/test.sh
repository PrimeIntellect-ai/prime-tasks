#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess

HOME = "/home/user"
EXPECTED = "2.0030,1.0233"


def require_file(path):
    assert os.path.isfile(path), f"File {path} is missing."


def run_test_script():
    subprocess.run(
        ["bash", os.path.join(HOME, "test.sh")],
        cwd=HOME,
        check=True,
        timeout=30,
    )


def read_exact(path):
    require_file(path)
    with open(path, "r") as f:
        return f.read().strip()


def assert_original_outputs():
    gd = read_exact(os.path.join(HOME, "gd_result.txt"))
    assert gd == EXPECTED, (
        f"Content of /home/user/gd_result.txt is incorrect. "
        f"Expected '{EXPECTED}', got '{gd}'."
    )

    analytical = read_exact(os.path.join(HOME, "analytical_result.txt"))
    assert analytical == EXPECTED, (
        f"Content of /home/user/analytical_result.txt is incorrect. "
        f"Expected '{EXPECTED}', got '{analytical}'."
    )

    log = read_exact(os.path.join(HOME, "regression.log"))
    assert log == "PASS", (
        f"Content of /home/user/regression.log is incorrect. "
        f"Expected 'PASS', got '{log}'."
    )


def parse_result(path):
    content = read_exact(path)
    assert re.fullmatch(r"-?(?:\d+\.\d{4}),-?(?:\d+\.\d{4})", content), (
        f"{path} must contain exactly w,b rounded to four decimal places; got {content!r}."
    )
    return content


def expected_values(xs, ys):
    n = len(xs)
    mean_x = sum(xs) / n
    mean_y = sum(ys) / n
    variance_sum = sum((x - mean_x) ** 2 for x in xs)
    assert variance_sum != 0
    w_exact = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / variance_sum
    b_exact = mean_y - w_exact * mean_x

    w = 0.0
    b = 0.0
    for _ in range(500):
        errors = [w * x + b - y for x, y in zip(xs, ys)]
        dw = 2.0 * sum(e * x for e, x in zip(errors, xs)) / n
        db = 2.0 * sum(errors) / n
        w -= 0.5 * dw
        b -= 0.5 * db

    return f"{w:.4f},{b:.4f}", f"{w_exact:.4f},{b_exact:.4f}"


def test_complete_behavior():
    gd_awk = os.path.join(HOME, "gd.awk")
    analytical_awk = os.path.join(HOME, "analytical.awk")
    test_sh = os.path.join(HOME, "test.sh")
    x_csv = os.path.join(HOME, "X.csv")
    y_csv = os.path.join(HOME, "Y.csv")

    # Preserve the original existence assertions.
    require_file(gd_awk)
    require_file(analytical_awk)
    require_file(test_sh)

    # The submitted regression test must actually generate the original outputs.
    run_test_script()
    assert_original_outputs()

    backups = {}
    paths = [gd_awk, analytical_awk, x_csv, y_csv]
    for path in paths:
        backup = path + ".verifier_backup"
        shutil.copy2(path, backup)
        backups[path] = backup

    gd_marker = "/tmp/verifier_gd_ran"
    analytical_marker = "/tmp/verifier_analytical_ran"

    try:
        for marker in (gd_marker, analytical_marker):
            try:
                os.remove(marker)
            except FileNotFoundError:
                pass

        # Instrument each AWK source with a harmless BEGIN rule. A marker is only
        # produced if test.sh really loads that source through an AWK interpreter.
        with open(gd_awk, "r") as f:
            gd_source = f.read()
        with open(gd_awk, "w") as f:
            f.write(f'BEGIN {{ print "ran" > "{gd_marker}"; close("{gd_marker}") }}\n')
            f.write(gd_source)

        with open(analytical_awk, "r") as f:
            analytical_source = f.read()
        with open(analytical_awk, "w") as f:
            f.write(f'BEGIN {{ print "ran" > "{analytical_marker}"; close("{analytical_marker}") }}\n')
            f.write(analytical_source)

        # This centered, low-variance challenge distinguishes the specified
        # 500-step gradient descent result from the analytical result while
        # keeping their difference below the required regression threshold.
        xs = [-0.15, -0.12, -0.09, -0.05, -0.02, 0.02, 0.05, 0.09, 0.12, 0.15]
        ys = [0.7 + 0.8 * x for x in xs]
        with open(x_csv, "w") as f:
            f.write("".join(f"{x:.2f}\n" for x in xs))
        with open(y_csv, "w") as f:
            f.write("".join(f"{y:.6f}\n" for y in ys))

        expected_gd, expected_analytical = expected_values(xs, ys)
        run_test_script()

        assert os.path.isfile(gd_marker), "test.sh did not execute /home/user/gd.awk with awk."
        assert os.path.isfile(analytical_marker), "test.sh did not execute /home/user/analytical.awk with awk."

        actual_gd = parse_result(os.path.join(HOME, "gd_result.txt"))
        actual_analytical = parse_result(os.path.join(HOME, "analytical_result.txt"))
        assert actual_gd == expected_gd, (
            f"Gradient descent failed on verifier data: expected {expected_gd}, got {actual_gd}."
        )
        assert actual_analytical == expected_analytical, (
            f"Analytical regression failed on verifier data: expected {expected_analytical}, "
            f"got {actual_analytical}."
        )
        assert read_exact(os.path.join(HOME, "regression.log")) == "PASS", (
            "test.sh did not write PASS when both parameter differences were below 0.01."
        )
    finally:
        for path, backup in backups.items():
            if os.path.exists(backup):
                shutil.move(backup, path)

    # Restore and retain the original verifier's final-state assertions.
    run_test_script()
    assert_original_outputs()
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
