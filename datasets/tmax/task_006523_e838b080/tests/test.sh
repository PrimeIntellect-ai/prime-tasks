#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shlex
import stat
import string
import subprocess
import tempfile
from pathlib import Path


def run_monitor(*args):
    return subprocess.run(
        ["/home/user/monitor_storage", *map(str, args)],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_env_profile_contents_and_exports():
    path = "/home/user/.env_profile"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original content assertions.
    assert "APP_PORT=8080" in content or "APP_PORT=\"8080\"" in content or "APP_PORT='8080'" in content, "APP_PORT is not correctly set to 8080."
    assert "APP_ENV=production" in content or "APP_ENV=\"production\"" in content or "APP_ENV='production'" in content, "APP_ENV is not correctly set to production."
    assert "export APP_PORT" in content or "export APP_ENV" in content or "export APP_PORT=8080" in content or "export APP_ENV=production" in content, "Variables must be exported."

    # Source the profile and inspect a child process's environment, proving both
    # values are actually defined and exported rather than merely mentioned.
    probe = (
        "import json,os; "
        "print(json.dumps({'APP_PORT':os.environ.get('APP_PORT'),"
        "'APP_ENV':os.environ.get('APP_ENV')}))"
    )
    result = subprocess.run(
        ["/bin/bash", "-c", f"source {shlex.quote(path)} && python3 -c {shlex.quote(probe)}"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"The environment profile could not be sourced: {result.stderr}"
    values = json.loads(result.stdout.strip().splitlines()[-1])
    assert values == {"APP_PORT": "8080", "APP_ENV": "production"}


def test_monitor_storage_executable_and_script():
    path = "/home/user/monitor_storage"
    assert os.path.isfile(path), f"File {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.readline().startswith(b"#!"), "monitor_storage must have a valid shebang."


def test_run_app_executable_and_strict():
    path = "/home/user/run_app.sh"
    assert os.path.isfile(path), f"File {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."
    with open(path, "r") as f:
        content = f.read()
    assert content.startswith("#!"), "run_app.sh must be an executable shell script with a shebang."
    assert "set -e" in content or "set -o errexit" in content, "run_app.sh must enable strict error handling (e.g., set -e)."


def test_monitor_storage_requires_exactly_one_argument():
    no_args = run_monitor()
    assert no_args.returncode != 0, "monitor_storage must reject zero arguments."
    with tempfile.TemporaryDirectory() as temp_dir:
        two_args = run_monitor(temp_dir, temp_dir)
    assert two_args.returncode != 0, "monitor_storage must reject more than one argument."


def test_monitor_storage_missing_dir():
    missing = os.path.join(tempfile.gettempdir(), "missing_" + os.urandom(8).hex())
    result = run_monitor(missing)
    assert result.returncode == 1, "monitor_storage should exit with status 1 for a missing directory."
    assert "Error: Directory not found" in result.stderr.strip(), "monitor_storage did not print the correct error message to stderr."
    assert result.stderr.strip() == "Error: Directory not found"
    assert result.stdout == ""


def test_monitor_storage_small_dir():
    with tempfile.TemporaryDirectory() as temp_dir:
        small_size = random.SystemRandom().randint(37, 900000)
        small = Path(temp_dir) / ("small_" + os.urandom(4).hex() + ".txt")
        small.write_bytes(b"x" * small_size)
        old = Path(temp_dir) / ("keep_" + os.urandom(4).hex() + ".old")
        old.write_bytes(b"old")

        result = run_monitor(temp_dir)
        assert result.returncode == 0, "monitor_storage should exit with status 0 for a small directory."
        assert result.stdout.strip() == "STATUS: OK", "monitor_storage should print exactly 'STATUS: OK' for a small directory."
        assert result.stdout == "STATUS: OK\n"
        assert result.stderr == ""
        assert small.exists() and old.exists(), "No files may be deleted at or below the limit."


def test_monitor_storage_exact_boundary_does_not_clean():
    with tempfile.TemporaryDirectory() as temp_dir:
        split = random.SystemRandom().randint(1, 999999)
        first = Path(temp_dir) / ("boundary_" + os.urandom(4).hex() + ".old")
        second = Path(temp_dir) / ("data_" + os.urandom(4).hex())
        first.write_bytes(b"a" * split)
        second.write_bytes(b"b" * (1000000 - split))

        result = run_monitor(temp_dir)
        assert result.returncode == 0
        assert result.stdout == "STATUS: OK\n"
        assert result.stderr == ""
        assert first.exists() and second.exists(), "Exactly 1,000,000 bytes must not trigger cleanup."


def test_monitor_storage_large_dir():
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        nested = root / ("nested_" + os.urandom(4).hex())
        nested.mkdir()
        excess = random.SystemRandom().randint(1, 50000)
        active = nested / ("active_" + os.urandom(4).hex() + ".log")
        active.write_bytes(b"0" * (1000000 + excess))
        old_files = [
            root / ("old_" + os.urandom(4).hex() + ".old"),
            nested / ("old_" + os.urandom(4).hex() + ".old"),
        ]
        for old in old_files:
            old.write_bytes(os.urandom(23))

        result = run_monitor(temp_dir)
        assert result.returncode == 0, "monitor_storage should exit with status 0 for a large directory."
        assert result.stdout.strip() == "STATUS: CLEANED", "monitor_storage should print exactly 'STATUS: CLEANED' for a large directory."
        assert result.stdout == "STATUS: CLEANED\n"
        assert result.stderr == ""
        assert all(not old.exists() for old in old_files), "monitor_storage must delete all .old files."
        assert active.exists(), "monitor_storage must preserve files that do not end in .old."


def test_launcher_sources_profile_invokes_monitor_and_honors_failures():
    profile = Path("/home/user/.env_profile")
    monitor = Path("/home/user/monitor_storage")
    launcher = Path("/home/user/run_app.sh")
    status_log = Path("/home/user/app_status.log")

    profile_data, profile_mode = profile.read_bytes(), stat.S_IMODE(profile.stat().st_mode)
    monitor_data, monitor_mode = monitor.read_bytes(), stat.S_IMODE(monitor.stat().st_mode)
    status_existed = status_log.exists()
    status_data = status_log.read_bytes() if status_existed else None

    token = "".join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(12))
    env_value = "env_" + token
    port_value = str(random.SystemRandom().randint(20000, 50000))
    sourced_marker = Path(tempfile.gettempdir()) / ("sourced_" + token)
    called_marker = Path(tempfile.gettempdir()) / ("called_" + token)

    try:
        profile.write_text(
            f"export APP_PORT={shlex.quote(port_value)}\n"
            f"export APP_ENV={shlex.quote(env_value)}\n"
            f"printf sourced > {shlex.quote(str(sourced_marker))}\n"
        )

        monitor.write_text(
            "#!/usr/bin/python3\n"
            "import os, pathlib, sys\n"
            f"ok = (len(sys.argv) == 2 and sys.argv[1] == '/home/user/app_logs' "
            f"and os.environ.get('APP_PORT') == {port_value!r} "
            f"and os.environ.get('APP_ENV') == {env_value!r} "
            f"and pathlib.Path({str(sourced_marker)!r}).is_file())\n"
            "if not ok:\n"
            "    print('instrumented monitor received incorrect launch state', file=sys.stderr)\n"
            "    sys.exit(29)\n"
            f"pathlib.Path({str(called_marker)!r}).write_text('called')\n"
            "print('STATUS: OK')\n"
        )
        monitor.chmod(0o755)
        if status_log.exists():
            status_log.unlink()

        result = subprocess.run([str(launcher)], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"run_app.sh failed instrumented execution: {result.stderr}"
        assert sourced_marker.is_file(), "run_app.sh did not source /home/user/.env_profile."
        assert called_marker.is_file(), "run_app.sh did not execute /home/user/monitor_storage."
        expected = f"[SUCCESS] Environment {env_value} initialized on port {port_value}\n"
        assert status_log.read_text() == expected, "The launcher must append the evaluated profile values exactly once."

        # A failing monitor must stop the launcher before it appends success.
        monitor.write_text("#!/usr/bin/python3\nimport sys\nsys.exit(37)\n")
        monitor.chmod(0o755)
        status_log.unlink()
        failed = subprocess.run([str(launcher)], capture_output=True, text=True, timeout=10)
        assert failed.returncode != 0, "Strict error handling must propagate a monitor failure."
        assert not status_log.exists() or status_log.read_text() == "", "The launcher must not append success after monitor failure."
    finally:
        profile.write_bytes(profile_data)
        profile.chmod(profile_mode)
        monitor.write_bytes(monitor_data)
        monitor.chmod(monitor_mode)
        for marker in (sourced_marker, called_marker):
            if marker.exists():
                marker.unlink()
        if status_existed:
            status_log.write_bytes(status_data)
        elif status_log.exists():
            status_log.unlink()


def test_run_app_execution_and_status():
    # Preserve the original end-to-end assertions against the submitted files.
    log_dir = "/home/user/app_logs"
    os.makedirs(log_dir, exist_ok=True)
    large_log = os.path.join(log_dir, "large_log.old")
    with open(large_log, "wb") as f:
        f.write(b"0" * 1200000)

    run_app_path = "/home/user/run_app.sh"
    result = subprocess.run([run_app_path], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"run_app.sh failed to execute properly. stderr: {result.stderr}"
    assert not os.path.exists(large_log), "run_app.sh did not result in the .old file being deleted."

    status_log = "/home/user/app_status.log"
    assert os.path.isfile(status_log), f"File {status_log} was not created."
    with open(status_log, "r") as f:
        content = f.read()
    expected_line = "[SUCCESS] Environment production initialized on port 8080"
    assert expected_line in content, f"Expected line '{expected_line}' not found in {status_log}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
