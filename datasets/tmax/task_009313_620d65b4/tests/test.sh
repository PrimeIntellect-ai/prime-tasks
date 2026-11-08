#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time
import uuid


def test_backup_archive_exists_and_valid():
    backup_path = "/home/user/backups/dashboard_active_backup.tar.gz"
    assert os.path.isfile(backup_path), f"Backup archive missing at {backup_path}"

    with tarfile.open(backup_path, "r:gz") as tar:
        members = tar.getnames()
        cpu_member = next((m for m in members if m.endswith("cpu.json")), None)
        mem_member = next((m for m in members if m.endswith("mem.json")), None)

        assert cpu_member is not None, "cpu.json missing from backup archive"
        assert mem_member is not None, "mem.json missing from backup archive"

        cpu_f = tar.extractfile(cpu_member)
        mem_f = tar.extractfile(mem_member)
        assert cpu_f is not None, "Could not extract cpu.json from archive"
        assert mem_f is not None, "Could not extract mem.json from archive"

        cpu_content = cpu_f.read().decode("utf-8").strip()
        mem_content = mem_f.read().decode("utf-8").strip()
        assert "CPU" in cpu_content and "CPU V2" not in cpu_content, "Backup cpu.json does not have original content"
        assert "Memory" in mem_content and "Memory V2" not in mem_content, "Backup mem.json does not have original content"


def test_active_dashboards_updated():
    cpu_path = "/home/user/dashboards/active/cpu.json"
    mem_path = "/home/user/dashboards/active/mem.json"
    assert os.path.isfile(cpu_path), f"Deployed file {cpu_path} is missing"
    assert os.path.isfile(mem_path), f"Deployed file {mem_path} is missing"

    with open(cpu_path) as f:
        cpu_data = json.load(f)
        assert cpu_data.get("title") == "CPU V2", f"cpu.json was not updated correctly: {cpu_data}"
    with open(mem_path) as f:
        mem_data = json.load(f)
        assert mem_data.get("title") == "Memory V2", f"mem.json was not updated correctly: {mem_data}"


def test_invalid_dashboard_not_deployed():
    network_path = "/home/user/dashboards/active/network.json"
    assert not os.path.exists(network_path), f"Invalid JSON file {network_path} should not have been deployed"


def test_error_log_contents():
    log_path = "/home/user/logs/deploy_errors.log"
    assert os.path.isfile(log_path), f"Error log missing at {log_path}"
    with open(log_path) as f:
        log_content = f.read().strip()
    expected_line = "ERROR: network.json is invalid JSON."
    assert expected_line in log_content, f"Error log does not contain the expected error message. Found: {log_content}"


def test_forward_dashboard_script():
    script_path = "/home/user/scripts/forward_dashboard.sh"
    assert os.path.isfile(script_path), f"Script missing at {script_path}"

    with open(script_path) as f:
        content = f.read().lower()

    assert "socat" in content, "Script does not use socat"
    assert "8080" in content, "Script does not reference port 8080"
    assert "9090" in content, "Script does not reference port 9090"
    assert re.search(r"tcp(-listen|l)?:8080", content), "Script does not correctly listen on port 8080"
    assert re.search(r"tcp:127\.0\.0\.1:9090", content), "Script does not correctly forward to 127.0.0.1:9090"
    assert "&" in content or "fork" in content, "Script does not run in background or use fork"

    # Execute the shell script with socat replaced by a recorder. This proves that
    # the required command is executable rather than merely present in comments.
    real_socat = shutil.which("socat")
    assert real_socat is not None, "socat is not installed"
    real_socat = os.path.realpath(real_socat)

    with tempfile.TemporaryDirectory() as td:
        args_path = os.path.join(td, "args")
        pid_path = os.path.join(td, "pid")
        saved_socat = os.path.join(td, "real-socat")
        wrapper = f'''#!/bin/sh
printf '%s\\n' "$$" > {pid_path!r}
printf '%s\\n' "$@" > {args_path!r}
sleep 3
'''
        proc = None
        os.rename(real_socat, saved_socat)
        try:
            with open(real_socat, "w") as f:
                f.write(wrapper)
            os.chmod(real_socat, 0o755)

            proc = subprocess.Popen(
                ["/bin/bash", script_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )

            deadline = time.time() + 2
            while time.time() < deadline and not os.path.exists(args_path):
                time.sleep(0.02)
            assert os.path.isfile(args_path), "Running the forwarding script did not invoke socat"
            time.sleep(0.05)

            with open(args_path) as f:
                args = [line.strip().lower() for line in f if line.strip()]
            assert len(args) == 2, f"socat must receive exactly a listen and destination address; got {args}"

            listen = args[0]
            destination = args[1]
            assert re.match(r"^tcp(?:4|6)?-listen:8080(?:,|$)", listen), f"Incorrect socat listen address: {listen}"
            assert "bind=127.0.0.1" not in listen and "bind=localhost" not in listen, "Port 8080 must listen on all interfaces"
            assert re.match(r"^tcp(?:4|6)?:127\.0\.0\.1:9090(?:,|$)", destination), f"Incorrect socat destination: {destination}"

            has_fork = "fork" in [part.strip() for part in listen.split(",")[1:]]
            time.sleep(0.35)
            if not has_fork:
                assert proc.poll() is not None, "socat neither uses the fork option nor runs as a background command"
        finally:
            if proc is not None:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    proc.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    pass
            if os.path.exists(real_socat):
                os.unlink(real_socat)
            os.rename(saved_socat, real_socat)


def test_dynamic_deployment_script_behavior():
    script_path = "/home/user/scripts/deploy_dashboards.py"
    assert os.path.isfile(script_path), f"Deployment script missing at {script_path}"
    assert not os.path.isdir(script_path), "Deployment script path is not a file"

    active = "/home/user/dashboards/active"
    staging = "/home/user/dashboards/staging"
    backup = "/home/user/backups/dashboard_active_backup.tar.gz"
    log_path = "/home/user/logs/deploy_errors.log"

    for directory in (active, staging):
        for name in os.listdir(directory):
            path = os.path.join(directory, name)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
    if os.path.lexists(backup):
        os.unlink(backup)

    token = uuid.uuid4().hex
    overwrite_name = f"overwrite_{token}.json"
    new_name = f"new_{token}.json"
    legacy_name = f"legacy_{token}.json"
    invalid_existing_name = f"invalid_existing_{token}.json"
    invalid_new_name = f"invalid_new_{token}.json"
    ignored_name = f"ignored_{token}.txt"

    original_files = {
        overwrite_name: b'{"version":"old","value":11}\n',
        legacy_name: b'{"unchanged":true,"value":22}\n',
        invalid_existing_name: b'{"keep":"existing active file"}\n',
    }
    staged_files = {
        overwrite_name: b'{"version":"new","nested":{"ok":true}}\n',
        new_name: b'[1,2,3,{"dynamic":true}]\n',
        invalid_existing_name: b'{"broken":\n',
        invalid_new_name: b'not-json-at-all\n',
        ignored_name: b'{"valid_but_not_json_extension":true}\n',
    }

    for name, data in original_files.items():
        with open(os.path.join(active, name), "wb") as f:
            f.write(data)
    for name, data in staged_files.items():
        with open(os.path.join(staging, name), "wb") as f:
            f.write(data)

    marker = f"preexisting-log-marker-{token}"
    with open(log_path, "w") as f:
        f.write(marker + "\n")

    user = pwd.getpwnam("user")
    for directory in (active, staging, os.path.dirname(backup), os.path.dirname(log_path)):
        os.chmod(directory, 0o777)
    for directory in (active, staging):
        for name in os.listdir(directory):
            os.chown(os.path.join(directory, name), user.pw_uid, user.pw_gid)
    os.chown(log_path, user.pw_uid, user.pw_gid)
    os.chmod(log_path, 0o666)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "python3", script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Deployment script failed:\nstdout={result.stdout}\nstderr={result.stderr}"

    assert os.path.isfile(backup), "Executing the deployment script did not create the backup archive"
    archived = {}
    with tarfile.open(backup, "r:gz") as tar:
        for member in tar.getmembers():
            if member.isfile():
                extracted = tar.extractfile(member)
                assert extracted is not None
                basename = os.path.basename(member.name)
                assert basename not in archived, f"Duplicate archived filename: {basename}"
                archived[basename] = extracted.read()
    assert archived == original_files, f"Backup did not capture the exact pre-deployment active files: {archived.keys()}"

    expected_active = {
        overwrite_name: staged_files[overwrite_name],
        new_name: staged_files[new_name],
        legacy_name: original_files[legacy_name],
        invalid_existing_name: original_files[invalid_existing_name],
    }
    actual_names = set(os.listdir(active))
    assert actual_names == set(expected_active), f"Unexpected deployed files: {actual_names}"
    for name, expected in expected_active.items():
        with open(os.path.join(active, name), "rb") as f:
            assert f.read() == expected, f"Incorrect deployed content for {name}"
    assert not os.path.exists(os.path.join(active, invalid_new_name)), "A dynamically created invalid JSON file was deployed"
    assert not os.path.exists(os.path.join(active, ignored_name)), "A non-.json staging file was deployed"

    with open(log_path) as f:
        lines = f.read().splitlines()
    assert lines[0] == marker, "The error log was overwritten instead of appended to"
    expected_errors = sorted([
        f"ERROR: {invalid_existing_name} is invalid JSON.",
        f"ERROR: {invalid_new_name} is invalid JSON.",
    ])
    assert sorted(lines[1:]) == expected_errors, f"Invalid JSON errors were not logged exactly: {lines[1:]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
