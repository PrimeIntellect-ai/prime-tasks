#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_rotation.py
import os
import secrets
import shutil
import stat
import subprocess

APP_DIR = "/home/user/app_logs"
STATUS = "/home/user/rotation_status.log"
SCRIPT = "/home/user/rotate.go"


def run_script():
    result = subprocess.run(
        ["go", "run", SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"go run {SCRIPT} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def reset_app_dir(files):
    if os.path.lexists(APP_DIR):
        if os.path.isdir(APP_DIR) and not os.path.islink(APP_DIR):
            shutil.rmtree(APP_DIR)
        else:
            os.unlink(APP_DIR)
    os.makedirs(APP_DIR)
    for name, data in files.items():
        with open(os.path.join(APP_DIR, name), "wb") as f:
            f.write(data)


def read_files():
    result = {}
    for name in os.listdir(APP_DIR):
        path = os.path.join(APP_DIR, name)
        assert os.path.isfile(path), f"Unexpected non-file entry created: {path}"
        with open(path, "rb") as f:
            result[name] = f.read()
    return result


def test_original_final_state_and_dynamic_behavior():
    # Preserve the original final-state assertions for the supplied fixture.
    assert os.path.isfile(STATUS), f"File {STATUS} is missing."
    with open(STATUS, "r") as f:
        content = f.read()
    expected_text = "ROTATED. Previous directory size: 15000 bytes"
    assert expected_text in content, (
        f"Expected '{expected_text}' in {STATUS}, but found: {content}"
    )

    app_log = os.path.join(APP_DIR, "app.log")
    app_log_1 = os.path.join(APP_DIR, "app.log.1")
    app_log_2 = os.path.join(APP_DIR, "app.log.2")
    app_log_3 = os.path.join(APP_DIR, "app.log.3")
    assert os.path.isfile(app_log), f"File {app_log} is missing."
    assert os.path.getsize(app_log) == 0, f"File {app_log} should be exactly 0 bytes (empty)."
    assert os.path.isfile(app_log_1), f"File {app_log_1} is missing."
    assert os.path.getsize(app_log_1) == 12000, f"File {app_log_1} should be exactly 12000 bytes."
    assert os.path.isfile(app_log_2), f"File {app_log_2} is missing."
    assert os.path.getsize(app_log_2) == 2000, f"File {app_log_2} should be exactly 2000 bytes."
    assert os.path.isfile(app_log_3), f"File {app_log_3} is missing."
    assert os.path.getsize(app_log_3) == 1000, f"File {app_log_3} should be exactly 1000 bytes."

    # The requested artifact must be a real, nonempty regular file.
    assert os.path.exists(SCRIPT), f"File {SCRIPT} is missing."
    assert not os.path.islink(SCRIPT), f"File {SCRIPT} must not be a symbolic link."
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"File {SCRIPT} is not a regular file."
    assert os.path.getsize(SCRIPT) > 0, f"File {SCRIPT} is empty."

    # At exactly the threshold, nothing may be rotated or logged.
    exact_sizes = {
        "app.log": 2500 + secrets.randbelow(400),
        "app.log.1": 1700 + secrets.randbelow(300),
        "app.log.2": 1200 + secrets.randbelow(300),
        "app.log.3": 600 + secrets.randbelow(200),
    }
    exact_sizes["quota-extra.bin"] = 10240 - sum(exact_sizes.values())
    exact_files = {name: os.urandom(size) for name, size in exact_sizes.items()}
    reset_app_dir(exact_files)
    marker = "status-before-no-rotation\n"
    with open(STATUS, "w") as f:
        f.write(marker)
    run_script()
    assert read_files() == exact_files, "Files changed even though directory size was exactly 10240 bytes."
    with open(STATUS, "r") as f:
        assert f.read() == marker, "Status log changed when no rotation should occur."

    # Use fresh, unpredictable data. The tracked logs alone are below quota,
    # while an additional file pushes the dynamically calculated total over it.
    over_sizes = {
        "app.log": 4000 + secrets.randbelow(500),
        "app.log.1": 1700 + secrets.randbelow(300),
        "app.log.2": 1300 + secrets.randbelow(300),
        "app.log.3": 500 + secrets.randbelow(200),
        "other-application-data.bin": 3800 + secrets.randbelow(500),
    }
    assert sum(over_sizes[name] for name in ("app.log", "app.log.1", "app.log.2", "app.log.3")) <= 10240
    total = sum(over_sizes.values())
    assert total > 10240
    before = {name: os.urandom(size) for name, size in over_sizes.items()}
    reset_app_dir(before)
    prefix = "existing status line\n"
    with open(STATUS, "w") as f:
        f.write(prefix)

    run_script()

    after = read_files()
    expected = {
        "app.log": b"",
        "app.log.1": before["app.log"],
        "app.log.2": before["app.log.1"],
        "app.log.3": before["app.log.2"],
        "other-application-data.bin": before["other-application-data.bin"],
    }
    assert after == expected, "Rotated files did not preserve and shift the original contents correctly."
    with open(STATUS, "r") as f:
        status_after = f.read()
    expected_status = prefix + f"ROTATED. Previous directory size: {total} bytes\n"
    assert status_after == expected_status, (
        "Status file was not appended with exactly one correctly calculated rotation line. "
        f"Expected {expected_status!r}, got {status_after!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_rotation.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
