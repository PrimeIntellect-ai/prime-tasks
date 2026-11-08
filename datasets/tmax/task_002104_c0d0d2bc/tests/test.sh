#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

PIPELINE = "/home/user/pipeline.sh"
SOURCE = "/home/user/classifier.c"
POINTS = "/home/user/points.csv"
RESULTS = "/home/user/results.csv"
STANDALONE = "/tmp/verifier_classifier"


def read_results():
    assert os.path.isfile(RESULTS), f"{RESULTS} was not created."
    with open(RESULTS, "r") as f:
        return [line.strip() for line in f.read().strip().splitlines() if line.strip()]


def assert_results(expected):
    content = read_results()
    assert content == expected, (
        f"Content of {RESULTS} does not match expected output.\n"
        f"Expected: {expected}\nGot: {content}"
    )


def run_program(path):
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    try:
        subprocess.run([path], check=True, cwd="/home/user", capture_output=True,
                       text=True, timeout=15)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of {path} failed.\nStdout: {e.stdout}\nStderr: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {path} timed out.")


def install_input(lines):
    with open(POINTS, "w", newline="") as f:
        f.write("\n".join(lines) + "\n")


def generated_case(rng, count):
    lines = ["id,x,y,z"]
    expected = ["id,class"]
    used = set()

    for _ in range(count):
        ident = rng.randrange(10000, 99999)
        while ident in used:
            ident = rng.randrange(10000, 99999)
        used.add(ident)

        # Tenths are exactly representable enough for this test, and scores are
        # kept away from zero except for the explicit boundary row below.
        while True:
            a = rng.randrange(-90, 91)
            b = rng.randrange(-90, 91)
            c = rng.randrange(-90, 91)
            numerator = 5 * a - 2 * b + c - 50
            if abs(numerator) >= 5:
                break
        x, y, z = a / 10.0, b / 10.0, c / 10.0
        lines.append(f"{ident},{x:.1f},{y:.1f},{z:.1f}")
        expected.append(f"{ident},{1 if numerator > 0 else 0}")

    # A valid score exactly on the decision boundary must be class 0.
    boundary_id = rng.randrange(100000, 999999)
    lines.append(f"{boundary_id},1.0,0.0,0.0")
    expected.append(f"{boundary_id},0")

    # Each of these violates the required four-field numeric schema.
    lines.extend([
        "badid,1.0,2.0,3.0",
        "800001,bad,2.0,3.0",
        "800002,1.0,,3.0",
        "800003,1.0,2.0,",
        "800004,1.0,2.0",
        "800005,1.0,2.0,3.0,4.0",
        "800006,1.0x,2.0,3.0",
        ",1.0,2.0,3.0",
        "",
    ])
    return lines, expected


def test_complete_pipeline_and_classifier():
    # Preserve the original existence and permission assertions.
    assert os.path.isfile(PIPELINE), f"{PIPELINE} does not exist."
    assert os.access(PIPELINE, os.X_OK), f"{PIPELINE} is not executable."
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."

    # Compile classifier.c independently before invoking the submitted pipeline,
    # so pipeline.sh cannot substitute unrelated behavior for defective C code.
    compile_result = subprocess.run(
        ["gcc", SOURCE, "-o", STANDALONE], cwd="/home/user",
        capture_output=True, text=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        "classifier.c did not compile with gcc.\n"
        f"Stdout: {compile_result.stdout}\nStderr: {compile_result.stderr}"
    )
    assert os.path.isfile(STANDALONE) and os.access(STANDALONE, os.X_OK)

    original_lines = [
        "id,x,y,z",
        "1,2.0,1.0,1.0",
        "2,-1.0,2.0,0.5",
        "3,1.5,-0.5,2.0",
        "bad_row,a,b,c",
        "4,0.0,0.0,0.0",
        "5,3.0,1.5,",
        "6,2.0,-3.0,-1.0",
        "7,0.5,0.5,0.5",
    ]
    original_expected = [
        "id,class", "1,1", "2,0", "3,1", "4,0", "6,1", "7,0"
    ]

    rng = random.SystemRandom()
    cases = [(original_lines, original_expected)]
    cases.append(generated_case(rng, 9))
    cases.append(generated_case(rng, 13))

    for lines, expected in cases:
        install_input(lines)

        # Exercise the independently compiled submitted C source.
        run_program(STANDALONE)
        assert_results(expected)

        # Exercise the submitted pipeline from a state with no prior executable.
        if os.path.exists("/home/user/classifier"):
            os.remove("/home/user/classifier")
        run_program(PIPELINE)
        assert_results(expected)

        classifier = "/home/user/classifier"
        assert os.path.isfile(classifier), "pipeline.sh did not create classifier."
        assert os.access(classifier, os.X_OK), "The generated classifier is not executable."
        with open(classifier, "rb") as f:
            assert f.read(4) == b"\x7fELF", "pipeline.sh did not produce a compiled executable."

        # Ensure the executable produced by the pipeline itself performs the work.
        run_program(classifier)
        assert_results(expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
