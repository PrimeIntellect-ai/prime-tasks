#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import shutil
import stat
import subprocess


def run_ok(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def read_nonempty(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def assert_real_executable(path):
    assert os.path.isfile(path), f"{path} does not exist or is not a regular file."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/pipeline.sh"
    assert os.path.exists(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    source_path = "/home/user/rolling_stats.cpp"
    assert os.path.isfile(source_path), f"{source_path} does not exist or is not a regular file."
    assert os.path.getsize(source_path) > 0, f"{source_path} is empty."


def active_cron_lines(content):
    return [
        line.strip() for line in content.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]


def valid_pipeline_cron_line(line):
    parts = line.split()
    if len(parts) < 6:
        return False
    if parts[0] not in ("*/15", "0,15,30,45"):
        return False
    if parts[1:5] != ["*", "*", "*", "*"]:
        return False
    return parts[5] == "/home/user/pipeline.sh"


def test_cron_schedule():
    cron_file = "/home/user/cron_schedule.txt"
    assert os.path.exists(cron_file), f"{cron_file} does not exist."

    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Crontab is not loaded for the user."

    crontab_content = result.stdout
    assert "/home/user/pipeline.sh" in crontab_content, "pipeline.sh is not scheduled in crontab."

    valid_schedules = ["*/15", "0,15,30,45"]
    has_valid_schedule = any(sched in crontab_content for sched in valid_schedules)
    assert has_valid_schedule, "Crontab does not contain the correct 15-minute schedule."

    with open(cron_file, "r") as f:
        cron_file_content = f.read()

    assert any(valid_pipeline_cron_line(line) for line in active_cron_lines(cron_file_content)), (
        "cron_schedule.txt does not contain an active exact every-15-minutes pipeline entry."
    )
    assert any(valid_pipeline_cron_line(line) for line in active_cron_lines(crontab_content)), (
        "The loaded crontab does not contain an active exact every-15-minutes pipeline entry."
    )


def test_pipeline_execution_and_outputs():
    script_path = "/home/user/pipeline.sh"
    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"pipeline.sh execution failed:\n{result.stderr}"

    cleaned_path = "/home/user/temp_cleaned.csv"
    assert os.path.exists(cleaned_path), f"{cleaned_path} was not created."
    cleaned_lines = read_nonempty(cleaned_path)

    expected_cleaned = [
        "1672531200,S1,temp,20.0",
        "1672531200,S3,temp,10.0",
        "1672531210,S1,temp,21.0",
        "1672531210,S3,temp,10.0",
        "1672531220,S1,temp,22.0",
        "1672531220,S3,temp,10.0",
        "1672531230,S1,temp,20.5",
        "1672531230,S3,temp,10.0",
        "1672531240,S1,temp,19.5",
        "1672531240,S3,temp,10.0",
        "1672531250,S1,temp,20.0",
        "1672531260,S1,temp,21.0",
        "1672531270,S1,temp,22.0",
        "1672531280,S1,temp,23.0"
    ]
    expected_cleaned.sort(key=lambda x: int(x.split(',')[0]))
    assert cleaned_lines == expected_cleaned, f"Contents of {cleaned_path} do not match expected cleaned data."

    stats_path = "/home/user/stats_output.csv"
    assert os.path.exists(stats_path), f"{stats_path} was not created."
    stats_lines = read_nonempty(stats_path)

    expected_stats = [
        "1672531240,S1,20.60,0.86",
        "1672531240,S3,10.00,0.00",
        "1672531250,S1,20.60,0.86",
        "1672531260,S1,20.60,0.86",
        "1672531270,S1,20.60,0.86",
        "1672531280,S1,21.10,1.28"
    ]
    for expected in expected_stats:
        assert expected in stats_lines, f"Expected output row '{expected}' not found in {stats_path}"
    assert len(stats_lines) == len(expected_stats), (
        f"Expected exactly {len(expected_stats)} rows in {stats_path}, but found {len(stats_lines)}."
    )

    assert_real_executable("/home/user/rolling_stats")


def dynamic_raw_rows():
    return [
        "220,A,temp,7",
        "105,C,humidity,99",
        "180,A,temp,5",
        "100,A,temp,1",
        "150,B,temp,5",
        "120,A,temp,2",
        "210,A,temp,",
        "130,B,temp,5",
        "160,A,temp,4",
        "110,B,temp,5",
        "190,B,temp,5",
        "140,A,temp,3",
        "170,B,temp,5",
        "200,A,temp,6",
        "180,A,temp,5",
        "115,D,pressure,12"
    ]


def expected_dynamic_cleaned():
    return [
        "100,A,temp,1",
        "110,B,temp,5",
        "120,A,temp,2",
        "130,B,temp,5",
        "140,A,temp,3",
        "150,B,temp,5",
        "160,A,temp,4",
        "170,B,temp,5",
        "180,A,temp,5",
        "190,B,temp,5",
        "200,A,temp,6",
        "220,A,temp,7"
    ]


def expected_dynamic_stats():
    return [
        "180,A,3.00,1.41",
        "190,B,5.00,0.00",
        "200,A,4.00,1.41",
        "220,A,5.00,1.41"
    ]


def test_pipeline_on_unseen_input_and_cpp_program_directly():
    raw_path = "/home/user/raw_sensor.csv"
    cleaned_path = "/home/user/temp_cleaned.csv"
    stats_path = "/home/user/stats_output.csv"
    source_path = "/home/user/rolling_stats.cpp"
    backup = "/tmp/raw_sensor.verifier-backup.csv"
    shutil.copy2(raw_path, backup)

    try:
        with open(raw_path, "w") as f:
            f.write("\n".join(dynamic_raw_rows()) + "\n")

        run_ok(["/home/user/pipeline.sh"])
        assert read_nonempty(cleaned_path) == expected_dynamic_cleaned(), (
            "pipeline.sh did not clean, deduplicate, filter, and chronologically sort an unseen input."
        )
        assert sorted(read_nonempty(stats_path)) == sorted(expected_dynamic_stats()), (
            "pipeline.sh did not compute the required rolling statistics on an unseen input."
        )
        assert_real_executable("/home/user/rolling_stats")

        direct_binary = "/tmp/rolling_stats_candidate"
        run_ok(["g++", "-O3", source_path, "-o", direct_binary])
        assert_real_executable(direct_binary)

        with open(cleaned_path, "w") as f:
            f.write("\n".join(expected_dynamic_cleaned()) + "\n")
        if os.path.exists(stats_path):
            os.remove(stats_path)
        run_ok([direct_binary])
        assert os.path.exists(stats_path), "The compiled C++ program did not create stats_output.csv."
        assert sorted(read_nonempty(stats_path)) == sorted(expected_dynamic_stats()), (
            "rolling_stats.cpp does not independently implement the required rolling algorithm."
        )
    finally:
        shutil.copy2(backup, raw_path)


def test_pipeline_compiles_with_o3_and_executes_the_cpp_artifact():
    source_path = "/home/user/rolling_stats.cpp"
    source_backup = "/tmp/rolling_stats.cpp.verifier-backup"
    marker = "/tmp/rolling_stats_was_executed"
    compiler_log = "/tmp/verifier_gpp_args"
    wrapper_dir = "/tmp/verifier-bin"
    wrapper = os.path.join(wrapper_dir, "g++")

    shutil.copy2(source_path, source_backup)
    os.makedirs(wrapper_dir, exist_ok=True)
    for path in (marker, compiler_log):
        if os.path.exists(path):
            os.remove(path)

    probe_source = r'''#include <fstream>
int main() {
    std::ofstream marker("/tmp/rolling_stats_was_executed");
    marker << "executed";
    std::ofstream output("/home/user/stats_output.csv");
    return 0;
}
'''
    with open(source_path, "w") as f:
        f.write(probe_source)

    with open(wrapper, "w") as f:
        f.write("#!/bin/bash\nprintf '%s\\n' \"$*\" >> /tmp/verifier_gpp_args\nexec /usr/bin/g++ \"$@\"\n")
    os.chmod(wrapper, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)

    env = os.environ.copy()
    env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
    try:
        run_ok(["/home/user/pipeline.sh"], env=env)
        assert os.path.exists(compiler_log), "pipeline.sh did not invoke g++ to compile rolling_stats.cpp."
        log = open(compiler_log, "r").read()
        assert "-O3" in log, "pipeline.sh did not compile the C++ program with -O3."
        assert source_path in log, "pipeline.sh did not compile /home/user/rolling_stats.cpp."
        assert "/home/user/rolling_stats" in log, (
            "pipeline.sh did not compile to /home/user/rolling_stats."
        )
        assert os.path.exists(marker), (
            "pipeline.sh compiled but did not execute the resulting C++ rolling_stats artifact."
        )
        assert_real_executable("/home/user/rolling_stats")
    finally:
        shutil.copy2(source_backup, source_path)
        run_ok(["/home/user/pipeline.sh"])

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
