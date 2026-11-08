#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile


def run_checked(cmd, timeout=15):
    return subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=True,
    )


def parse_update_rate(path):
    with open(path, "r") as f:
        content = f.read()
    match = re.search(r"^\s*#\s*define\s+UPDATE_RATE\s+([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\b", content, re.MULTILINE)
    assert match, f"Could not derive UPDATE_RATE from {path}."
    return float(match.group(1))


def expected_mre_output(rate):
    x = 10.0
    for _ in range(10):
        x = x - rate * x
    return f"{x:.2f}\n"


def test_mre_c_exists_and_correct():
    path = "/home/user/app/mre.c"
    assert os.path.isfile(path), f"MRE file {path} is missing."
    with open(path, "r") as f:
        content = f.read()

    assert "<calc_utils.h>" in content, f"{path} is missing <calc_utils.h> include."
    assert "<stdio.h>" in content, f"{path} is missing <stdio.h> include."
    assert "main" in content, f"{path} is missing main function."
    assert "10.0" in content, f"{path} does not initialize x to 10.0."
    assert "10" in content, f"{path} does not seem to have a 10-iteration loop."
    assert "UPDATE_RATE" in content, f"{path} does not use UPDATE_RATE."
    assert "%.2f" in content, f"{path} does not print to 2 decimal places."


def test_build_sh_fixed():
    path = "/home/user/app/build.sh"
    assert os.path.isfile(path), f"Build script {path} is missing."
    with open(path, "r") as f:
        content = f.read()

    idx_v2 = content.find("-I/home/user/app/deps/v2")
    idx_v1 = content.find("-I/home/user/app/deps/v1")

    assert idx_v2 != -1, f"{path} must include deps/v2."

    if idx_v1 != -1:
        assert idx_v2 < idx_v1, f"In {path}, deps/v2 must be prioritized over deps/v1."


def test_solution_txt_correct():
    path = "/home/user/app/solution.txt"
    assert os.path.isfile(path), f"Solution file {path} is missing."
    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"{path} must contain at least two lines."
    assert lines[0] == "Converged value: 0.000000", f"First line of {path} is incorrect. Expected 'Converged value: 0.000000'."
    assert lines[1] == "v1", f"Second line of {path} is incorrect. Expected 'v1'."


def test_mre_compiles_and_reproduces_broken_headers():
    source = "/home/user/app/mre.c"
    with tempfile.TemporaryDirectory() as td:
        binary = os.path.join(td, "mre")
        run_checked([
            "gcc",
            "-I/home/user/app/deps/v1",
            "-I/home/user/app/deps/v2",
            source,
            "-o",
            binary,
        ])
        result = run_checked([binary])

    rate = parse_update_rate("/home/user/app/deps/v1/calc_utils.h")
    assert result.stderr == "", f"MRE wrote unexpected stderr: {result.stderr!r}"
    assert result.stdout == expected_mre_output(rate), "MRE does not perform the required ten UPDATE_RATE iterations."
    assert abs(float(result.stdout.strip())) > 10.0, "MRE did not reproduce divergence with the broken include order."


def test_mre_behavior_uses_header_macro_for_exactly_ten_iterations():
    source = "/home/user/app/mre.c"
    rates = secrets.SystemRandom().sample(
        [0.13, 0.27, 0.41, 0.63, 0.78, 1.17, 1.36, 1.71, 1.89], 3
    )

    for rate in rates:
        with tempfile.TemporaryDirectory() as td:
            header = os.path.join(td, "calc_utils.h")
            binary = os.path.join(td, "mre")
            with open(header, "w") as f:
                f.write(f"#ifndef CALC_UTILS_H\n#define CALC_UTILS_H\n#define UPDATE_RATE {rate:.17g}\n#endif\n")
            run_checked(["gcc", "-I" + td, source, "-o", binary])
            result = run_checked([binary])

        assert result.stderr == "", f"MRE wrote unexpected stderr for UPDATE_RATE={rate}: {result.stderr!r}"
        assert result.stdout == expected_mre_output(rate), (
            f"MRE output is wrong for verifier-supplied UPDATE_RATE={rate}; "
            "it must initialize x to 10.0 and apply the update exactly ten times."
        )


def test_build_script_rebuilds_working_sim_and_solution_matches_it():
    build = "/home/user/app/build.sh"
    sim = "/home/user/app/sim"
    source = "/home/user/app/src/sim.c"
    solution = "/home/user/app/solution.txt"

    assert os.access(build, os.X_OK), f"Build script {build} is not executable."

    with tempfile.TemporaryDirectory() as td:
        reference = os.path.join(td, "reference_sim")
        run_checked([
            "gcc",
            "-I/home/user/app/deps/v2",
            "-I/home/user/app/deps/v1",
            source,
            "-o",
            reference,
        ])
        expected = run_checked([reference]).stdout

    if os.path.lexists(sim):
        os.remove(sim)
    run_checked([build], timeout=20)

    assert os.path.isfile(sim), "build.sh did not create /home/user/app/sim."
    assert os.access(sim, os.X_OK), "/home/user/app/sim is not executable."
    with open(sim, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/app/sim is not a compiled ELF binary."

    result = run_checked([sim])
    assert result.stderr == "", f"sim wrote unexpected stderr: {result.stderr!r}"
    assert result.stdout == expected, "The rebuilt sim does not behave like sim.c compiled with deps/v2 prioritized."
    assert result.stdout == "Converged value: 0.000000\n", "The rebuilt simulation did not converge successfully."

    with open(solution, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines[0] == result.stdout.strip(), "The first line of solution.txt is not the actual rebuilt sim output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
