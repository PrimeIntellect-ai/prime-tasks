#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
import pytest


def run_processor(executable, inputs, output):
    return subprocess.run(
        [str(executable), *[str(p) for p in inputs], "-o", str(output)],
        capture_output=True,
        text=True,
    )


@pytest.fixture(scope="session")
def compiled_processor(tmp_path_factory):
    build_dir = tmp_path_factory.mktemp("build")
    executable = build_dir / "processor_from_source"
    result = subprocess.run(
        ["g++", "-std=c++17", "/home/user/processor.cpp", "-o", str(executable)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"processor.cpp does not compile as C++17: {result.stderr}"
    return executable


def test_processor_exists():
    assert os.path.isfile("/home/user/processor.cpp"), "/home/user/processor.cpp is missing"
    assert os.path.isfile("/home/user/processor"), "/home/user/processor executable is missing"
    assert os.access("/home/user/processor", os.X_OK), "/home/user/processor is not executable"


def test_pipeline_script_exists():
    assert os.path.isfile("/home/user/run_pipeline.sh"), "/home/user/run_pipeline.sh is missing"
    assert os.access("/home/user/run_pipeline.sh", os.X_OK), "/home/user/run_pipeline.sh is not executable"


def test_processed_logs_content():
    expected_content = """timestamp_sec,masked_user_id,action,value
100,MASKED_100,LOGIN,1
108,MASKED_100,CLICK,5
115,MASKED_200,LOGIN,1
116,MASKED_200,LOGOUT,1
130,MASKED_300,LOGIN,1
140,MASKED_400,LOGIN,1
150,MASKED_500,LOGIN,1
160,MASKED_600,LOGIN,1
170,MASKED_700,LOGIN,1"""

    assert os.path.isfile("/home/user/processed_logs.csv"), "/home/user/processed_logs.csv is missing"
    with open("/home/user/processed_logs.csv", "r") as f:
        content = f.read().strip()
    assert content == expected_content, "/home/user/processed_logs.csv content does not match expected output"


def test_pipeline_log():
    assert os.path.isfile("/home/user/pipeline.log"), "/home/user/pipeline.log is missing"
    with open("/home/user/pipeline.log", "r") as f:
        content = f.read()
    assert "SUCCESS" in content, "/home/user/pipeline.log does not contain SUCCESS"


def test_crontab_schedule():
    assert os.path.isfile("/home/user/crontab.txt"), "/home/user/crontab.txt is missing"
    with open("/home/user/crontab.txt", "r") as f:
        content = f.read().strip()

    match = re.search(r'^(\*/15|0,15,30,45)\s+\*\s+\*\s+\*\s+\*\s+/home/user/run_pipeline\.sh$', content, re.MULTILINE)
    assert match is not None, "/home/user/crontab.txt does not have the correct every-15-min schedule for /home/user/run_pipeline.sh"
    lines = [line for line in content.splitlines() if line.strip()]
    assert len(lines) == 1, "/home/user/crontab.txt must contain exactly one cron job line"


def test_normal_processing_on_unseen_inputs(tmp_path, compiled_processor):
    first = tmp_path / "unseen_a.csv"
    second = tmp_path / "unseen_b.csv"
    first.write_text("""timestamp_ms,user_id,action,value
200000,UABC,LOGIN,9
100000,USR999,VIEW,1
106000,USR999,VIEW,2
250999,QWE777,BUY,3
""")
    second.write_text("""timestamp_ms,user_id,action,value
105000,USR999,VIEW,duplicate
201000,UABC,LOGOUT,4
300000,ZZ123,ACTION,5
400001,RST456,END,6
""")
    expected = """timestamp_sec,masked_user_id,action,value
100,MASKED_999,VIEW,1
106,MASKED_999,VIEW,2
200,MASKED_ABC,LOGIN,9
201,MASKED_ABC,LOGOUT,4
250,MASKED_777,BUY,3
300,MASKED_123,ACTION,5
400,MASKED_456,END,6"""

    for index, executable in enumerate(("/home/user/processor", compiled_processor)):
        output = tmp_path / f"normal_{index}.csv"
        result = run_processor(executable, [first, second], output)
        assert result.returncode == 0, f"normal processing failed: {result.stderr}"
        assert output.is_file(), "Processor did not create output for a passing input"
        assert output.read_text().strip() == expected


def test_quality_gate_logic(tmp_path):
    mock_input = tmp_path / "mock_log.csv"
    mock_input.write_text("""timestamp_ms,user_id,action,value
100000,U100,LOGIN,1
101000,U100,LOGIN,1
102000,U100,LOGIN,1
103000,U100,LOGIN,1
""")
    mock_output = tmp_path / "mock_output.csv"

    result = subprocess.run(
        ["/home/user/processor", str(mock_input), "-o", str(mock_output)],
        capture_output=True,
        text=True
    )

    assert result.returncode == 2, "Processor did not exit with code 2 when drop rate > 20%"
    assert not mock_output.exists(), "Processor generated output file even when quality gate failed"


def test_pipeline_invokes_processor_and_handles_exit_codes():
    log_dir = "/home/user/logs"
    output_path = "/home/user/processed_logs.csv"
    pipeline_log = "/home/user/pipeline.log"
    backup_root = tempfile.mkdtemp(prefix="pipeline_backup_")
    backup_logs = os.path.join(backup_root, "logs")
    shutil.copytree(log_dir, backup_logs)
    old_output = open(output_path, "rb").read() if os.path.exists(output_path) else None
    old_pipeline_log = open(pipeline_log, "rb").read() if os.path.exists(pipeline_log) else None

    try:
        shutil.rmtree(log_dir)
        os.makedirs(log_dir)
        with open(os.path.join(log_dir, "part_a.csv"), "w") as f:
            f.write("""timestamp_ms,user_id,action,value
9000,AA111,OPEN,9
1000,BB222,READ,1
6000,BB222,READ,dropped
""")
        with open(os.path.join(log_dir, "part_b.csv"), "w") as f:
            f.write("""timestamp_ms,user_id,action,value
7001,BB222,READ,2
8000,BB222,WRITE,3
12000,CC333,CLOSE,4
""")
        if os.path.exists(output_path):
            os.remove(output_path)
        open(pipeline_log, "w").close()

        subprocess.run(["/home/user/run_pipeline.sh"], capture_output=True, text=True)
        expected = """timestamp_sec,masked_user_id,action,value
1,MASKED_222,READ,1
7,MASKED_222,READ,2
8,MASKED_222,WRITE,3
9,MASKED_111,OPEN,9
12,MASKED_333,CLOSE,4"""
        assert os.path.isfile(output_path), "Pipeline did not create processed_logs.csv on success"
        assert open(output_path).read().strip() == expected, "Pipeline did not process all unseen log files correctly"
        assert "SUCCESS" in open(pipeline_log).read(), "Pipeline did not log SUCCESS after processor exit code 0"

        shutil.rmtree(log_dir)
        os.makedirs(log_dir)
        with open(os.path.join(log_dir, "gate.csv"), "w") as f:
            f.write("""timestamp_ms,user_id,action,value
100000,U100,LOGIN,1
101000,U100,LOGIN,1
102000,U100,LOGIN,1
103000,U100,LOGIN,1
""")
        if os.path.exists(output_path):
            os.remove(output_path)
        open(pipeline_log, "w").close()

        subprocess.run(["/home/user/run_pipeline.sh"], capture_output=True, text=True)
        assert not os.path.exists(output_path), "Pipeline left an output file when the quality gate failed"
        assert "QUALITY GATE FAILED" in open(pipeline_log).read(), "Pipeline did not handle processor exit code 2"
    finally:
        shutil.rmtree(log_dir, ignore_errors=True)
        shutil.copytree(backup_logs, log_dir)
        if old_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(old_output)
        if old_pipeline_log is None:
            if os.path.exists(pipeline_log):
                os.remove(pipeline_log)
        else:
            with open(pipeline_log, "wb") as f:
                f.write(old_pipeline_log)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
