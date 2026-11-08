#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import tempfile


def run_script(argv):
    result = subprocess.run(
        argv,
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"Command {argv!r} failed with status {result.returncode}: "
        f"{result.stderr}"
    )
    assert re.fullmatch(r"-?\d+\.\d{5}\n?", result.stdout), (
        f"Expected exactly one value with five decimal places, got {result.stdout!r}"
    )
    return result.stdout.strip()


def kl_value(p, q):
    return sum(pi * math.log(pi / qi) for pi, qi in zip(p, q) if pi != 0)


def root_value(divergence):
    lo, hi = 1.0, 2.0
    for _ in range(200):
        mid = (lo + hi) / 2.0
        if mid ** 3 - mid - divergence < 0:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def expected_kl(p, q):
    return f"{kl_value(p, q):.5f}"


def expected_root(p, q):
    return f"{root_value(kl_value(p, q)):.5f}"


def test_calc_kl_script_exists_and_executable():
    script_path = "/home/user/calc_kl.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_find_root_script_exists_and_executable():
    script_path = "/home/user/find_root.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_kl_out_content():
    out_path = "/home/user/kl_out.txt"
    assert os.path.isfile(out_path), f"Output file {out_path} is missing."
    with open(out_path, "r") as f:
        content = f.read().strip()
    assert content == "0.05754", (
        f"Expected KL divergence output to be '0.05754', got '{content}'."
    )


def test_root_out_content():
    out_path = "/home/user/root_out.txt"
    assert os.path.isfile(out_path), f"Output file {out_path} is missing."
    with open(out_path, "r") as f:
        content = f.read().strip()
    assert content == "1.02761", (
        f"Expected root output to be '1.02761', got '{content}'."
    )


def test_calc_kl_executes_on_its_arguments():
    cases = [
        ([0.5, 0.5], [0.25, 0.75]),
        ([0.1, 0.2, 0.3, 0.4], [0.25, 0.25, 0.25, 0.25]),
    ]
    with tempfile.TemporaryDirectory() as tmp:
        for index, (p, q) in enumerate(cases):
            p_path = os.path.join(tmp, f"P{index}.txt")
            q_path = os.path.join(tmp, f"Q{index}.txt")
            with open(p_path, "w") as f:
                f.write("".join(f"{value}\n" for value in p))
            with open(q_path, "w") as f:
                f.write("".join(f"{value}\n" for value in q))
            actual = run_script(["/home/user/calc_kl.sh", p_path, q_path])
            assert actual == expected_kl(p, q), (
                f"Incorrect KL result for P={p}, Q={q}: got {actual}"
            )


def test_scripts_execute_correctly_on_supplied_data():
    p = [0.2, 0.2, 0.2, 0.2, 0.2]
    q = [0.1, 0.2, 0.3, 0.2, 0.2]
    assert run_script([
        "/home/user/calc_kl.sh", "/home/user/P.txt", "/home/user/Q.txt"
    ]) == expected_kl(p, q)
    assert run_script(["/home/user/find_root.sh"]) == expected_root(p, q)


def test_find_root_uses_the_distribution_data():
    p_path = "/home/user/P.txt"
    q_path = "/home/user/Q.txt"
    with open(p_path, "rb") as f:
        original_p = f.read()
    with open(q_path, "rb") as f:
        original_q = f.read()

    cases = [
        ([0.5, 0.5], [0.4, 0.6]),
        ([0.1, 0.2, 0.3, 0.4], [0.25, 0.25, 0.25, 0.25]),
    ]
    try:
        for p, q in cases:
            with open(p_path, "w") as f:
                f.write("".join(f"{value}\n" for value in p))
            with open(q_path, "w") as f:
                f.write("".join(f"{value}\n" for value in q))
            actual = run_script(["/home/user/find_root.sh"])
            assert actual == expected_root(p, q), (
                f"Incorrect root for P={p}, Q={q}: got {actual}"
            )
    finally:
        with open(p_path, "wb") as f:
            f.write(original_p)
        with open(q_path, "wb") as f:
            f.write(original_q)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
