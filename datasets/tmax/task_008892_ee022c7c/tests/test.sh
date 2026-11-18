#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import uuid

import pytest

RESTORE_DIR = "/home/user/restore_dir"
LOG_PATH = "/home/user/restore_metrics.log"
LEGACY_PATH = "/home/user/legacy_restore.sh"

EXPECTED_LEGACY = b'''#!/bin/bash
if [ "$TZ" != "Pacific/Honolulu" ]; then 
    echo "Error: Incorrect timezone. System requires Pacific/Honolulu for accurate timestamp parsing."
    exit 1
fi

echo -n "Enter backup archive password: "
read -s password
echo
if [ "$password" != "V@ult2024" ]; then 
    echo "Error: Bad password"
    exit 1
fi

echo -n "Enter target restore date (YYYY-MM-DD): "
read date
if [ "$date" != "2024-01-01" ]; then 
    echo "Error: No backup found for date"
    exit 1
fi

# Simulate extracting 512000 bytes of data
dd if=/dev/zero of=/home/user/restore_dir/restored_data.bin bs=1024 count=500 2>/dev/null
echo "Restore complete."
'''


def du_bytes():
    output = subprocess.check_output(
        "du -sb /home/user/restore_dir | cut -f1",
        shell=True,
        text=True,
    )
    return int(output.strip())


def clear_restore_dir():
    for entry in os.scandir(RESTORE_DIR):
        if entry.is_dir(follow_symlinks=False):
            shutil.rmtree(entry.path)
        else:
            os.unlink(entry.path)


@pytest.fixture(scope="session")
def run_result():
    sh_exists = os.path.isfile("/home/user/run_restore.sh")
    py_exists = os.path.isfile("/home/user/run_restore.py")
    assert sh_exists or py_exists, "Automation script /home/user/run_restore.sh or .py does not exist."

    script_path = "/home/user/run_restore.sh" if sh_exists else "/home/user/run_restore.py"
    command = ["bash", script_path] if sh_exists else ["python3", script_path]

    assert os.path.isfile(LEGACY_PATH), "The legacy restore tool is missing."
    with open(LEGACY_PATH, "rb") as f:
        original_legacy = f.read()
    assert original_legacy == EXPECTED_LEGACY, "The legacy restore tool was modified."
    original_mode = stat.S_IMODE(os.stat(LEGACY_PATH).st_mode)

    clear_restore_dir()
    if os.path.lexists(LOG_PATH):
        os.unlink(LOG_PATH)

    before = du_bytes()
    unique = uuid.uuid4().hex
    real_tool = f"/tmp/legacy_restore_original_{unique}.sh"
    marker = f"/tmp/legacy_restore_invoked_{unique}"

    try:
        with open(real_tool, "wb") as f:
            f.write(EXPECTED_LEGACY)
        os.chmod(real_tool, 0o755)

        wrapper = (
            "#!/bin/bash\n"
            f"printf '%s' '{unique}' > '{marker}'\n"
            f"exec '{real_tool}' \"$@\"\n"
        )
        with open(LEGACY_PATH, "w") as f:
            f.write(wrapper)
        os.chmod(LEGACY_PATH, 0o755)

        proc = subprocess.run(
            [
                "runuser", "-u", "user", "--",
                "env", "-u", "TZ",
                "HOME=/home/user", "USER=user", "LOGNAME=user",
                *command,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )
        assert proc.returncode == 0, f"Automation script failed with exit code {proc.returncode}:\n{proc.stdout}"

        after = du_bytes()
        assert os.path.isfile(marker), "The automation script did not invoke /home/user/legacy_restore.sh."
        with open(marker, "r") as f:
            assert f.read() == unique, "Legacy tool invocation marker was invalid."

        yield {"before": before, "after": after, "script_path": script_path}
    finally:
        with open(LEGACY_PATH, "wb") as f:
            f.write(original_legacy)
        os.chmod(LEGACY_PATH, original_mode)
        for path in (real_tool, marker):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def test_automation_script_exists(run_result):
    """Test that the automation script exists."""
    sh_exists = os.path.isfile("/home/user/run_restore.sh")
    py_exists = os.path.isfile("/home/user/run_restore.py")
    assert sh_exists or py_exists, "Automation script /home/user/run_restore.sh or .py does not exist."


def test_restored_data_exists_and_size(run_result):
    """Test that the restored data file exists and has the correct size."""
    file_path = "/home/user/restore_dir/restored_data.bin"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. The legacy tool may not have run successfully."

    file_size = os.path.getsize(file_path)
    assert file_size == 512000, f"Expected file size 512000, but got {file_size}. The legacy tool may not have run correctly."


def test_metrics_log_exists_and_format(run_result):
    """Test that the metrics log contains the actual du measurements."""
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."

    with open(LOG_PATH, "r") as f:
        content = f.read()

    before_match = re.search(r"^Before:\s+(\d+)\s+bytes", content, re.MULTILINE)
    after_match = re.search(r"^After:\s+(\d+)\s+bytes", content, re.MULTILINE)

    assert before_match is not None, "Log file does not contain the 'Before: <bytes> bytes' line."
    assert after_match is not None, "Log file does not contain the 'After: <bytes> bytes' line."
    assert re.fullmatch(r"Before: (\d+) bytes\nAfter: (\d+) bytes\n?", content), "Log file does not have the required exact format."

    before_bytes = int(before_match.group(1))
    after_bytes = int(after_match.group(1))
    assert before_bytes == run_result["before"], f"Logged Before value {before_bytes} does not match du measurement {run_result['before']}."
    assert after_bytes == run_result["after"], f"Logged After value {after_bytes} does not match du measurement {run_result['after']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
