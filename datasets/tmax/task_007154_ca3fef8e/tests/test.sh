#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile
import pytest

PIPELINE_SCRIPT = "/home/user/pipeline.sh"
PROCESSOR_CODE = "/home/user/processor.c"
PROCESSOR_BIN = "/home/user/processor"
INPUT_FILE = "/home/user/data/raw_logs.csv"
OUTPUT_FILE = "/home/user/sampled_metrics.csv"


def read_output(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return [line.strip() for line in f if line.strip()]
    except UnicodeDecodeError:
        pytest.fail(f"Failed to decode {path} as UTF-8. The output must be valid UTF-8.")


def run_pipeline():
    try:
        return subprocess.run(
            [PIPELINE_SCRIPT],
            check=True,
            capture_output=True,
            text=True,
            timeout=20,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Execution of {PIPELINE_SCRIPT} failed with return code {e.returncode}.\n"
            f"Stdout: {e.stdout}\nStderr: {e.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {PIPELINE_SCRIPT} timed out.")


def expected_output(rows):
    pattern = re.compile(r"ERR-[A-Z]{3}-[0-9]{2}")
    recent = []
    status_counts = {}
    result = []

    for row_id, status, response, message in rows:
        if not pattern.search(message):
            continue
        recent.append(response)
        recent = recent[-3:]
        average = sum(recent) // len(recent)
        count = status_counts.get(status, 0)
        status_counts[status] = count + 1
        if count < 2:
            result.append(f"{status},{response},{average},{message}")
    return result


def make_case(case_number):
    statuses = random.sample(range(410, 590), 4)
    a, b, c, other = map(str, statuses)
    responses = random.sample(range(71, 1900), 9)
    nonce = random.randint(100000, 999999)
    rows = [
        (1, a, responses[0], f"défaut {nonce} ERR-SYS-01 démarrage"),
        (2, other, responses[1], "réponse normale sans erreur"),
        (3, b, responses[2], "échec ERR-DBX-99 après connexion"),
        (4, a, responses[3], "préfixe-ERR-NET-42-suffixe"),
        (5, a, responses[4], "troisième ERR-APP-07 occurrence non imprimée"),
        (6, b, responses[5], "deuxième ERR-CPU-88 résultat"),
        (7, c, responses[6], "façade ERR-IOX-10 très lente"),
        (8, other, responses[7], "invalide ERR-abC-12 et ERR-ABCD-12"),
        (9, a, responses[8], f"quatrième ERR-RAM-{case_number + 20:02d} toujours filtrée"),
    ]
    return rows


def rows_as_csv(rows):
    return "".join(f"{row_id},{status},{response},{message}\n" for row_id, status, response, message in rows)


def test_files_exist():
    assert os.path.exists(PIPELINE_SCRIPT), f"Missing bash script: {PIPELINE_SCRIPT}"
    assert os.path.isfile(PIPELINE_SCRIPT), f"{PIPELINE_SCRIPT} is not a file."
    assert os.path.exists(PROCESSOR_CODE), f"Missing C program: {PROCESSOR_CODE}"
    assert os.path.isfile(PROCESSOR_CODE), f"{PROCESSOR_CODE} is not a file."


def test_pipeline_executable():
    assert os.access(PIPELINE_SCRIPT, os.X_OK), f"The script {PIPELINE_SCRIPT} is not executable."


def test_pipeline_execution():
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    run_pipeline()
    assert os.path.exists(OUTPUT_FILE), f"The script did not generate {OUTPUT_FILE}."


def test_output_content():
    assert os.path.exists(OUTPUT_FILE), f"Cannot verify content, {OUTPUT_FILE} is missing."
    lines = read_output(OUTPUT_FILE)
    expected_lines = [
        "500,100,100,défaut ERR-SYS-01 system down",
        "500,200,150,erreur ERR-DBX-99 timeout",
        "502,300,200,fatal ERR-NET-42 connection lost",
        "502,500,400,critique ERR-NET-99 routing failed",
    ]
    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in output, but got {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i + 1}.\nExpected: {expected}\nActual:   {actual}"


def test_required_c_and_pipeline_features_present():
    with open(PROCESSOR_CODE, "r", encoding="utf-8", errors="replace") as f:
        c_source = f.read()
    assert re.search(r"#\s*include\s*[<\"]regex\.h[>\"]", c_source), "processor.c must include regex.h."
    assert "regcomp" in c_source and "regexec" in c_source, "processor.c must use POSIX regex compilation and matching."
    assert "REG_EXTENDED" in c_source, "processor.c must use POSIX extended regular expressions."

    with open(PIPELINE_SCRIPT, "r", encoding="utf-8", errors="replace") as f:
        script = f.read()
    assert re.search(r"\bgcc\b", script), "pipeline.sh must invoke gcc."
    assert "-O2" in script, "pipeline.sh must compile with -O2."


def test_processor_and_pipeline_on_derived_inputs():
    with tempfile.TemporaryDirectory() as td:
        test_binary = os.path.join(td, "processor_test")
        compiled = subprocess.run(
            ["gcc", "-O2", PROCESSOR_CODE, "-o", test_binary],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compiled.returncode == 0, f"processor.c did not compile.\nStdout: {compiled.stdout}\nStderr: {compiled.stderr}"

        original_input = open(INPUT_FILE, "rb").read()
        try:
            for case_number in range(2):
                rows = make_case(case_number)
                csv_utf8 = rows_as_csv(rows)
                expected = expected_output(rows)

                direct = subprocess.run(
                    [test_binary],
                    input=csv_utf8,
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                assert direct.returncode == 0, f"Compiled processor failed: {direct.stderr}"
                assert [line.strip() for line in direct.stdout.splitlines() if line.strip()] == expected

                with open(INPUT_FILE, "wb") as f:
                    f.write(csv_utf8.encode("iso-8859-1"))
                for path in (OUTPUT_FILE, PROCESSOR_BIN):
                    if os.path.exists(path):
                        os.remove(path)

                run_pipeline()
                assert os.path.isfile(OUTPUT_FILE), "pipeline.sh did not create sampled_metrics.csv."
                assert read_output(OUTPUT_FILE) == expected
                assert os.path.isfile(PROCESSOR_BIN), "pipeline.sh did not create the processor executable."
                assert os.access(PROCESSOR_BIN, os.X_OK), "The generated processor is not executable."
                with open(PROCESSOR_BIN, "rb") as f:
                    assert f.read(4) == b"\x7fELF", "The generated processor is not a compiled ELF executable."

                generated = subprocess.run(
                    [PROCESSOR_BIN],
                    input=csv_utf8,
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                assert generated.returncode == 0, f"Pipeline-generated processor failed: {generated.stderr}"
                assert [line.strip() for line in generated.stdout.splitlines() if line.strip()] == expected
        finally:
            with open(INPUT_FILE, "wb") as f:
                f.write(original_input)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
