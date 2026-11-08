#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

CLEANER = "/home/user/cleaner"
SOURCE = "/home/user/clean_artifacts.c"


def run_cleaner(executable, input_lines):
    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "input.csv")
        output_path = os.path.join(td, "output.csv")
        with open(input_path, "w", newline="") as f:
            f.write("\n".join(input_lines) + "\n")
        result = subprocess.run(
            [executable, input_path, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(output_path), "Cleaner did not create its requested output file."
        with open(output_path, "r") as f:
            return f.read().splitlines()


def reference_clean(input_lines):
    output = []
    last_sensor_1 = None
    last_sensor_2 = None
    integer = re.compile(r"^[+-]?\d+$")

    for line in input_lines:
        fields = line.split(",")
        if len(fields) != 4:
            continue
        timestamp, sensor_1_text, sensor_2_text, error_code = fields
        if not integer.fullmatch(timestamp) or not integer.fullmatch(error_code):
            continue

        missing_1 = sensor_1_text in ("", "NaN")
        missing_2 = sensor_2_text in ("", "NaN")
        try:
            sensor_1 = last_sensor_1 if missing_1 else float(sensor_1_text)
            sensor_2 = last_sensor_2 if missing_2 else float(sensor_2_text)
        except ValueError:
            continue
        if sensor_1 is None or sensor_2 is None:
            continue

        if not missing_1:
            last_sensor_1 = sensor_1
        if not missing_2:
            last_sensor_2 = sensor_2

        sensor_1 = min(sensor_1, 150.0)
        sensor_2 = max(sensor_2, -50.0)
        output.append(f"{int(timestamp)},{sensor_1:.2f},{sensor_2:.2f},{int(error_code)}")
    return output


def test_executable_exists():
    assert os.path.isfile(CLEANER), "/home/user/cleaner executable is missing."
    assert os.access(CLEANER, os.X_OK), "/home/user/cleaner is not executable."
    with open(CLEANER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/cleaner is not a compiled executable."


def test_source_exists_and_compiles():
    assert os.path.isfile(SOURCE), "/home/user/clean_artifacts.c is missing."
    with tempfile.TemporaryDirectory() as td:
        compiled = os.path.join(td, "cleaner_from_source")
        result = subprocess.run(
            ["gcc", SOURCE, "-o", compiled],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"clean_artifacts.c does not compile:\n{result.stderr}"


def test_cleaner_on_additional_inputs():
    cases = [
        [
            "timestamp,sensor_1,sensor_2,error_code",
            "9000,NaN,NaN,0",
            "9001,10.25,20.50,0",
            "9002,NaN,,1",
            "9003,151.00,-51.00,2",
            "9004,,30.00,3",
            "9005,40.00,NaN,-2",
            "9006,1.00,2.00,0,extra",
            "bad,1.00,2.00,0",
            "9007,1.00,2.00,bad",
            "9008,149.50,-49.50,4",
        ],
        [
            "1,NaN,NaN,0",
            "2,0.25,-0.25,1",
            "3,,NaN,2",
            "4,250.00,-150.00,3",
            "5,75.00,25.00,4",
            "missing,columns,only",
            "6,NaN,NaN,5",
        ],
    ]

    with tempfile.TemporaryDirectory() as td:
        compiled = os.path.join(td, "cleaner_from_source")
        result = subprocess.run(
            ["gcc", SOURCE, "-o", compiled],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, result.stderr

        for case in cases:
            expected = reference_clean(case)
            assert run_cleaner(CLEANER, case) == expected
            assert run_cleaner(compiled, case) == expected


def test_processed_data_content():
    assert os.path.isfile("/home/user/processed_data.csv"), "/home/user/processed_data.csv is missing."

    expected_lines = [
        "1620000001,120.50,-10.20,0",
        "1620000002,150.00,-50.00,1",
        "1620000003,150.00,15.00,0",
        "1620000004,150.00,15.00,0",
        "1620000006,140.00,0.00,2"
    ]

    with open("/home/user/processed_data.csv", "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_lines, "Processed data does not match the expected output format and rules."


def test_pipeline_script_exists():
    assert os.path.isfile("/home/user/pipeline_test.sh"), "/home/user/pipeline_test.sh is missing."
    assert os.access("/home/user/pipeline_test.sh", os.X_OK), "/home/user/pipeline_test.sh is not executable."


def test_test_result_log():
    assert os.path.isfile("/home/user/test_result.log"), "/home/user/test_result.log is missing."

    with open("/home/user/test_result.log", "r") as f:
        content = f.read().strip()

    assert content == "REPRODUCIBLE", f"Expected 'REPRODUCIBLE' in test_result.log, but got '{content}'"


def test_pipeline_script_actually_runs_cleaner_reproducibly():
    expected_lines = [
        "1620000001,120.50,-10.20,0",
        "1620000002,150.00,-50.00,1",
        "1620000003,150.00,15.00,0",
        "1620000004,150.00,15.00,0",
        "1620000006,140.00,0.00,2",
    ]
    raw = "/home/user/data/raw_experiment.csv"
    artifacts = [
        "/home/user/data/raw_copy.csv",
        "/home/user/run1.csv",
        "/home/user/run2.csv",
        "/home/user/test_result.log",
    ]
    for path in artifacts:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    with tempfile.TemporaryDirectory() as td:
        real_cleaner = os.path.join(td, "real_cleaner")
        call_log = os.path.join(td, "calls.log")
        os.replace(CLEANER, real_cleaner)
        try:
            with open(CLEANER, "w") as f:
                f.write("#!/bin/bash\n")
                f.write(f"printf '%s\\t%s\\n' \"$1\" \"$2\" >> {call_log!r}\n")
                f.write(f"exec {real_cleaner!r} \"$@\"\n")
            os.chmod(CLEANER, 0o755)

            result = subprocess.run(
                ["/bin/bash", "/home/user/pipeline_test.sh"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            assert result.returncode == 0, result.stderr

            assert os.path.isfile(call_log), "pipeline_test.sh did not invoke /home/user/cleaner."
            with open(call_log, "r") as f:
                calls = [line.rstrip("\n") for line in f]
            assert calls == [
                "/home/user/data/raw_experiment.csv\t/home/user/run1.csv",
                "/home/user/data/raw_copy.csv\t/home/user/run2.csv",
            ], "pipeline_test.sh must run cleaner once for each required input/output pair."

            with open(raw, "rb") as f:
                raw_bytes = f.read()
            with open("/home/user/data/raw_copy.csv", "rb") as f:
                assert f.read() == raw_bytes, "raw_copy.csv is not an exact copy of the raw dataset."

            for output in ("/home/user/run1.csv", "/home/user/run2.csv"):
                with open(output, "r") as f:
                    assert f.read().splitlines() == expected_lines
            with open("/home/user/run1.csv", "rb") as f:
                run1 = f.read()
            with open("/home/user/run2.csv", "rb") as f:
                run2 = f.read()
            assert run1 == run2, "The two pipeline runs are not reproducible."
            with open("/home/user/test_result.log", "r") as f:
                assert f.read().strip() == "REPRODUCIBLE"
        finally:
            if os.path.exists(real_cleaner):
                os.replace(real_cleaner, CLEANER)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
