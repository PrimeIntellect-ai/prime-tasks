#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import stat
import subprocess
import tempfile
import time


def parse_timestamp(line, zone):
    pattern = rf"^(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}}) {zone}$"
    match = re.fullmatch(pattern, line)
    assert match, f"Output '{line}' does not match expected timestamp format ending in {zone}."
    offset = datetime.timedelta(hours=9 if zone == "JST" else 0)
    parsed = datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
    return parsed.replace(tzinfo=datetime.timezone(offset)).timestamp()


def assert_current_timestamp(output, zone, before, after):
    assert output.endswith("\n"), "Output does not have a trailing newline."
    assert output == output.rstrip("\n") + "\n", "Output must contain exactly one trailing newline."
    assert len(output.splitlines()) == 1, "Output must contain exactly one line."
    timestamp = parse_timestamp(output[:-1], zone)
    assert before - 2 <= timestamp <= after + 2, (
        f"Timestamp {output[:-1]!r} is not the current system time."
    )


def run_and_check_current(executable, tz, zone):
    env = os.environ.copy()
    env["TZ"] = tz
    env["LC_ALL"] = "C"
    before = time.time()
    result = subprocess.run([executable], env=env, capture_output=True, text=True)
    after = time.time()
    assert result.returncode == 0, f"Running {executable} failed with return code {result.returncode}."
    assert result.stderr == "", f"Running {executable} wrote unexpected stderr: {result.stderr!r}"
    assert_current_timestamp(result.stdout, zone, before, after)


def test_c_program_exists_and_executable():
    c_source = "/home/user/write_timestamp.c"
    c_bin = "/home/user/write_timestamp"

    assert os.path.isfile(c_source), f"C source file {c_source} is missing."
    assert os.path.isfile(c_bin), f"Compiled binary {c_bin} is missing."

    st = os.stat(c_bin)
    assert bool(st.st_mode & stat.S_IXUSR), f"Binary {c_bin} is not executable."

    with open(c_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{c_bin} is not a compiled ELF executable."
    assert st.st_mtime_ns >= os.stat(c_source).st_mtime_ns, (
        f"{c_bin} is older than its C source and does not appear to have been compiled from it."
    )


def test_c_source_compiles_and_implements_timestamp_program():
    c_source = "/home/user/write_timestamp.c"
    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt = os.path.join(temp_dir, "write_timestamp")
        result = subprocess.run(
            ["/usr/bin/gcc", c_source, "-o", rebuilt],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"C source failed to compile: {result.stderr}"
        assert os.access(rebuilt, os.X_OK), "Recompiled C source did not produce an executable."
        run_and_check_current(rebuilt, "UTC", "UTC")
        run_and_check_current(rebuilt, "Asia/Tokyo", "JST")


def test_c_program_output():
    c_bin = "/home/user/write_timestamp"
    env = os.environ.copy()
    env["TZ"] = "UTC"
    env["LC_ALL"] = "C"

    before = time.time()
    result = subprocess.run([c_bin], env=env, capture_output=True, text=True)
    after = time.time()
    assert result.returncode == 0, f"Running {c_bin} failed with return code {result.returncode}."

    output = result.stdout
    assert output.endswith("\n"), "Output does not have a trailing newline."

    output_stripped = output.strip()
    pattern = r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC$"
    assert re.match(pattern, output_stripped), f"Output '{output_stripped}' does not match expected format 'YYYY-MM-DD HH:MM:SS UTC'."
    assert_current_timestamp(output, "UTC", before, after)

    run_and_check_current(c_bin, "Asia/Tokyo", "JST")


def test_bash_script_exists_and_executable():
    script = "/home/user/logger_script.sh"
    assert os.path.isfile(script), f"Bash script {script} is missing."

    st = os.stat(script)
    assert bool(st.st_mode & stat.S_IXUSR), f"Bash script {script} is not executable."


def test_bash_script_logic():
    script = "/home/user/logger_script.sh"
    log_file = "/home/user/server.log"
    old_log_file = "/home/user/server.log.old"

    if os.path.exists(log_file):
        os.remove(log_file)
    if os.path.exists(old_log_file):
        os.remove(old_log_file)

    before_runs = time.time()

    for i in range(3):
        subprocess.run([script], check=True)

    assert os.path.isfile(log_file), f"{log_file} was not created."
    with open(log_file, "r") as f:
        lines = f.readlines()

    assert len(lines) == 3, f"Expected 3 lines in {log_file} after 3 runs, got {len(lines)}."
    for idx, line in enumerate(lines):
        assert line.strip().endswith("JST"), f"Line {idx+1} in {log_file} does not end with JST: {line.strip()}"

    subprocess.run([script], check=True)
    after_runs = time.time()

    assert os.path.isfile(old_log_file), f"{old_log_file} was not created after 4th run (rotation failed)."
    with open(old_log_file, "r") as f:
        old_lines = f.readlines()
    assert len(old_lines) == 3, f"Expected 3 lines in {old_log_file}, got {len(old_lines)}."

    with open(log_file, "r") as f:
        new_lines = f.readlines()
    assert len(new_lines) == 1, f"Expected 1 line in {log_file} after rotation, got {len(new_lines)}."
    assert new_lines[0].strip().endswith("JST"), f"New line in {log_file} does not end with JST: {new_lines[0].strip()}"

    for line in old_lines + new_lines:
        assert_current_timestamp(line, "JST", before_runs, after_runs)


def test_cron_schedule():
    cron_file = "/home/user/cron_schedule"
    assert os.path.isfile(cron_file), f"Cron schedule file {cron_file} is missing."

    with open(cron_file, "r") as f:
        content = f.read().strip()

    pattern = r"^(\*/15|0,15,30,45)\s+\*\s+\*\s+\*\s+\*\s+/home/user/logger_script\.sh$"
    assert re.match(pattern, content), f"Cron schedule content '{content}' does not match expected format."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
