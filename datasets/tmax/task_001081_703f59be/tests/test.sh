#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import statistics
import subprocess
import tempfile
import uuid


def test_libgsl_dev_installed():
    """Check if libgsl-dev is installed."""
    gsl_header_path = "/usr/include/gsl/gsl_math.h"
    dpkg_check = subprocess.run(["dpkg", "-l", "libgsl-dev"], capture_output=True, text=True)

    assert os.path.isfile(gsl_header_path) or dpkg_check.returncode == 0, \
        "libgsl-dev package does not appear to be installed."


def test_process_data_c_exists():
    """Check if the C source file exists."""
    c_file = "/home/user/process_data.c"
    assert os.path.isfile(c_file), f"C source file {c_file} is missing."


def test_process_data_executable_exists():
    """Check if the compiled executable exists and is executable."""
    executable = "/home/user/process_data"
    assert os.path.isfile(executable), f"Compiled executable {executable} is missing."
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\\x7fELF", f"File {executable} is not a compiled ELF executable."


def test_run_experiments_sh_exists():
    """Check if the bash script exists and is executable."""
    script = "/home/user/run_experiments.sh"
    assert os.path.isfile(script), f"Bash script {script} is missing."
    assert os.access(script, os.X_OK), f"File {script} is not executable."


def test_tracker_csv_content():
    """Check if tracker.csv exists and has the correct output."""
    tracker_file = "/home/user/tracker.csv"
    assert os.path.isfile(tracker_file), f"Tracker file {tracker_file} is missing."

    with open(tracker_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "/home/user/data/exp1.csv,6.3333",
        "/home/user/data/exp2.csv,0.0000",
        "/home/user/data/exp3.csv,SCHEMA_ERROR",
        "/home/user/data/exp4.csv,SCHEMA_ERROR"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in tracker.csv, but got {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in tracker.csv is incorrect. Expected: '{expected}', Got: '{actual}'"


def run_processor(executable, content):
    fd, path = tempfile.mkstemp(suffix=".csv")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
        result = subprocess.run([executable, path], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"{executable} exited with {result.returncode}: {result.stderr}"
        return result.stdout
    finally:
        os.unlink(path)


def assert_exact_output(actual, expected):
    assert actual in (expected, expected + "\n"), \
        f"Expected exactly {expected!r} (optionally followed by one newline), got {actual!r}"


def test_source_builds_uses_gsl_and_processors_handle_derived_cases():
    """Compile the submitted source and exercise both it and the installed executable."""
    rebuilt = os.path.join(tempfile.mkdtemp(prefix="verifier-build-"), "process_data")
    try:
        build = subprocess.run(
            ["gcc", "/home/user/process_data.c", "-o", rebuilt, "-lgsl", "-lgslcblas", "-lm"],
            capture_output=True, text=True, timeout=30
        )
        assert build.returncode == 0, f"process_data.c did not compile with GSL: {build.stderr}"

        for executable in ("/home/user/process_data", rebuilt):
            with open(executable, "rb") as f:
                assert f.read(4) == b"\x7fELF", f"{executable} is not a compiled ELF executable"
            symbols = subprocess.run(["nm", "-D", executable], capture_output=True, text=True, timeout=10)
            assert symbols.returncode == 0, f"Could not inspect symbols in {executable}"
            assert "gsl_stats_variance" in symbols.stdout, \
                f"{executable} is not linked to the required gsl_stats_variance function"

        token = int(uuid.uuid4().hex[:8], 16)
        second_column = [
            1.125 + (token % 101) / 37.0,
            -3.75 - (token % 47) / 29.0,
            8.5 + (token % 83) / 41.0,
            14.25 - (token % 31) / 23.0,
            2.625 + (token % 59) / 43.0,
        ]
        valid = "".join(f"{i - 2.5},{value:.12f}\n" for i, value in enumerate(second_column))
        parsed_values = [float(line.split(",")[1]) for line in valid.splitlines()]
        expected_variance = f"{statistics.variance(parsed_values):.4f}"

        cases = [
            (valid, expected_variance),
            ("1.0,2.0\n3.0,4.0,5.0\n", "SCHEMA_ERROR"),
            ("1.0,2.0\n3.0,not-a-number\n", "SCHEMA_ERROR"),
            ("1.0,2.0\n\n3.0,4.0\n", "SCHEMA_ERROR"),
            ("1.0,2.0\n3.0,\n", "SCHEMA_ERROR"),
            ("1.0,2.0\n3.0,4.0junk\n", "SCHEMA_ERROR"),
            ("1.0,2.0\n3.0\n", "SCHEMA_ERROR"),
        ]

        for executable in ("/home/user/process_data", rebuilt):
            for content, expected in cases:
                assert_exact_output(run_processor(executable, content), expected)
    finally:
        shutil.rmtree(os.path.dirname(rebuilt), ignore_errors=True)


def test_run_experiments_executes_processor_on_dynamic_files_in_order():
    """Replace the data set temporarily and verify the script invokes the processor for every CSV."""
    home = "/home/user"
    data_dir = os.path.join(home, "data")
    tracker = os.path.join(home, "tracker.csv")
    processor = os.path.join(home, "process_data")
    workspace = tempfile.mkdtemp(prefix="experiment-verifier-")
    saved_data = os.path.join(workspace, "saved-data")
    saved_tracker = os.path.join(workspace, "saved-tracker")
    real_processor = os.path.join(workspace, "real-process-data")
    call_log = os.path.join(workspace, "calls.log")

    tracker_existed = os.path.exists(tracker)
    processor_moved = False
    data_moved = False
    try:
        os.rename(data_dir, saved_data)
        data_moved = True
        os.mkdir(data_dir)
        if tracker_existed:
            os.rename(tracker, saved_tracker)

        token = uuid.uuid4().hex[:10]
        names = [f"a_{token}.csv", f"b_{token}.csv", f"c_{token}.csv"]
        values = [2.25, -1.5, 7.75, 11.0]
        valid_content = "".join(f"{i + 0.5},{v}\n" for i, v in enumerate(values))
        contents = {
            names[0]: valid_content,
            names[1]: "1.0,3.0\n2.0,bad\n",
            names[2]: "1.0,9.0,4.0\n2.0,5.0,6.0\n",
        }
        for name, content in contents.items():
            with open(os.path.join(data_dir, name), "w") as f:
                f.write(content)

        os.rename(processor, real_processor)
        processor_moved = True
        with open(processor, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"printf '%s\\n' \"$1\" >> {call_log!r}\n")
            f.write(f"exec {real_processor!r} \"$@\"\n")
        os.chmod(processor, 0o755)

        with open(tracker, "w") as f:
            f.write("STALE,LINE\n")

        result = subprocess.run(["/home/user/run_experiments.sh"], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"run_experiments.sh failed: {result.stderr}"

        expected_paths = [os.path.join(data_dir, name) for name in sorted(names)]
        with open(call_log, "r") as f:
            calls = [line.rstrip("\n") for line in f]
        assert calls == expected_paths, \
            f"run_experiments.sh must invoke /home/user/process_data once per CSV in alphabetical order; got {calls}"

        expected_variance = f"{statistics.variance(values):.4f}"
        expected_lines = [
            f"{expected_paths[0]},{expected_variance}",
            f"{expected_paths[1]},SCHEMA_ERROR",
            f"{expected_paths[2]},SCHEMA_ERROR",
        ]
        with open(tracker, "r") as f:
            actual_lines = [line.rstrip("\n") for line in f]
        assert actual_lines == expected_lines, \
            f"Dynamic tracker output is incorrect. Expected {expected_lines}, got {actual_lines}"
    finally:
        if os.path.lexists(processor) and processor_moved:
            os.unlink(processor)
        if processor_moved and os.path.exists(real_processor):
            os.rename(real_processor, processor)
        if os.path.exists(tracker):
            os.unlink(tracker)
        if tracker_existed and os.path.exists(saved_tracker):
            os.rename(saved_tracker, tracker)
        if data_moved:
            shutil.rmtree(data_dir, ignore_errors=True)
            os.rename(saved_data, data_dir)
        shutil.rmtree(workspace, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
