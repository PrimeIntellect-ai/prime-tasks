#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import string
import subprocess
import tempfile
import pytest


def test_transcription_file():
    path = "/home/user/transcribed_alert.txt"
    assert os.path.isfile(path), f"Missing transcription file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    expected = "The network connectivity has failed with storage error code ENOSPC"
    assert content == expected, f"Transcription content mismatch. Expected '{expected}', got '{content}'"


def generate_random_logs(num_lines=100):
    lines = []
    for _ in range(num_lines):
        date = f"2023-10-{random.randint(10, 31)}"
        time = f"{random.randint(10, 23)}:{random.randint(10, 59)}:{random.randint(10, 59)}"
        pid = random.randint(1000, 9999)
        level = random.choice(["INFO", "WARN", "CRITICAL"])
        msg = ''.join(random.choices(string.ascii_letters, k=15))
        lines.append(f"{date} {time} {pid} {level} {msg}")
    return "\n".join(lines) + "\n"


def reference_output(input_data):
    output = []
    for line in input_data.splitlines():
        if "CRITICAL" in line:
            fields = line.split()
            output.append(f"{fields[2]}-ENOSPC\n")
    return "".join(output)


def test_parse_metrics_fuzz_equivalence():
    agent_script = "/home/user/parse_metrics.sh"
    assert os.path.isfile(agent_script), f"Missing agent script: {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script is not executable: {agent_script}"

    random.seed(42)
    inputs = [
        "a b 1111 CRITICAL message\na b 2222 INFO message\n",
        "date   time   3333   CRITICAL   spaced fields\n",
        "date time 4444 INFO message-containing-CRITICAL\n",
    ]
    inputs.extend(generate_random_logs(100) for _ in range(500))

    for i, input_data in enumerate(inputs):
        expected = reference_output(input_data)
        agent_proc = subprocess.run(
            [agent_script],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, (
            f"Agent script failed with return code {agent_proc.returncode}\n"
            f"Stderr: {agent_proc.stderr}"
        )
        if expected != agent_proc.stdout:
            pytest.fail(
                f"Mismatch on iteration {i}.\n"
                f"Input:\n{input_data}\n"
                f"Expected Output:\n{expected}\n"
                f"Agent Output:\n{agent_proc.stdout}"
            )


def test_run_alerts_execution():
    wrapper_script = "/home/user/run_alerts.sh"
    parser_script = "/home/user/parse_metrics.sh"
    output_log = "/home/user/alert_output.log"
    mount_path = "/home/user/mnt/data"
    sample_logs = "/app/sample_logs.txt"

    assert os.path.isfile(wrapper_script), f"Missing wrapper script: {wrapper_script}"
    assert os.access(wrapper_script, os.X_OK), f"Wrapper script is not executable: {wrapper_script}"

    if os.path.exists(output_log):
        os.remove(output_log)

    proc = subprocess.run([wrapper_script], capture_output=True, text=True)
    assert proc.returncode == 0, f"Wrapper script failed. Stderr: {proc.stderr}"
    assert os.path.isfile(output_log), f"Output log was not created at {output_log}"

    with open(output_log, "r") as f:
        content = f.read()

    assert "mnt/data" in content or "0" in content, "Output log does not seem to contain `du` output."
    assert "ENOSPC" in content, "Output log does not seem to contain parsed metrics."

    du_output = subprocess.run(
        ["/usr/bin/du", "-sh", mount_path],
        text=True,
        capture_output=True,
        check=True
    ).stdout
    with open(sample_logs, "r") as f:
        expected_parse = reference_output(f.read())
    assert content == du_output + expected_parse, (
        "Wrapper output must contain the exact `du -sh` output followed by the parser output."
    )

    original_parser = open(parser_script, "rb").read()
    original_mode = stat.S_IMODE(os.stat(parser_script).st_mode)
    probe_token = "PARSER_WAS_INVOKED_WITH_SAMPLE_LOGS\n"

    try:
        with open(parser_script, "w") as f:
            f.write(
                "#!/bin/bash\n"
                "if ! /usr/bin/cmp -s - /app/sample_logs.txt; then exit 91; fi\n"
                "printf 'PARSER_WAS_INVOKED_WITH_SAMPLE_LOGS\\n'\n"
            )
        os.chmod(parser_script, 0o755)

        with tempfile.TemporaryDirectory() as hostile_dir:
            fake_du = os.path.join(hostile_dir, "du")
            with open(fake_du, "w") as f:
                f.write("#!/bin/bash\nprintf 'FAKE_DU_WAS_USED\\n'\n")
            os.chmod(fake_du, 0o755)

            env = os.environ.copy()
            env["PATH"] = hostile_dir
            expected_du = subprocess.run(
                ["/usr/bin/du", "-sh", mount_path],
                text=True,
                capture_output=True,
                check=True,
                env=env
            ).stdout

            if os.path.exists(output_log):
                os.remove(output_log)
            probe_proc = subprocess.run(
                [wrapper_script], capture_output=True, text=True, env=env
            )
            assert probe_proc.returncode == 0, (
                f"Wrapper failed with a hostile inherited PATH: {probe_proc.stderr}"
            )
            assert os.path.isfile(output_log), "Wrapper did not recreate the output log."
            with open(output_log, "r") as f:
                probe_content = f.read()
            assert probe_content == expected_du + probe_token, (
                "Wrapper must prioritize standard binary directories, run `du -sh` on the mount, "
                "invoke the parser with /app/sample_logs.txt on stdin, and write both results to the output log."
            )
    finally:
        with open(parser_script, "wb") as f:
            f.write(original_parser)
        os.chmod(parser_script, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
