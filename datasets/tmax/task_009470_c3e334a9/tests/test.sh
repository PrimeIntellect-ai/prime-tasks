#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import tarfile
import time
import uuid

import pytest

HOME = "/home/user"


def run(path, *args):
    return subprocess.run([path, *args], capture_output=True, text=True)


def tar_member_data(tarball, basename):
    with tarfile.open(tarball, "r:gz") as archive:
        matches = [m for m in archive.getmembers() if m.isfile() and os.path.basename(m.name) == basename]
        assert len(matches) == 1, f"Expected exactly one {basename} in backup, found {[m.name for m in matches]}"
        return archive.extractfile(matches[0]).read()


def test_pipeline_execution_and_directories():
    pipeline_script = "/home/user/pipeline.sh"
    backup_script = "/home/user/backup.sh"
    operator_script = "/home/user/operator.py"

    assert os.path.isfile(pipeline_script), f"{pipeline_script} does not exist."
    assert os.access(pipeline_script, os.X_OK), f"{pipeline_script} is not executable."
    assert os.path.isfile(backup_script), f"{backup_script} does not exist."
    assert os.access(backup_script, os.X_OK), f"{backup_script} is not executable."
    assert os.path.isfile(operator_script), f"{operator_script} does not exist."

    result = run(pipeline_script)
    assert result.returncode == 0, f"Pipeline script failed with exit code {result.returncode}.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"

    for directory in [f"{HOME}/deployments", f"{HOME}/state", f"{HOME}/backups"]:
        assert os.path.isdir(directory), f"Directory {directory} was not created."


def test_backup_creation_and_behavior():
    backup_script = f"{HOME}/backup.sh"
    backup_tarball = f"{HOME}/backups/state_backup.tar.gz"
    marker_name = f"backup-probe-{uuid.uuid4().hex}.txt"
    marker_path = os.path.join(HOME, "state", marker_name)
    marker_data = os.urandom(48)

    with open(marker_path, "wb") as handle:
        handle.write(marker_data)
    if os.path.exists(backup_tarball):
        os.remove(backup_tarball)

    result = run(backup_script)
    assert result.returncode == 0, f"Backup script failed.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    assert os.path.isfile(backup_tarball), f"Backup tarball {backup_tarball} does not exist."

    result = subprocess.run(["tar", "-tzf", backup_tarball], capture_output=True)
    assert result.returncode == 0, f"Backup file {backup_tarball} is not a valid compressed tarball."
    assert tar_member_data(backup_tarball, marker_name) == marker_data, "Backup did not contain the current state marker."
    os.remove(marker_path)


def test_operator_on_derived_manifest_and_idempotency():
    token = uuid.uuid4().hex
    vm_name = f"probe-{token}"
    manifest_path = f"{HOME}/manifests/{token}.json"
    state_path = f"{HOME}/state/{vm_name}.json"
    deployment_path = f"{HOME}/deployments/launch_{vm_name}.sh"
    manifest = {
        "metadata": {"name": vm_name},
        "spec": {
            "qemu_image": f"/var/lib/images/{token}.qcow2",
            "vnc_port": 6100 + (int(token[:4], 16) % 700),
            "memory": f"{512 + (int(token[4:8], 16) % 8) * 256}M",
        },
    }

    try:
        with open(manifest_path, "w") as handle:
            json.dump(manifest, handle)
        for path in (state_path, deployment_path):
            if os.path.exists(path):
                os.remove(path)

        result = subprocess.run(["python3", f"{HOME}/operator.py"], capture_output=True, text=True)
        assert result.returncode == 0, f"Operator failed.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
        assert os.path.isfile(deployment_path), f"Deployment script {deployment_path} does not exist."
        assert os.access(deployment_path, os.X_OK), f"Deployment script {deployment_path} is not executable."

        with open(deployment_path) as handle:
            lines = handle.read().splitlines()
        expected_cmd = (
            f"qemu-system-x86_64 -m {manifest['spec']['memory']} "
            f"-hda {manifest['spec']['qemu_image']} "
            f"-vnc 127.0.0.1:{manifest['spec']['vnc_port']} -daemonize"
        )
        assert lines == ["#!/bin/bash", expected_cmd], f"Deployment script must contain exactly the required two lines: {lines!r}"

        with open(state_path) as handle:
            state_data = json.load(handle)
        assert state_data == {
            "status": "deployed",
            "name": vm_name,
            "port": manifest["spec"]["vnc_port"],
        }, "State file does not contain exactly the required JSON object."

        state_mtime = os.stat(state_path).st_mtime_ns
        result = subprocess.run(["python3", f"{HOME}/operator.py"], capture_output=True, text=True)
        assert result.returncode == 0, "Operator failed on an unchanged manifest."
        assert os.stat(state_path).st_mtime_ns == state_mtime, "Operator rewrote state for an unchanged manifest."

        time.sleep(1.1)
        os.utime(manifest_path, None)
        result = subprocess.run(["python3", f"{HOME}/operator.py"], capture_output=True, text=True)
        assert result.returncode == 0, "Operator failed after the manifest was updated."
        assert os.path.getmtime(state_path) >= os.path.getmtime(manifest_path), "Operator did not reconcile the updated manifest."
    finally:
        for path in (manifest_path, state_path, deployment_path):
            if os.path.exists(path):
                os.remove(path)


def test_pipeline_invokes_required_steps_in_order_and_checks_syntax():
    token = uuid.uuid4().hex
    vm_name = f"pipeline-{token}"
    manifest_path = f"{HOME}/manifests/{token}.json"
    state_path = f"{HOME}/state/{vm_name}.json"
    deployment_path = f"{HOME}/deployments/launch_{vm_name}.sh"
    invalid_script = f"{HOME}/deployments/launch_syntax_probe.sh"
    marker_name = f"order-marker-{token}.txt"
    marker_path = f"{HOME}/state/{marker_name}"
    trace_path = f"/tmp/pipeline-trace-{token}"
    backup_path = f"{HOME}/backup.sh"
    operator_path = f"{HOME}/operator.py"
    saved_backup = f"{HOME}/backup.sh.submitted-{token}"
    saved_operator = f"{HOME}/operator.py.submitted-{token}"
    log_path = f"{HOME}/pipeline.log"
    manifest = {
        "metadata": {"name": vm_name},
        "spec": {"qemu_image": f"/tmp/{token}.qcow2", "vnc_port": 7000 + int(token[:3], 16) % 500, "memory": "1536M"},
    }

    with open(manifest_path, "w") as handle:
        json.dump(manifest, handle)
    with open(marker_path, "w") as handle:
        handle.write(token)
    with open(invalid_script, "w") as handle:
        handle.write("#!/bin/bash\nif then\n")
    os.chmod(invalid_script, 0o755)
    if os.path.exists(state_path):
        os.remove(state_path)

    before_successes = 0
    if os.path.isfile(log_path):
        with open(log_path) as handle:
            before_successes = handle.read().splitlines().count("PIPELINE SUCCESS")

    shutil.move(backup_path, saved_backup)
    shutil.move(operator_path, saved_operator)
    try:
        with open(backup_path, "w") as handle:
            handle.write(f"#!/bin/bash\nprintf 'backup\\n' >> {trace_path!r}\nexec /bin/bash {saved_backup!r} \"$@\"\n")
        os.chmod(backup_path, 0o755)
        with open(operator_path, "w") as handle:
            handle.write(
                "import os, sys\n"
                f"with open({trace_path!r}, 'a') as f: f.write('operator\\n')\n"
                f"os.execv(sys.executable, [sys.executable, {saved_operator!r}] + sys.argv[1:])\n"
            )

        run(f"{HOME}/pipeline.sh")

        assert os.path.isfile(trace_path), "Pipeline did not invoke the required backup and operator paths."
        with open(trace_path) as handle:
            trace = handle.read().splitlines()
        assert "backup" in trace and "operator" in trace, "Pipeline did not invoke both backup.sh and operator.py."
        assert trace.index("backup") < trace.index("operator"), "Pipeline did not invoke backup.sh before operator.py."

        with open(log_path) as handle:
            after_failed_successes = handle.read().splitlines().count("PIPELINE SUCCESS")
        assert after_failed_successes == before_successes, "Pipeline logged success despite a syntactically invalid launch script."

        backup_tarball = f"{HOME}/backups/state_backup.tar.gz"
        assert tar_member_data(backup_tarball, marker_name) == token.encode(), "Pipeline backup did not archive preexisting state."
        with tarfile.open(backup_tarball, "r:gz") as archive:
            archived_basenames = [os.path.basename(m.name) for m in archive.getmembers() if m.isfile()]
        assert os.path.basename(state_path) not in archived_basenames, "Pipeline ran the operator before creating its backup."

        os.remove(invalid_script)
        result = run(f"{HOME}/pipeline.sh")
        assert result.returncode == 0, f"Pipeline failed after syntax was corrected.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
        with open(log_path) as handle:
            final_successes = handle.read().splitlines().count("PIPELINE SUCCESS")
        assert final_successes == before_successes + 1, "Pipeline did not append exactly one PIPELINE SUCCESS after all steps succeeded."
    finally:
        if os.path.exists(backup_path):
            os.remove(backup_path)
        if os.path.exists(operator_path):
            os.remove(operator_path)
        if os.path.exists(saved_backup):
            shutil.move(saved_backup, backup_path)
        if os.path.exists(saved_operator):
            shutil.move(saved_operator, operator_path)
        for path in (manifest_path, state_path, deployment_path, invalid_script, marker_path, trace_path):
            if os.path.exists(path):
                os.remove(path)


def test_deployment_scripts():
    manifests_dir = f"{HOME}/manifests"
    deployments_dir = f"{HOME}/deployments"

    for filename in os.listdir(manifests_dir):
        if not filename.endswith(".json"):
            continue
        with open(os.path.join(manifests_dir, filename)) as handle:
            manifest = json.load(handle)

        vm_name = manifest["metadata"]["name"]
        memory = manifest["spec"]["memory"]
        qemu_image = manifest["spec"]["qemu_image"]
        vnc_port = manifest["spec"]["vnc_port"]
        script_path = os.path.join(deployments_dir, f"launch_{vm_name}.sh")

        assert os.path.isfile(script_path), f"Deployment script {script_path} does not exist."
        assert os.access(script_path, os.X_OK), f"Deployment script {script_path} is not executable."
        with open(script_path) as handle:
            lines = handle.read().splitlines()
        assert len(lines) == 2, f"Script {script_path} does not have exactly two lines."
        assert lines[0] == "#!/bin/bash", f"Script {script_path} does not start with #!/bin/bash."
        expected_cmd = f"qemu-system-x86_64 -m {memory} -hda {qemu_image} -vnc 127.0.0.1:{vnc_port} -daemonize"
        assert lines[1] == expected_cmd, f"Script {script_path} command line does not match expected."


def test_state_files():
    manifests_dir = f"{HOME}/manifests"
    for filename in os.listdir(manifests_dir):
        if not filename.endswith(".json"):
            continue
        with open(os.path.join(manifests_dir, filename)) as handle:
            manifest = json.load(handle)
        vm_name = manifest["metadata"]["name"]
        vnc_port = manifest["spec"]["vnc_port"]
        state_path = f"{HOME}/state/{vm_name}.json"
        assert os.path.isfile(state_path), f"State file {state_path} does not exist."
        try:
            with open(state_path) as handle:
                state_data = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"State file {state_path} is not valid JSON.")
        assert state_data.get("status") == "deployed", f"State file {state_path} status is incorrect."
        assert state_data.get("name") == vm_name, f"State file {state_path} name is incorrect."
        assert state_data.get("port") == vnc_port, f"State file {state_path} port is incorrect."
        assert state_data == {"status": "deployed", "name": vm_name, "port": vnc_port}, f"State file {state_path} has extra or missing fields."


def test_pipeline_log():
    log_path = f"{HOME}/pipeline.log"
    assert os.path.isfile(log_path), f"Pipeline log {log_path} does not exist."
    with open(log_path) as handle:
        content = handle.read()
    assert "PIPELINE SUCCESS" in content, f"Pipeline log {log_path} does not contain 'PIPELINE SUCCESS'."


def test_idempotency():
    pipeline_script = f"{HOME}/pipeline.sh"
    web_manifest = f"{HOME}/manifests/web.json"
    web_state = f"{HOME}/state/web-server.json"
    db_state = f"{HOME}/state/db-server.json"

    assert os.path.isfile(web_manifest), f"Manifest {web_manifest} missing."
    assert os.path.isfile(web_state), f"State file {web_state} missing."
    assert os.path.isfile(db_state), f"State file {db_state} missing."
    time.sleep(2)
    db_state_mtime_before = os.path.getmtime(db_state)
    os.utime(web_manifest, None)
    result = run(pipeline_script)
    assert result.returncode == 0, "Pipeline script failed during idempotency test."
    assert os.path.getmtime(web_state) >= os.path.getmtime(web_manifest), "Web state file was not updated after manifest modification."
    assert db_state_mtime_before == os.path.getmtime(db_state), "DB state file was updated even though its manifest was not modified (idempotency failed)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
