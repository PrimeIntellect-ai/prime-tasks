#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import csv
import subprocess
import tempfile
from pathlib import Path

SCRIPT_PATH = "/home/user/workflow.sh"


def test_workflow_script_properties():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "xargs" in content or "parallel" in content, (
        "The script must use parallel processing (e.g., xargs or parallel)."
    )

    # Execute the required workflow on the supplied data rather than trusting
    # files that may have been created manually.
    result = subprocess.run(
        [SCRIPT_PATH, "/home/user/raw_data", "/home/user/processed_data"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"workflow.sh failed on the supplied data:\n{result.stderr}"
    )


def process_expected_data(input_path):
    expected_rows = []
    with open(input_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        expected_rows.append(reader.fieldnames)

        for row in reader:
            # 1. Constraint-based Validation & Regex
            if not re.match(r'^\d{3}-\d{2}-\d{4}$', row['SSN']):
                continue

            try:
                age = int(row['Age'])
                if not (0 <= age <= 120):
                    continue
            except ValueError:
                continue

            # 2. Data Masking and Anonymization
            row['Name'] = 'REDACTED'
            row['SSN'] = f"***-**-{row['SSN'][-4:]}"

            # 3. Interpolation and Imputation
            if not row['BloodPressure'].strip():
                row['BloodPressure'] = '120/80'
            if not row['HeartRate'].strip():
                row['HeartRate'] = '72'

            expected_rows.append([row[field] for field in reader.fieldnames])

    return expected_rows


def assert_processed_file(input_file, output_file):
    assert os.path.isfile(output_file), f"Processed file {output_file} is missing."
    expected_data = process_expected_data(input_file)
    with open(output_file, "r", newline="") as f:
        actual_data = list(csv.reader(f))
    assert actual_data == expected_data, (
        f"Data in {output_file} does not match the expected processed output."
    )


def test_processed_data_batch1():
    assert_processed_file(
        "/home/user/raw_data/batch1.csv",
        "/home/user/processed_data/batch1.csv",
    )


def test_processed_data_batch2():
    assert_processed_file(
        "/home/user/raw_data/batch2.csv",
        "/home/user/processed_data/batch2.csv",
    )


def test_new_inputs_arbitrary_directories_and_parallel_tool_use():
    with tempfile.TemporaryDirectory(prefix="workflow_verify_") as root:
        root = Path(root)
        input_dir = root / "new_inputs"
        output_dir = root / "new_outputs"
        wrappers = root / "tool_wrappers"
        input_dir.mkdir()
        wrappers.mkdir()

        header = "PatientID,Name,SSN,Age,BloodPressure,HeartRate\n"
        (input_dir / "fresh_a.csv").write_text(
            header
            + "101,New Person,321-54-9876,42,,\n"
            + "102,Bad Age,111-22-3333,121,100/70,60\n"
            + "103,Bad SSN,not-an-ssn,30,110/70,75\n"
            + "104,Young Person,222-33-4444,0,90/60,100\n"
        )
        (input_dir / "fresh_b.csv").write_text(
            header
            + "201,Old Person,888-77-6666,120,,55\n"
            + "202,Missing Pulse,555-44-3333,67,140/90,\n"
            + "203,Text Age,123-45-6789,abc,120/80,72\n"
        )
        (input_dir / "ignore.txt").write_text("not a csv\n")

        xargs_args = root / "xargs.args"
        parallel_used = root / "parallel.used"
        (wrappers / "xargs").write_text(
            "#!/bin/sh\n"
            "printf '%s\\0' \"$@\" >> \"$VERIFY_XARGS_ARGS\"\n"
            "exec /usr/bin/xargs \"$@\"\n"
        )
        (wrappers / "parallel").write_text(
            "#!/bin/sh\n"
            "printf 'used\\n' >> \"$VERIFY_PARALLEL_USED\"\n"
            "exec /usr/bin/parallel \"$@\"\n"
        )
        os.chmod(wrappers / "xargs", 0o755)
        os.chmod(wrappers / "parallel", 0o755)

        env = os.environ.copy()
        env["PATH"] = str(wrappers) + os.pathsep + env.get("PATH", "")
        env["VERIFY_XARGS_ARGS"] = str(xargs_args)
        env["VERIFY_PARALLEL_USED"] = str(parallel_used)

        result = subprocess.run(
            [SCRIPT_PATH, str(input_dir), str(output_dir)],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"workflow.sh failed for newly supplied directories:\n{result.stderr}"
        )

        assert output_dir.is_dir(), "The requested output directory was not created."
        assert {p.name for p in output_dir.iterdir() if p.is_file()} == {
            "fresh_a.csv", "fresh_b.csv"
        }, "The workflow must process every new CSV and retain its filename."
        assert_processed_file(input_dir / "fresh_a.csv", output_dir / "fresh_a.csv")
        assert_processed_file(input_dir / "fresh_b.csv", output_dir / "fresh_b.csv")

        parallel_confirmed = parallel_used.exists()
        if xargs_args.exists():
            args = [a.decode() for a in xargs_args.read_bytes().split(b"\0") if a]
            for i, arg in enumerate(args):
                if re.fullmatch(r"-P(?:0|[2-9]\d*)", arg):
                    parallel_confirmed = True
                elif arg in ("-P", "--max-procs") and i + 1 < len(args):
                    if re.fullmatch(r"0|[2-9]\d*", args[i + 1]):
                        parallel_confirmed = True
                elif re.fullmatch(r"--max-procs=(?:0|[2-9]\d*)", arg):
                    parallel_confirmed = True

        # Absolute tool paths bypass PATH wrappers, so also accept a real,
        # uncommented parallel-tool command in that case. A comment containing
        # only the keyword does not satisfy this check.
        if not parallel_confirmed:
            source = Path(SCRIPT_PATH).read_text()
            source = re.sub(r"\\\n", " ", source)
            commands = []
            for line in source.splitlines():
                stripped = line.lstrip()
                if not stripped.startswith("#"):
                    commands.append(line.split("#", 1)[0])
            command_source = "\n".join(commands)
            parallel_cmd = re.search(
                r"(?:^|[|;&(]\s*)(?:command\s+)?(?:/[\w./-]+/)?parallel(?:\s|$)",
                command_source,
                re.MULTILINE,
            )
            xargs_cmd = re.search(
                r"(?:^|[|;&(]\s*)(?:command\s+)?(?:/[\w./-]+/)?xargs\b[^\n]*"
                r"(?:-P\s*(?:0|[2-9]\d*)|--max-procs(?:=|\s+)(?:0|[2-9]\d*))",
                command_source,
                re.MULTILINE,
            )
            parallel_confirmed = bool(parallel_cmd or xargs_cmd)

        assert parallel_confirmed, (
            "The workflow must actually invoke GNU parallel or xargs with more "
            "than one worker; mentioning a tool only in a comment is insufficient."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
