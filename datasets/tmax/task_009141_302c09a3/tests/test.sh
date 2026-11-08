#!/bin/bash
set +e
mkdir -p /logs/verifier

python3 - <<'PY'
import glob
import os
import secrets
import shutil
import string
import subprocess
import tempfile

MERGER = "/home/user/merger"
SOURCE = "/home/user/merger.rs"
SCRIPT = "/home/user/run_tests.sh"
REPORT = "/home/user/test_report.log"
TESTS = "/home/user/tests"

# Preserve the original verifier's assertions.
assert os.path.isfile(MERGER), f"File {MERGER} does not exist. Did you compile the Rust code?"
assert os.access(MERGER, os.X_OK), f"File {MERGER} is not executable."
assert os.path.isfile(SCRIPT), f"File {SCRIPT} does not exist. Did you create the Bash script?"
assert os.path.isfile(REPORT), f"File {REPORT} does not exist. Did you run the tests?"

with open(REPORT, "r") as f:
    lines = [line.strip() for line in f.readlines() if line.strip()]
expected_lines = ["[PASS] case1", "[PASS] case2"]
assert lines == expected_lines, f"Contents of {REPORT} are incorrect. Expected {expected_lines}, got {lines}."

for case in ["case1", "case2"]:
    output_path = f"{TESTS}/{case}/output.txt"
    expected_path = f"{TESTS}/{case}/expected.txt"
    assert os.path.isfile(output_path), f"File {output_path} was not generated."
    with open(output_path, "r") as f:
        output_content = f.read().strip()
    with open(expected_path, "r") as f:
        expected_content = f.read().strip()
    assert output_content == expected_content, f"Output for {case} does not match expected."

# The requested compiled artifact must be a native executable, not a placeholder script.
with open(MERGER, "rb") as f:
    assert f.read(4) == b"\x7fELF", f"{MERGER} is not an ELF executable."


def merged_output(first, second):
    all_lines = first.splitlines() + second.splitlines()
    return ("--- MERGED LOGS ---\n"
            "(End of --- MERGED LOGS ---)\n" +
            "".join(line + "\n" for line in sorted(all_lines))).encode()


def random_line():
    alphabet = string.ascii_letters + string.digits + " _-."
    return "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(20) + 4))

# Compile the repaired source independently and exercise both it and the submitted binary
# on data whose answer is derived by the verifier.
with tempfile.TemporaryDirectory() as td:
    rebuilt = os.path.join(td, "merger")
    compile_result = subprocess.run(
        ["rustc", SOURCE, "-o", rebuilt], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, (
        "merger.rs still does not compile:\n" + compile_result.stderr.decode(errors="replace")
    )

    first_lines = [random_line() for _ in range(7)]
    second_lines = [random_line() for _ in range(6)] + [first_lines[0]]
    first = "\n".join(first_lines) + "\n"
    second = "\n".join(second_lines) + "\n"
    input1 = os.path.join(td, "input1.txt")
    input2 = os.path.join(td, "input2.txt")
    with open(input1, "w") as f:
        f.write(first)
    with open(input2, "w") as f:
        f.write(second)

    expected = merged_output(first, second)
    for executable in [MERGER, rebuilt]:
        result = subprocess.run(
            [executable, input1, input2], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10
        )
        assert result.returncode == 0, f"{executable} exited with status {result.returncode}."
        assert result.stdout == expected, f"{executable} produced incorrect output on dynamic inputs."

# Run the integration script against a controlled, dynamically named test suite. One
# fixture deliberately has a mismatching expected file so PASS and FAIL handling are
# both exercised. Restore the original task files afterward.
backup = TESTS + ".verifier_backup_" + secrets.token_hex(8)
report_existed = os.path.exists(REPORT)
report_data = open(REPORT, "rb").read() if report_existed else None
os.rename(TESTS, backup)
os.mkdir(TESTS)
try:
    suffixes = ["0_" + secrets.token_hex(4), "m_" + secrets.token_hex(4), "z_" + secrets.token_hex(4)]
    case_names = ["case" + suffix for suffix in suffixes]
    actual_outputs = {}
    statuses = {}

    for index, name in enumerate(case_names):
        case_dir = os.path.join(TESTS, name)
        os.mkdir(case_dir)
        first = "\n".join(random_line() for _ in range(index + 2)) + "\n"
        second = "\n".join(random_line() for _ in range(4 - index)) + "\n"
        expected = merged_output(first, second)
        actual_outputs[name] = expected
        statuses[name] = "FAIL" if index == 1 else "PASS"
        with open(os.path.join(case_dir, "input1.txt"), "w") as f:
            f.write(first)
        with open(os.path.join(case_dir, "input2.txt"), "w") as f:
            f.write(second)
        with open(os.path.join(case_dir, "expected.txt"), "wb") as f:
            f.write(b"deliberately incorrect expected output\n" if index == 1 else expected)

    if os.path.exists(REPORT):
        os.remove(REPORT)
    subprocess.run(["bash", SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)

    assert os.path.isfile(REPORT), "run_tests.sh did not generate test_report.log."
    with open(REPORT, "r") as f:
        dynamic_report = [line.rstrip("\n") for line in f]
    ordered_names = sorted(case_names)
    expected_report = [f"[{statuses[name]}] {name}" for name in ordered_names]
    assert dynamic_report == expected_report, (
        f"run_tests.sh report is incorrect. Expected {expected_report}, got {dynamic_report}."
    )

    for name in case_names:
        output_path = os.path.join(TESTS, name, "output.txt")
        assert os.path.isfile(output_path), f"run_tests.sh did not create {output_path}."
        with open(output_path, "rb") as f:
            output = f.read()
        assert output == actual_outputs[name], f"run_tests.sh produced incorrect output for {name}."
finally:
    shutil.rmtree(TESTS, ignore_errors=True)
    os.rename(backup, TESTS)
    if report_existed:
        with open(REPORT, "wb") as f:
            f.write(report_data)
    elif os.path.exists(REPORT):
        os.remove(REPORT)
PY
status=$?

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
