#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import uuid


def run_deploy():
    return subprocess.run(
        ["/home/user/app/deploy.sh"],
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_deployment_script_executes_compiles_copies_and_is_idempotent():
    deploy_script = "/home/user/app/deploy.sh"
    source_path = "/home/user/app/client.c"
    template_path = "/home/user/app/netclient.service"
    client_path = "/home/user/app/client"
    deployed_dir = "/home/user/.config/systemd/user"
    deployed_service = os.path.join(deployed_dir, "netclient.service")
    log_path = "/home/user/app/deploy.log"

    assert os.path.isfile(deploy_script), f"{deploy_script} is missing"
    assert os.access(deploy_script, os.X_OK), f"{deploy_script} is not executable"

    with open(source_path, "rb") as f:
        original_source = f.read()
    with open(template_path, "rb") as f:
        original_template = f.read()

    backup_dir = None
    try:
        # A compilation error must terminate the script before copy/log actions.
        os.makedirs(deployed_dir, exist_ok=True)
        with open(source_path, "w") as f:
            f.write("this is intentionally invalid C\n")
        with open(deployed_service, "w") as f:
            f.write("SERVICE_SENTINEL\n")
        with open(log_path, "w") as f:
            f.write("LOG_SENTINEL\n")

        failed = run_deploy()
        assert failed.returncode != 0, "deploy.sh succeeded despite a gcc compilation failure"
        with open(deployed_service, "r") as f:
            assert f.read() == "SERVICE_SENTINEL\n", "deploy.sh copied the service after compilation failed"
        with open(log_path, "r") as f:
            assert f.read() == "LOG_SENTINEL\n", "deploy.sh wrote the success log after compilation failed"

        # Use derived probe contents to prove that the script really compiles the
        # current source and copies the current template.
        nonce = uuid.uuid4().hex
        probe_output = f"deploy-compile-{nonce}"
        probe_source = (
            "#include <stdio.h>\n"
            "int main(void) {\n"
            f"    puts(\"{probe_output}\");\n"
            "    return 23;\n"
            "}\n"
        ).encode()
        probe_template = original_template + f"\n# verifier-copy-{nonce}\n".encode()
        with open(source_path, "wb") as f:
            f.write(probe_source)
        with open(template_path, "wb") as f:
            f.write(probe_template)

        if os.path.isdir(deployed_dir):
            backup_dir = f"/tmp/systemd-user-backup-{nonce}"
            os.rename(deployed_dir, backup_dir)
        if os.path.lexists(client_path):
            os.remove(client_path)
        if os.path.lexists(log_path):
            os.remove(log_path)

        first = run_deploy()
        assert first.returncode == 0, f"First deploy.sh run failed: {first.stderr}"
        assert os.path.isdir(deployed_dir), "deploy.sh did not create the systemd user directory"
        assert os.path.isfile(client_path), "deploy.sh did not create /home/user/app/client"
        assert os.access(client_path, os.X_OK), "deployed client is not executable"
        with open(client_path, "rb") as f:
            assert f.read(4) == b"\x7fELF", "deployed client is not a compiled executable"
        probe_run = subprocess.run([client_path], capture_output=True, timeout=10)
        assert probe_run.returncode == 23, "deploy.sh did not compile the current client.c"
        assert probe_run.stdout == (probe_output + "\n").encode(), "compiled probe produced unexpected output"
        with open(deployed_service, "rb") as f:
            assert f.read() == probe_template, "deploy.sh did not copy the current service template exactly"
        with open(log_path, "r") as f:
            assert f.read().strip() == "Deployment script executed successfully"

        second = run_deploy()
        assert second.returncode == 0, f"Second deploy.sh run failed: {second.stderr}"
        with open(deployed_service, "rb") as f:
            assert f.read() == probe_template, "repeated deployment changed or duplicated the service configuration"
        with open(log_path, "r") as f:
            assert f.read().strip() == "Deployment script executed successfully", "repeated deployment duplicated the log text"
    finally:
        with open(source_path, "wb") as f:
            f.write(original_source)
        with open(template_path, "wb") as f:
            f.write(original_template)
        if backup_dir and os.path.isdir(backup_dir):
            shutil.rmtree(backup_dir)

    # Perform the required final deployment from the agent's actual files.
    final = run_deploy()
    assert final.returncode == 0, f"Final deploy.sh run failed: {final.stderr}"
    with open(deployed_service, "rb") as f:
        assert f.read() == original_template, "final deployed service is not an exact copy of the template"


def test_client_c_behavior():
    client_c_path = "/home/user/app/client.c"
    assert os.path.isfile(client_c_path), f"{client_c_path} is missing"

    test_bin = "/tmp/test_client_bin"
    compile_proc = subprocess.run(
        ["gcc", client_c_path, "-o", test_bin],
        capture_output=True,
        text=True
    )
    assert compile_proc.returncode == 0, f"Compilation of client.c failed: {compile_proc.stderr}"

    run_proc = subprocess.run([test_bin], capture_output=True, text=True, timeout=10)
    assert run_proc.returncode == 5, f"Expected exit code 5, got {run_proc.returncode}"
    assert run_proc.stderr.strip() == "Error: Connection refused", f"Expected 'Error: Connection refused' on stderr, got '{run_proc.stderr}'"
    assert run_proc.stderr == "Error: Connection refused\n", "Error message must be written exactly to stderr"

    deployed_run = subprocess.run(
        ["/home/user/app/client"], capture_output=True, text=True, timeout=10
    )
    assert deployed_run.returncode == 5, f"Deployed client returned {deployed_run.returncode}, expected 5"
    assert deployed_run.stderr == "Error: Connection refused\n", "Deployed client has incorrect stderr output"


def directives_in_unit_section(content):
    current_section = None
    unit_lines = []
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if line.startswith("[") and line.endswith("]"):
            current_section = line
        elif current_section == "[Unit]" and line and not line.startswith(("#", ";")):
            unit_lines.append(line)
    return unit_lines


def test_systemd_configuration():
    deployed_service_path = "/home/user/.config/systemd/user/netclient.service"
    assert os.path.isfile(deployed_service_path), f"{deployed_service_path} is missing"

    with open(deployed_service_path, "r") as f:
        content = f.read()

    assert "After=netserver.service" in content, "Missing 'After=netserver.service' in deployed systemd unit"
    assert "Requires=netserver.service" in content, "Missing 'Requires=netserver.service' in deployed systemd unit"
    deployed_unit = directives_in_unit_section(content)
    assert "After=netserver.service" in deployed_unit, "After directive is not in the deployed [Unit] section"
    assert "Requires=netserver.service" in deployed_unit, "Requires directive is not in the deployed [Unit] section"

    template_service_path = "/home/user/app/netclient.service"
    assert os.path.isfile(template_service_path), f"{template_service_path} is missing"

    with open(template_service_path, "r") as f:
        template_content = f.read()

    assert "After=netserver.service" in template_content, "Missing 'After=netserver.service' in template systemd unit"
    assert "Requires=netserver.service" in template_content, "Missing 'Requires=netserver.service' in template systemd unit"
    template_unit = directives_in_unit_section(template_content)
    assert "After=netserver.service" in template_unit, "After directive is not in the template [Unit] section"
    assert "Requires=netserver.service" in template_unit, "Requires directive is not in the template [Unit] section"


def test_deployment_script_exists_and_executable():
    deploy_script_path = "/home/user/app/deploy.sh"
    assert os.path.isfile(deploy_script_path), f"{deploy_script_path} is missing"
    assert os.access(deploy_script_path, os.X_OK), f"{deploy_script_path} is not executable"


def test_deployment_log_contents():
    log_path = "/home/user/app/deploy.log"
    assert os.path.isfile(log_path), f"{log_path} is missing"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "Deployment script executed successfully", f"deploy.log contents are incorrect: {content}"


def test_client_executable_deployed():
    client_bin_path = "/home/user/app/client"
    assert os.path.isfile(client_bin_path), f"{client_bin_path} is missing"
    assert os.access(client_bin_path, os.X_OK), f"{client_bin_path} is not executable"
    with open(client_bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{client_bin_path} is not a compiled executable"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
