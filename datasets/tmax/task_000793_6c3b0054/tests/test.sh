#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import subprocess
import tempfile
import time
import zipfile
from pathlib import Path


def test_archive_created_and_contents():
    archive_path = "/home/user/secure_backup.zip"
    assert os.path.exists(archive_path), f"Archive file {archive_path} was not created."

    with zipfile.ZipFile(archive_path, 'r') as zf:
        namelist = zf.namelist()

        # Check presence of old files
        assert "log1.txt" in namelist, "log1.txt is missing from the archive."
        assert "subdir/log2.txt" in namelist, "subdir/log2.txt is missing from the archive."

        # Check absence of new file
        assert "log3_new.txt" not in namelist, "log3_new.txt should not be in the archive because it is not old enough."

        # Check redaction in log1.txt
        content1 = zf.read("log1.txt").decode('utf-8')
        assert "[REDACTED_EMAIL]" in content1, "Email was not redacted with [REDACTED_EMAIL] in log1.txt."
        assert "admin@example.com" not in content1, "Original email admin@example.com is still present in archived log1.txt."
        assert "user123@test.co.uk" not in content1, "Original email user123@test.co.uk is still present in archived log1.txt."

        # Check redaction in subdir/log2.txt
        content2 = zf.read("subdir/log2.txt").decode('utf-8')
        assert "[REDACTED_EMAIL]" in content2, "Email was not redacted with [REDACTED_EMAIL] in subdir/log2.txt."
        assert "support@domain.com" not in content2, "Original email support@domain.com is still present in archived subdir/log2.txt."


def test_original_files_deleted():
    log1_path = "/home/user/app_logs/log1.txt"
    log2_path = "/home/user/app_logs/subdir/log2.txt"

    assert not os.path.exists(log1_path), f"Old log file {log1_path} was not deleted from disk."
    assert not os.path.exists(log2_path), f"Old log file {log2_path} was not deleted from disk."


def test_recent_file_untouched():
    log3_path = "/home/user/app_logs/log3_new.txt"

    assert os.path.exists(log3_path), f"Recent log file {log3_path} was incorrectly deleted."

    with open(log3_path, "r") as f:
        content3 = f.read()

    assert "hello@world.com" in content3, f"Recent log file {log3_path} was incorrectly redacted or modified."
    assert "[REDACTED_EMAIL]" not in content3, f"Recent log file {log3_path} was incorrectly redacted."


def test_script_handles_dynamic_configuration():
    script = Path("/home/user/archiver.py")
    assert script.is_file(), "/home/user/archiver.py was not created as a file."

    config_path = Path("/home/user/backup_config.json")
    original_config = config_path.read_bytes()
    work = Path(tempfile.mkdtemp(prefix="archiver_verify_"))

    try:
        target = work / ("logs_" + secrets.token_hex(4))
        nested = target / ("nested_" + secrets.token_hex(4))
        nested.mkdir(parents=True)
        archive = work / ("archive_" + secrets.token_hex(4) + ".zip")

        token1 = secrets.token_hex(12)
        token2 = secrets.token_hex(12)
        token3 = secrets.token_hex(12)
        pattern = r"PRIVATE_[0-9a-f]{24}"
        replacement = "[CUSTOM_MASK]"

        old_top = target / ("old_" + secrets.token_hex(4) + ".txt")
        old_nested = nested / ("old_" + secrets.token_hex(4) + ".data")
        recent = nested / ("recent_" + secrets.token_hex(4) + ".txt")

        old_top_content = f"alpha PRIVATE_{token1} omega\n"
        old_nested_content = f"PRIVATE_{token2} appears twice PRIVATE_{token3}\n"
        recent_content = f"leave PRIVATE_{token1} unchanged\n"
        old_top.write_text(old_top_content)
        old_nested.write_text(old_nested_content)
        recent.write_text(recent_content)

        now = time.time()
        old_time = now - (4 * 86400)
        recent_time = now - 3600
        os.utime(old_top, (old_time, old_time))
        os.utime(old_nested, (old_time, old_time))
        os.utime(recent, (recent_time, recent_time))

        config = {
            "target_dir": str(target),
            "min_days_old": 2,
            "mask_regex": pattern,
            "mask_replacement": replacement,
            "archive_path": str(archive),
        }
        config_path.write_text(json.dumps(config))

        result = subprocess.run(
            ["python3", str(script)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"archiver.py failed on a dynamic configuration.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert archive.is_file(), "The dynamically configured archive was not created."

        top_name = old_top.relative_to(target).as_posix()
        nested_name = old_nested.relative_to(target).as_posix()
        recent_name = recent.relative_to(target).as_posix()
        with zipfile.ZipFile(archive, "r") as zf:
            names = zf.namelist()
            assert top_name in names, "A dynamically named old file was not archived."
            assert nested_name in names, "A nested dynamically named old file was not archived."
            assert recent_name not in names, "A recent dynamically named file was archived."
            assert zf.read(top_name).decode("utf-8") == re.sub(pattern, replacement, old_top_content)
            assert zf.read(nested_name).decode("utf-8") == re.sub(pattern, replacement, old_nested_content)

        assert not old_top.exists(), "An archived dynamic file was not deleted."
        assert not old_nested.exists(), "An archived nested dynamic file was not deleted."
        assert recent.exists(), "The dynamic recent file was incorrectly deleted."
        assert recent.read_text() == recent_content, "The dynamic recent file was modified."
    finally:
        config_path.write_bytes(original_config)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
