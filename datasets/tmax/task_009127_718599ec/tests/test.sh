#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import textwrap


def test_00_expect_script_exists_and_runs_restore():
    exp_path = "/home/user/run_restore.exp"
    assert os.path.exists(exp_path), f"The expect script {exp_path} does not exist."
    assert stat.S_ISREG(os.lstat(exp_path).st_mode), f"The path {exp_path} is not a regular file."

    with open(exp_path, "r", errors="replace") as f:
        source = f.read()
    active_source = "\n".join(
        line for line in source.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )
    assert re.search(r"(?m)^\s*spawn\b", active_source), "The script does not contain an active Expect 'spawn' command."
    assert re.search(r"(?m)^\s*expect\b", active_source), "The script does not contain an active Expect 'expect' command."
    assert re.search(r"(?m)^\s*send(?:_user)?\b", active_source), "The script does not contain an active Expect 'send' command."

    # Install a clean canonical interactive restore program immediately before
    # exercising the submitted Expect script, so pre-created output cannot pass.
    legacy_path = "/home/user/legacy_restore.sh"
    legacy_source = textwrap.dedent(r'''\
        #!/bin/bash
        read -p "Enter decryption passphrase: " pass
        if [ "$pass" != "secure_backup_2024" ]; then
            echo "[ERROR] Invalid passphrase" >> /home/user/restore_activity.log
            exit 1
        fi
        read -p "Target restore path: " path
        if [ "$path" != "/home/user/recovered_data" ]; then
            echo "[ERROR] Invalid path" >> /home/user/restore_activity.log
            exit 1
        fi
        read -p "Proceed with restore? (yes/no): " proceed
        if [ "$proceed" != "yes" ]; then
            echo "[WARN] Aborted" >> /home/user/restore_activity.log
            exit 1
        fi
        mkdir -p "$path"
        echo "2024-10-24 10:00:01 INFO Started restore" > /home/user/restore_activity.log
        echo "2024-10-24 10:00:02 [RESTORED] FILE /home/user/recovered_data/config.yml success" >> /home/user/restore_activity.log
        echo "2024-10-24 10:00:03 [RESTORED] FILE /home/user/recovered_data/database.db success" >> /home/user/restore_activity.log
        echo "2024-10-24 10:00:04 INFO Checking integrity" >> /home/user/restore_activity.log
        echo "2024-10-24 10:00:05 [RESTORED] FILE /home/user/recovered_data/images.tar.gz success" >> /home/user/restore_activity.log
        echo "2024-10-24 10:00:06 INFO Finished restore" >> /home/user/restore_activity.log
    ''')
    with open(legacy_path, "w") as f:
        f.write(legacy_source)
    os.chmod(legacy_path, 0o755)

    subprocess.run(["rm", "-rf", "/home/user/recovered_data", "/home/user/restore_activity.log"], check=True)
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "timeout", "15", "expect", exp_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert result.returncode == 0, f"Executing the Expect script failed or timed out:\n{result.stdout}"
    assert os.path.isdir("/home/user/recovered_data"), "The executed Expect script did not complete the restore."
    assert os.path.isfile("/home/user/restore_activity.log"), "The executed Expect script did not produce the restore log."


def test_recovered_data_directory_exists():
    target_dir = "/home/user/recovered_data"
    assert os.path.exists(target_dir), f"The target directory {target_dir} does not exist. The expect script may not have run successfully."
    assert os.path.isdir(target_dir), f"The path {target_dir} is not a directory."


def test_restore_activity_log_exists():
    log_path = "/home/user/restore_activity.log"
    assert os.path.exists(log_path), f"The log file {log_path} does not exist. Ensure the expect script was executed successfully."
    assert os.path.isfile(log_path), f"The path {log_path} is not a file."


def test_restored_files_txt_content():
    txt_path = "/home/user/restored_files.txt"
    assert os.path.exists(txt_path), f"The file {txt_path} does not exist."
    assert os.path.isfile(txt_path), f"The path {txt_path} is not a file."

    with open(txt_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "/home/user/recovered_data/config.yml",
        "/home/user/recovered_data/database.db",
        "/home/user/recovered_data/images.tar.gz"
    ]

    assert lines == expected_lines, f"The contents of {txt_path} do not match the expected file paths. Found: {lines}"

    # Also derive the answer from the freshly generated log rather than trusting
    # only a fixed list embedded in the verifier.
    derived_lines = []
    with open("/home/user/restore_activity.log", "r") as f:
        for line in f:
            fields = line.split()
            if "[RESTORED]" in fields:
                assert len(fields) >= 5, f"Malformed restored log line: {line!r}"
                derived_lines.append(fields[4])
    assert lines == derived_lines, f"{txt_path} was not extracted from the generated [RESTORED] log entries."


def test_logrotate_conf():
    conf_path = "/home/user/test_logrotate.conf"
    assert os.path.exists(conf_path), f"The file {conf_path} does not exist."
    assert os.path.isfile(conf_path), f"The path {conf_path} is not a file."

    with open(conf_path, 'r') as f:
        content = f.read()

    assert "/home/user/restore_activity.log" in content, f"The logrotate config does not specify the target log file '/home/user/restore_activity.log'."

    required_directives = [
        r"\bdaily\b",
        r"\brotate\s+5\b",
        r"\bcompress\b",
        r"\bmissingok\b",
        r"\bcreate\s+0644\s+user\s+user\b"
    ]

    for directive in required_directives:
        assert re.search(directive, content), f"The logrotate config is missing or has an incorrect directive matching regex: {directive}"

    # Require the directives to be active inside the target log's block, rather
    # than merely appearing in comments or unrelated text.
    uncommented = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    match = re.search(r"(?ms)^\s*/home/user/restore_activity\.log\s*\{(.*?)^\s*\}", uncommented)
    assert match, "No syntactically structured block was found for /home/user/restore_activity.log."
    block = match.group(1)
    active_directives = [
        r"(?m)^\s*daily\s*$",
        r"(?m)^\s*rotate\s+5\s*$",
        r"(?m)^\s*compress\s*$",
        r"(?m)^\s*missingok\s*$",
        r"(?m)^\s*create\s+0644\s+user\s+user\s*$",
    ]
    for directive in active_directives:
        assert re.search(directive, block), f"The target log block lacks an active directive matching: {directive}"

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "logrotate", "--debug", "-s", "/dev/null", conf_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert result.returncode == 0, f"logrotate rejected the configuration:\n{result.stdout}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
