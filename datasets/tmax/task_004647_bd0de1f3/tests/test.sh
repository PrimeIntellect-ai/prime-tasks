#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_log_manager.py
import gzip
import os
import shutil
import subprocess
import sys
import uuid

BASE = "/home/user"
LOGS = os.path.join(BASE, "logs")
ARCHIVE = os.path.join(BASE, "archive")
SUMMARY = os.path.join(BASE, "summary.txt")
SCRIPT = os.path.join(BASE, "log_manager.py")
HEADER = "### LOG ROTATED ###\n"


def reset_dirs():
    shutil.rmtree(LOGS, ignore_errors=True)
    shutil.rmtree(ARCHIVE, ignore_errors=True)
    os.makedirs(LOGS, exist_ok=True)
    os.makedirs(ARCHIVE, exist_ok=True)
    try:
        os.remove(SUMMARY)
    except FileNotFoundError:
        pass


def write_lines(path, lines):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.writelines(lines)


def read_lines(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        return f.readlines()


def read_gzip_lines(path):
    with gzip.open(path, "rt", encoding="utf-8", newline="") as f:
        return f.readlines()


def run_submission():
    result = subprocess.run(
        [sys.executable, SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
    )
    assert result.returncode == 0, (
        f"log_manager.py exited with {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def verify_original_case():
    reset_dirs()

    service_a = [
        (f"Line {i} [IGNORE] unnecessary trace data\n" if i % 5 == 0
         else f"Line {i} standard log output\n")
        for i in range(1, 15001)
    ]
    service_b = [f"Line {i} standard log output\n" for i in range(1, 8001)]
    service_c = [
        (f"Line {i} [IGNORE] unnecessary trace data\n" if i % 10 == 0
         else f"Line {i} standard log output\n")
        for i in range(1, 25001)
    ]

    write_lines(os.path.join(LOGS, "serviceA.log"), service_a)
    write_lines(os.path.join(LOGS, "serviceB.log"), service_b)
    write_lines(os.path.join(LOGS, "serviceC.log"), service_c)
    run_submission()

    # Preserve all assertions made by the original verifier.
    b_path = os.path.join(LOGS, "serviceB.log")
    assert os.path.isfile(b_path), f"Expected {b_path} to exist."
    b_lines = read_lines(b_path)
    assert len(b_lines) == 8000, f"serviceB.log should have exactly 8000 lines, found {len(b_lines)}."
    assert "### LOG ROTATED ###" not in b_lines[0], "serviceB.log should not have a rotation header."
    assert b_lines == service_b, "serviceB.log was not left completely untouched."

    a_path = os.path.join(LOGS, "serviceA.log")
    assert os.path.isfile(a_path), f"Expected {a_path} to exist."
    a_lines = read_lines(a_path)
    assert len(a_lines) == 1001, f"serviceA.log should have exactly 1001 lines, found {len(a_lines)}."
    assert a_lines[0] == HEADER, "The first line of serviceA.log must be the exact header."
    assert "Line 14001" in a_lines[1], "The second line of serviceA.log should be the 14001st line from the original file."
    assert "Line 15000" in a_lines[-1], "The last line of serviceA.log should be the 15000th line from the original file."
    assert a_lines == [HEADER] + service_a[-1000:], "serviceA.log does not contain the exact final 1000 original lines."

    c_path = os.path.join(LOGS, "serviceC.log")
    assert os.path.isfile(c_path), f"Expected {c_path} to exist."
    c_lines = read_lines(c_path)
    assert len(c_lines) == 1001, f"serviceC.log should have exactly 1001 lines, found {len(c_lines)}."
    assert c_lines[0] == HEADER, "The first line of serviceC.log must be the exact header."
    assert "Line 24001" in c_lines[1], "The second line of serviceC.log should be the 24001st line from the original file."
    assert "Line 25000" in c_lines[-1], "The last line of serviceC.log should be the 25000th line from the original file."
    assert c_lines == [HEADER] + service_c[-1000:], "serviceC.log does not contain the exact final 1000 original lines."

    expected_a_archive = [line for line in service_a[:-1000] if "[IGNORE]" not in line]
    a_archive_path = os.path.join(ARCHIVE, "serviceA.log.gz")
    assert os.path.isfile(a_archive_path), f"Expected archive {a_archive_path} to exist."
    a_archive = read_gzip_lines(a_archive_path)
    assert len(a_archive) == 11200, f"Expected 11200 lines in serviceA.log archive, found {len(a_archive)}."
    assert not any("[IGNORE]" in line for line in a_archive), "Archive for serviceA.log must not contain any lines with '[IGNORE]'."
    assert a_archive == expected_a_archive, "serviceA archive does not exactly match the filtered original prefix."

    expected_c_archive = [line for line in service_c[:-1000] if "[IGNORE]" not in line]
    c_archive_path = os.path.join(ARCHIVE, "serviceC.log.gz")
    assert os.path.isfile(c_archive_path), f"Expected archive {c_archive_path} to exist."
    c_archive = read_gzip_lines(c_archive_path)
    assert len(c_archive) == 21600, f"Expected 21600 lines in serviceC.log archive, found {len(c_archive)}."
    assert not any("[IGNORE]" in line for line in c_archive), "Archive for serviceC.log must not contain any lines with '[IGNORE]'."
    assert c_archive == expected_c_archive, "serviceC archive does not exactly match the filtered original prefix."

    assert os.path.isfile(SUMMARY), f"Expected {SUMMARY} to exist."
    summary = read_lines(SUMMARY)
    content = [line.rstrip("\r\n") for line in summary]
    assert len(content) == 2, f"Expected exactly 2 lines in summary.txt, found {len(content)}."
    assert content[0] == "serviceA.log: 11200", f"Expected 'serviceA.log: 11200', got {content[0]}."
    assert content[1] == "serviceC.log: 21600", f"Expected 'serviceC.log: 21600', got {content[1]}."


def verify_generated_case():
    reset_dirs()
    token = uuid.uuid4().hex[:12]
    large_name = f"alpha_{token}.log"
    zero_name = f"omega_{token}.log"
    exact_name = f"middle_{token}.log"
    small_name = f"small_{token}.log"
    other_name = f"notes_{token}.txt"

    large = []
    for i in range(1, 10018):
        if i % 7 == 2 or i % 113 == 0:
            large.append(f"generated-{token}-{i:05d} [IGNORE] discard-this\n")
        else:
            large.append(f"generated-{token}-{i:05d} payload-{i * 17}\n")

    # Its one-line archive prefix is filtered, so its reported archive count is zero.
    zero_archive = [f"zero-{token}-00001 [IGNORE] remove me\n"] + [
        f"zero-{token}-{i:05d} retained-active-data\n" for i in range(2, 10002)
    ]
    exact = [f"exact-{token}-{i:05d}\n" for i in range(1, 10001)]
    small = [f"small-{token}-{i:05d}\n" for i in range(1, 38)]
    other = [f"not-a-log-{token}\n"]

    inputs = {
        large_name: large,
        zero_name: zero_archive,
        exact_name: exact,
        small_name: small,
    }
    for name, lines in inputs.items():
        write_lines(os.path.join(LOGS, name), lines)
    write_lines(os.path.join(LOGS, other_name), other)

    expected_archives = {
        large_name: [line for line in large[:-1000] if "[IGNORE]" not in line],
        zero_name: [],
    }
    run_submission()

    for name in (large_name, zero_name):
        original = inputs[name]
        assert read_lines(os.path.join(LOGS, name)) == [HEADER] + original[-1000:], (
            f"{name} does not contain the header followed by the exact final 1000 lines"
        )
        archive_path = os.path.join(ARCHIVE, name + ".gz")
        assert os.path.isfile(archive_path), f"Missing generated archive {archive_path}"
        actual = read_gzip_lines(archive_path)
        assert actual == expected_archives[name], f"Archive for {name} is not the filtered original prefix"
        assert not any("[IGNORE]" in line for line in actual)

    assert read_lines(os.path.join(LOGS, exact_name)) == exact, "A 10,000-line log must be completely untouched"
    assert read_lines(os.path.join(LOGS, small_name)) == small, "A short log must be completely untouched"
    assert read_lines(os.path.join(LOGS, other_name)) == other, "A non-.log file must be ignored"
    assert not os.path.exists(os.path.join(ARCHIVE, exact_name + ".gz"))
    assert not os.path.exists(os.path.join(ARCHIVE, small_name + ".gz"))
    assert not os.path.exists(os.path.join(ARCHIVE, other_name + ".gz"))

    expected_summary = [
        f"{name}: {len(expected_archives[name])}"
        for name in sorted(expected_archives)
    ]
    actual_summary = [line.rstrip("\r\n") for line in read_lines(SUMMARY)]
    assert actual_summary == expected_summary, (
        f"Generated-case summary mismatch: expected {expected_summary}, got {actual_summary}"
    )


def main():
    assert os.path.isfile(SCRIPT), f"Required script {SCRIPT} does not exist or is not a regular file."
    assert not os.path.islink(SCRIPT), f"Required script {SCRIPT} must not be a symbolic link."
    verify_original_case()
    verify_generated_case()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        import traceback
        traceback.print_exc()
        sys.exit(1)
PY_EOF

if python3 /tmp/verify_log_manager.py; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
