#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess

SOURCE = "/home/user/biomodel.c"
PIPELINE = "/home/user/pipeline.sh"
BINARY = "/home/user/biomodel"
RESULT = "/home/user/result.txt"
ALPHABET = "ACGT"


def expected_value(target, primer, initial_x=1.0):
    occurrences = sum(
        target[i:i + len(primer)] == primer
        for i in range(len(target) - len(primer) + 1)
    )
    k = occurrences * 2.0
    x = initial_x
    y = 0.0
    for _ in range(10000):
        dx = y
        dy = -k * x - 0.5 * y
        x += dx * 0.001
        y += dy * 0.001
    return f"{x:.4f}"


def read_result():
    assert os.path.isfile(RESULT), f"File {RESULT} does not exist."
    with open(RESULT, "rb") as f:
        data = f.read()
    assert re.fullmatch(rb"[+-]?\d+\.\d{4}\n?", data), \
        f"result.txt must contain only one numeric value with four decimal places, got {data!r}"
    return data.decode().strip()


def random_cases(count=7):
    cases = []
    for _ in range(count):
        primer = "".join(secrets.choice(ALPHABET) for _ in range(1 + secrets.randbelow(4)))
        left = "".join(secrets.choice(ALPHABET) for _ in range(4 + secrets.randbelow(9)))
        right = "".join(secrets.choice(ALPHABET) for _ in range(4 + secrets.randbelow(9)))
        target = left + primer * (1 + secrets.randbelow(5)) + right
        cases.append((target, primer))
    # Include a dynamically generated likely-zero-occurrence case as well.
    absent_base = secrets.choice(ALPHABET)
    other = next(c for c in ALPHABET if c != absent_base)
    cases.append((absent_base * (8 + secrets.randbelow(12)), other * (1 + secrets.randbelow(3))))
    return cases


def run_fresh_pipeline(target, primer):
    if os.path.lexists(BINARY):
        os.unlink(BINARY)
    result = subprocess.run(
        ["bash", PIPELINE, target, primer], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"pipeline.sh failed with error: {result.stderr}"
    assert os.path.isfile(BINARY), "pipeline.sh did not create /home/user/biomodel"
    assert os.stat(BINARY).st_mode & stat.S_IXUSR, "/home/user/biomodel is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/biomodel is not a compiled ELF executable"
    return read_result()


def test_biomodel_c_fixed():
    assert os.path.isfile(SOURCE), f"File {SOURCE} does not exist."
    with open(SOURCE, "r") as f:
        content = f.read()

    # Preserve the original assertion and additionally verify the actual assignments.
    assert "0.001" in content, "The integration time step dt was not changed to 0.001 in biomodel.c."
    assert re.search(r"\bdouble\s+dt\s*=\s*0\.0010*\s*;", content), \
        "biomodel.c does not assign dt the value 0.001."
    assert re.search(r"\bdouble\s+T\s*=\s*10(?:\.0*)?\s*;", content), \
        "biomodel.c must retain total simulation time T = 10.0."
    assert re.search(r"\bint\s+steps\s*=", content), \
        "biomodel.c does not define the integration step count."


def test_pipeline_sh_exists_and_works():
    assert os.path.isfile(PIPELINE), f"File {PIPELINE} does not exist."

    # Preserve the prompt's original fixed test and expected assertion.
    target = "ACGTACGTACGT"
    primer = "ACGT"
    result = subprocess.run(["bash", PIPELINE, target, primer], capture_output=True, text=True)
    assert result.returncode == 0, f"pipeline.sh failed with error: {result.stderr}"
    result_content = read_result()
    assert result_content == "-0.0195", \
        f"Expected result.txt to contain exactly '-0.0195', but got '{result_content}'"


def test_pipeline_is_dynamic_original_case():
    target = "AAAA"
    primer = "A"
    expected_output = expected_value(target, primer)
    subprocess.run(["bash", PIPELINE, target, primer], capture_output=True, text=True)
    result_content = read_result()
    assert result_content == expected_output, \
        f"Expected result.txt to contain '{expected_output}' for inputs {target} {primer}, but got '{result_content}'. The script might be hardcoded."


def test_compiled_source_on_unpredictable_inputs():
    # Compile the submitted C source independently and exercise inputs generated only
    # at verification time. This checks the actual dt/step behavior rather than text alone.
    checked_binary = "/tmp/checked_biomodel"
    build = subprocess.run(
        ["gcc", SOURCE, "-o", checked_binary], capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, f"biomodel.c failed to compile: {build.stderr}"

    for target, primer in random_cases():
        expected = expected_value(target, primer)
        run = subprocess.run(
            [checked_binary, target, primer], capture_output=True, text=True, timeout=30
        )
        assert run.returncode == 0, f"Compiled biomodel failed: {run.stderr}"
        assert run.stdout.strip().splitlines()[-1] == expected, \
            f"Compiled biomodel produced the wrong t=10 result for {target!r}, {primer!r}."


def test_pipeline_compiles_and_runs_current_source_dynamically():
    assert os.path.isfile(PIPELINE), f"File {PIPELINE} does not exist."

    cases = random_cases()
    for target, primer in cases:
        expected = expected_value(target, primer)
        result_content = run_fresh_pipeline(target, primer)
        assert result_content == expected, \
            f"Wrong pipeline result for unpredictable inputs {target!r}, {primer!r}: expected {expected}, got {result_content}"

        direct = subprocess.run(
            [BINARY, target, primer], capture_output=True, text=True, timeout=30
        )
        assert direct.returncode == 0, f"Generated biomodel executable failed: {direct.stderr}"
        assert direct.stdout.strip().splitlines()[-1] == expected, \
            "The executable created by pipeline.sh does not produce the required result."


def test_pipeline_really_uses_current_biomodel_source():
    # Temporarily apply an unpredictable, reversible change to the model's initial
    # state. A pipeline that compiles and executes the current source must reflect it.
    with open(SOURCE, "r") as f:
        original = f.read()

    initial_text = f"{1 + secrets.randbelow(800000) / 1000000:.6f}"
    pattern = re.compile(r"(\bdouble\s+x\s*=\s*)1(?:\.0*)?(\s*;)")
    instrumented, replacements = pattern.subn(r"\g<1>" + initial_text + r"\g<2>", original, count=1)
    assert replacements == 1, "Could not identify the model's initial x assignment."

    primer = "".join(secrets.choice(ALPHABET) for _ in range(3))
    target = (
        "".join(secrets.choice(ALPHABET) for _ in range(7))
        + primer * (2 + secrets.randbelow(4))
        + "".join(secrets.choice(ALPHABET) for _ in range(7))
    )

    try:
        with open(SOURCE, "w") as f:
            f.write(instrumented)

        expected = expected_value(target, primer, float(initial_text))
        result_content = run_fresh_pipeline(target, primer)
        assert result_content == expected, \
            "pipeline.sh did not compile and execute the current /home/user/biomodel.c source."

        with open(SOURCE, "r") as f:
            assert f.read() == instrumented, "pipeline.sh unexpectedly replaced biomodel.c."

        direct = subprocess.run([BINARY, target, primer], capture_output=True, text=True, timeout=30)
        assert direct.returncode == 0
        assert direct.stdout.strip().splitlines()[-1] == expected, \
            "The biomodel executable created by pipeline.sh does not match the current source."
    finally:
        with open(SOURCE, "w") as f:
            f.write(original)
        subprocess.run(["bash", PIPELINE, "ACGTACGTACGT", "ACGT"], capture_output=True, text=True)


def test_pipeline_requires_exactly_two_arguments():
    for args in ([], ["ACGT"], ["ACGT", "AC", "extra"]):
        result = subprocess.run(["bash", PIPELINE, *args], capture_output=True, text=True, timeout=30)
        assert result.returncode != 0, "pipeline.sh must reject calls that do not have exactly two arguments."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
