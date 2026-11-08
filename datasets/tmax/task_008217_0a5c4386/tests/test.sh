#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os


def test_fstab_conf_exists_and_content():
    fstab_path = "/home/user/fstab.conf"
    assert os.path.exists(fstab_path), f"{fstab_path} is missing"
    with open(fstab_path, "r") as f:
        content = f.read()
    assert "/dev/mapper/data_vol /home/user/mnt/data ext4 defaults 0 0" in content, f"{fstab_path} content is invalid"
    assert content == "/dev/mapper/data_vol /home/user/mnt/data ext4 defaults 0 0\n", f"{fstab_path} must contain exactly the requested line"


def test_mount_directory_created():
    dir_path = "/home/user/mnt/data"
    assert os.path.isdir(dir_path), f"Directory {dir_path} was not created"


def test_monitor_json_valid():
    json_path = "/home/user/project/monitor.json"
    assert os.path.exists(json_path), f"{json_path} is missing"
    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} does not contain valid JSON"

    assert data.get("mount_target") == "/home/user/mnt/data", "Incorrect mount_target in JSON"
    assert data.get("network_ok") is True, "network_ok should be true in JSON"


def test_dockerfile_content():
    dockerfile_path = "/home/user/project/Dockerfile"
    assert os.path.exists(dockerfile_path), f"{dockerfile_path} is missing"
    with open(dockerfile_path, "r") as f:
        content = f.read()

    assert "ubuntu:22.04" in content, "Dockerfile missing base image ubuntu:22.04"
    assert "g++" in content, "Dockerfile missing g++ installation"
    assert "nas_monitor" in content, "Dockerfile missing compilation instructions for nas_monitor"


def test_ci_sh_executable_and_content():
    ci_path = "/home/user/project/ci.sh"
    assert os.path.exists(ci_path), f"{ci_path} is missing"
    assert os.access(ci_path, os.X_OK), f"{ci_path} must be executable"

    with open(ci_path, "r") as f:
        content = f.read()

    assert "8080" in content, "ci.sh missing port 8080 for python server"
    assert "g++" in content, "ci.sh missing g++ compilation command"
    assert "nas_monitor" in content, "ci.sh missing execution of nas_monitor"
TEST_EOF

cat <<'BEHAVIOR_EOF' > /tmp/test_behavior.py
import json
import os
import pathlib
import re
import shutil
import socket
import subprocess
import tempfile
import time
import uuid

PROJECT = pathlib.Path("/home/user/project")
SOURCE = PROJECT / "nas_monitor.cpp"
CI = PROJECT / "ci.sh"
DOCKERFILE = PROJECT / "Dockerfile"
FSTAB = pathlib.Path("/home/user/fstab.conf")
OUTPUT = PROJECT / "monitor.json"
LOCAL_BINARY = PROJECT / "nas_monitor"
REQUIRED_FSTAB = "/dev/mapper/data_vol /home/user/mnt/data ext4 defaults 0 0\n"


def wait_for_port(up, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket() as s:
            result = s.connect_ex(("127.0.0.1", 8080)) == 0
        if result == up:
            return
        time.sleep(0.05)
    raise AssertionError(f"port 8080 did not become {'available' if up else 'closed'}")


def start_server():
    code = r'''
import socket
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 8080))
s.listen(16)
while True:
    c, _ = s.accept()
    c.close()
'''
    proc = subprocess.Popen(["python3", "-c", code], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        wait_for_port(True)
    except Exception:
        error = proc.stderr.read().decode(errors="replace") if proc.poll() is not None else ""
        proc.kill()
        raise AssertionError("could not start verification server: " + error)
    return proc


def stop_server(proc):
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=3)
    wait_for_port(False)


def read_exact_result(target, network_ok):
    assert OUTPUT.is_file(), "monitor did not create monitor.json"
    text = OUTPUT.read_text()
    expected = '{"mount_target": "' + target + '", "network_ok": ' + ("true" if network_ok else "false") + '}'
    assert text.strip() == expected, f"monitor.json format/content was {text!r}, expected {expected!r}"
    data = json.loads(text)
    assert data == {"mount_target": target, "network_ok": network_ok}


def check_dockerfile_and_build_if_possible():
    raw = DOCKERFILE.read_text()
    logical = re.sub(r"\\\s*\n", " ", raw)
    lines = [line.strip() for line in logical.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    assert lines and re.fullmatch(r"FROM\s+ubuntu:22\.04(?:\s+AS\s+\S+)?", lines[0], re.I), "Dockerfile must use ubuntu:22.04"
    run_lines = [line for line in lines if re.match(r"RUN\s+", line, re.I)]
    assert any(re.search(r"(?:apt-get|apt)\s+install\b[^\n]*\bg\+\+\b", line, re.I) and re.search(r"\bmake\b", line) for line in run_lines), "Dockerfile must install g++ and make"
    assert any(re.match(r"(?:COPY|ADD)\s+(?:--\S+\s+)*nas_monitor\.cpp\s+/app/?(?:nas_monitor\.cpp)?\s*$", line, re.I) for line in lines), "Dockerfile must copy nas_monitor.cpp into /app"
    assert any(re.search(r"\bg\+\+\b", line) and re.search(r"(?:/app/)?nas_monitor\.cpp\b", line) and re.search(r"-o\s+/usr/local/bin/nas_monitor\b", line) for line in run_lines), "Dockerfile must compile to /usr/local/bin/nas_monitor"
    assert any(re.match(r"ENTRYPOINT\s+(?:\[\s*[\"']/usr/local/bin/nas_monitor[\"']\s*\]|/usr/local/bin/nas_monitor)\s*$", line, re.I) for line in lines), "Dockerfile must set nas_monitor as its entrypoint"

    if shutil.which("docker") and subprocess.run(["docker", "info"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        tag = "nas-monitor-verify-" + uuid.uuid4().hex
        try:
            subprocess.run(["docker", "build", "--no-cache", "-t", tag, str(PROJECT)], check=True, timeout=180)
            inspect = subprocess.check_output(["docker", "image", "inspect", tag, "--format", "{{json .Config.Entrypoint}}"], text=True).strip()
            assert "/usr/local/bin/nas_monitor" in inspect, "built image has the wrong entrypoint"
        finally:
            subprocess.run(["docker", "image", "rm", "-f", tag], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    assert SOURCE.is_file(), "nas_monitor.cpp is missing"
    assert CI.is_file() and os.access(CI, os.X_OK), "ci.sh is missing or not executable"

    # Execute the submitted CI pipeline from a clean artifact state. It must
    # compile a real executable, run it successfully, and clean up its server.
    FSTAB.write_text(REQUIRED_FSTAB)
    pathlib.Path("/home/user/mnt/data").mkdir(parents=True, exist_ok=True)
    OUTPUT.unlink(missing_ok=True)
    LOCAL_BINARY.unlink(missing_ok=True)
    subprocess.run([str(CI)], cwd=str(PROJECT), check=True, timeout=30)
    assert LOCAL_BINARY.is_file() and os.access(LOCAL_BINARY, os.X_OK), "ci.sh did not create an executable nas_monitor"
    assert LOCAL_BINARY.read_bytes()[:4] == b"\x7fELF", "ci.sh output is not a compiled ELF binary"
    read_exact_result("/home/user/mnt/data", True)
    wait_for_port(False, timeout=3)

    check_dockerfile_and_build_if_possible()

    # Compile the submitted source independently and exercise both TCP outcomes
    # with a randomized fstab target, so hard-coded monitor.json cannot pass.
    with tempfile.TemporaryDirectory(prefix="monitor-verify-") as td:
        binary = pathlib.Path(td) / "nas_monitor"
        subprocess.run(["g++", "-std=c++17", str(SOURCE), "-o", str(binary)], check=True, timeout=30)
        assert binary.read_bytes()[:4] == b"\x7fELF"

        target = f"/home/user/mnt/verify_{uuid.uuid4().hex}"
        shutil.rmtree(target, ignore_errors=True)
        FSTAB.write_text(f"/dev/mapper/unrelated /tmp/not_the_target ext4 defaults 0 0\n/dev/mapper/data_vol {target} ext4 defaults 0 0\n")

        server = start_server()
        try:
            OUTPUT.unlink(missing_ok=True)
            subprocess.run([str(binary)], cwd=str(PROJECT), check=True, timeout=10)
            assert pathlib.Path(target).is_dir(), "monitor did not create the parsed mount target"
            read_exact_result(target, True)
        finally:
            stop_server(server)

        OUTPUT.unlink(missing_ok=True)
        subprocess.run([str(binary)], cwd=str(PROJECT), check=True, timeout=10)
        read_exact_result(target, False)

        # Restore the required final state and regenerate its successful result.
        FSTAB.write_text(REQUIRED_FSTAB)
        server = start_server()
        try:
            OUTPUT.unlink(missing_ok=True)
            subprocess.run([str(binary)], cwd=str(PROJECT), check=True, timeout=10)
            read_exact_result("/home/user/mnt/data", True)
        finally:
            stop_server(server)


if __name__ == "__main__":
    try:
        main()
    finally:
        FSTAB.write_text(REQUIRED_FSTAB)
BEHAVIOR_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && python3 /tmp/test_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
