#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop only stale instances of the project artifact so they cannot satisfy the
# requests made by a fresh CI run.
python3 - <<'PY'
import os
import signal
import time

target = "/home/user/polybuild/server"
for entry in os.listdir("/proc"):
    if not entry.isdigit():
        continue
    try:
        exe = os.readlink(f"/proc/{entry}/exe").removesuffix(" (deleted)")
        if exe == target:
            os.kill(int(entry), signal.SIGTERM)
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        pass
time.sleep(0.2)
PY

rm -f /home/user/polybuild/server \
      /home/user/polybuild/ci_result.log \
      /home/user/polybuild/actual_version.txt \
      /home/user/polybuild/actual_data.txt

# Actually execute the submitted pipeline from its project directory.
set +e
timeout 40s bash -c 'cd /home/user/polybuild && ./ci.sh' >/tmp/ci_stdout.log 2>/tmp/ci_stderr.log
ci_status=$?
set -e
echo "$ci_status" > /tmp/ci_status

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import time
import urllib.request
import uuid
import pytest

PROJECT = "/home/user/polybuild"
SERVER = os.path.join(PROJECT, "server")


def request(path):
    with urllib.request.urlopen("http://127.0.0.1:8080" + path, timeout=2) as response:
        return response.status, response.headers.get("Content-Type", ""), response.read()


def exercise_server(binary, expected_version):
    proc = subprocess.Popen(
        [binary], cwd=PROJECT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        last_error = None
        for _ in range(30):
            if proc.poll() is not None:
                pytest.fail(f"Server exited before becoming ready (status {proc.returncode}).")
            try:
                status, content_type, body = request("/version")
                break
            except Exception as exc:
                last_error = exc
                time.sleep(0.1)
        else:
            pytest.fail(f"Server did not listen on port 8080: {last_error}")

        assert status == 200
        assert content_type.lower().startswith("text/plain")
        assert body == expected_version.encode(), f"Unexpected /version response: {body!r}"

        status, content_type, body = request("/data")
        assert status == 200
        assert content_type.lower().startswith("text/plain")
        assert body == b"zebra\nalpha\ncharlie\nbravo\n", f"Unexpected /data response: {body!r}"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)


def test_pipeline_execution_succeeded():
    with open("/tmp/ci_status", "r") as f:
        status = int(f.read().strip())
    stderr = open("/tmp/ci_stderr.log", "r", errors="replace").read()
    assert status == 0, f"ci.sh exited with status {status}. stderr:\n{stderr}"
    assert os.path.isfile(SERVER), "ci.sh did not produce the server executable."
    assert os.access(SERVER, os.X_OK), "The server produced by ci.sh is not executable."


def test_ci_result_log():
    """Check that ci_result.log contains CI_PASS."""
    log_path = "/home/user/polybuild/ci_result.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. Did the CI script run?"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "CI_PASS", f"Expected ci_result.log to contain 'CI_PASS', but found '{content}'."


def test_actual_version():
    """Check that actual_version.txt contains exactly 1.2.3."""
    version_path = "/home/user/polybuild/actual_version.txt"
    assert os.path.isfile(version_path), f"File {version_path} does not exist."
    with open(version_path, "r") as f:
        content = f.read().strip()
    assert content == "1.2.3", f"Expected actual_version.txt to contain '1.2.3', but found '{content}'."


def test_actual_data_and_expected():
    """Check actual_data.txt and expected.txt for the correct sorted output."""
    actual_path = "/home/user/polybuild/actual_data.txt"
    expected_path = "/home/user/polybuild/expected.txt"

    assert os.path.isfile(actual_path), f"File {actual_path} does not exist."
    assert os.path.isfile(expected_path), f"File {expected_path} does not exist."

    expected_lines = ["alpha", "bravo", "charlie", "zebra"]

    with open(actual_path, "r") as f:
        actual_content = [line.strip() for line in f.readlines() if line.strip()]

    with open(expected_path, "r") as f:
        expected_content = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_content == expected_lines, f"actual_data.txt does not contain the correctly sorted data. Found: {actual_content}"
    assert expected_content == expected_lines, f"expected.txt does not contain the correctly sorted data. Found: {expected_content}"


def test_ci_script_content_and_permissions():
    """Check that ci.sh exists, is executable, and contains the correct go build command."""
    script_path = "/home/user/polybuild/ci.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert "go build" in content, "ci.sh does not contain a 'go build' command."
    assert "-ldflags" in content, "ci.sh does not use '-ldflags' in the build command."
    assert "main.Version=1.2.3" in content.replace("'", "").replace('"', ''), "ci.sh does not inject 'main.Version=1.2.3' correctly."


def test_go_project_files():
    """Check that the Go project files were created."""
    main_path = "/home/user/polybuild/main.go"
    mod_path = "/home/user/polybuild/go.mod"

    assert os.path.isfile(main_path), f"Go source file {main_path} does not exist."
    assert os.path.isfile(mod_path), f"Go module file {mod_path} does not exist."
    result = subprocess.run(
        ["go", "list", "-m"], cwd=PROJECT, text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "polybuild", f"Unexpected Go module: {result.stdout!r}"


def test_ci_stopped_its_background_server():
    target = os.path.realpath(SERVER)
    live = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            exe = os.readlink(f"/proc/{entry}/exe").removesuffix(" (deleted)")
            if exe == target:
                live.append(int(entry))
        except (FileNotFoundError, PermissionError):
            pass
    assert not live, f"ci.sh left its background server running (PIDs: {live})."


def test_server_built_by_ci_is_functional():
    exercise_server(SERVER, "1.2.3")


def test_source_builds_with_default_and_dynamic_versions(tmp_path):
    default_binary = str(tmp_path / "server-default")
    result = subprocess.run(
        ["go", "build", "-o", default_binary, "."],
        cwd=PROJECT, text=True, capture_output=True, timeout=40
    )
    assert result.returncode == 0, f"Go build failed:\n{result.stderr}"
    exercise_server(default_binary, "dev")

    injected = "verify-" + uuid.uuid4().hex
    injected_binary = str(tmp_path / "server-injected")
    result = subprocess.run(
        ["go", "build", "-o", injected_binary, "-ldflags", f"-X main.Version={injected}", "."],
        cwd=PROJECT, text=True, capture_output=True, timeout=40
    )
    assert result.returncode == 0, f"Go build with ldflags failed:\n{result.stderr}"
    exercise_server(injected_binary, injected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
