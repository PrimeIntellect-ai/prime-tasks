#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kwargs)


def test_operator_files_exist():
    assert os.path.isfile("/home/user/operator.cpp"), "operator.cpp is missing."
    assert os.path.isfile("/home/user/operator"), "Compiled operator is missing."
    assert os.access("/home/user/operator", os.X_OK), "operator is not executable."
    with open("/home/user/operator", "rb") as f:
        assert f.read(4) == b"\x7fELF", "operator is not a compiled executable."


def test_git_hook_exists():
    hook_path = "/home/user/manifests.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"Git hook {hook_path} is missing."
    assert os.access(hook_path, os.X_OK), f"Git hook {hook_path} is not executable."
    with open(hook_path, "r", errors="replace") as f:
        first_line = f.readline().strip()
    assert first_line.startswith("#!") and "bash" in first_line, "post-receive must be a Bash script."


def test_operator_is_functional_and_reads_fstab():
    token = uuid.uuid4().hex
    namespace = "verify-" + token
    target = Path(tempfile.mkdtemp(prefix="operator-target-"))
    source_dir = Path(tempfile.mkdtemp(prefix="operator-input-"))
    rebuilt = Path(tempfile.mktemp(prefix="rebuilt-operator-"))
    fstab_path = Path("/home/user/k8s_fstab")
    original_fstab = fstab_path.read_bytes()

    try:
        subprocess.run(
            ["g++", "-std=c++17", "/home/user/operator.cpp", "-o", str(rebuilt)],
            check=True, capture_output=True, text=True
        )

        assert subprocess.run(["/home/user/operator"], capture_output=True).returncode != 0
        assert subprocess.run(
            ["/home/user/operator", str(source_dir), "extra"], capture_output=True
        ).returncode != 0

        with open(fstab_path, "ab") as f:
            if original_fstab and not original_fstab.endswith(b"\n"):
                f.write(b"\n")
            f.write(f"{namespace} {target} fuse.bind rw 0 0\n".encode())

        executables = [Path("/home/user/operator"), rebuilt]
        expected_logs = []
        for index, executable in enumerate(executables):
            custom_name = f"custom-{token}-{index}.yaml"
            default_name = f"default-{token}-{index}.yaml"
            ignored_name = f"ignored-{token}-{index}.txt"
            custom_data = (
                "apiVersion: v1\nkind: ConfigMap\nmetadata:\n"
                f"  name: marker-{token}-{index}\n  namespace: {namespace}\n"
                f"data:\n  value: {uuid.uuid4().hex}\n"
            ).encode()
            default_data = (
                "apiVersion: v1\nkind: Pod\nmetadata:\n"
                f"  name: default-marker-{token}-{index}\n"
            ).encode()
            (source_dir / custom_name).write_bytes(custom_data)
            (source_dir / default_name).write_bytes(default_data)
            (source_dir / ignored_name).write_text("not a manifest\n")

            result = subprocess.run([str(executable), str(source_dir)], capture_output=True, text=True)
            assert result.returncode == 0, f"operator failed: {result.stderr}"
            assert (target / custom_name).read_bytes() == custom_data
            assert Path("/home/user/deploy/default", default_name).read_bytes() == default_data
            assert not (target / ignored_name).exists(), "A non-.yaml file was deployed."
            expected_logs.extend([
                f"Deployed {custom_name} to {target}",
                f"Deployed {default_name} to /home/user/deploy/default",
            ])

        log_path = Path("/home/user/operator.log")
        assert log_path.is_file(), "operator.log was not created."
        log_lines = log_path.read_text().splitlines()
        for expected in expected_logs:
            assert expected in log_lines, f"Missing exact log entry: {expected}"
    finally:
        fstab_path.write_bytes(original_fstab)
        shutil.rmtree(target, ignore_errors=True)
        shutil.rmtree(source_dir, ignore_errors=True)
        rebuilt.unlink(missing_ok=True)


def test_deployment_via_git_push():
    clone_dir = tempfile.mkdtemp()
    token = uuid.uuid4().hex
    try:
        subprocess.run(["git", "clone", "/home/user/manifests.git", clone_dir], check=True, capture_output=True)

        manifests = {
            "pod-system.yaml": """apiVersion: v1
kind: Pod
metadata:
  name: system-pod
  namespace: kube-system
""",
            "pod-default.yaml": """apiVersion: v1
kind: Pod
metadata:
  name: default-pod
""",
            "pod-monitoring.yaml": """apiVersion: v1
kind: Pod
metadata:
  name: monitoring-pod
  namespace: monitoring
""",
            f"random-{token}.yaml": f"""apiVersion: v1
kind: ConfigMap
metadata:
  name: random-{token}
  namespace: monitoring
data:
  unpredictable: {uuid.uuid4().hex}
""",
        }
        destinations = {
            "pod-system.yaml": "/home/user/deploy/system",
            "pod-default.yaml": "/home/user/deploy/default",
            "pod-monitoring.yaml": "/home/user/deploy/monitoring",
            f"random-{token}.yaml": "/home/user/deploy/monitoring",
        }

        for name, content in manifests.items():
            Path(clone_dir, name).write_text(content)

        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=clone_dir, check=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=clone_dir, check=True)
        subprocess.run(["git", "add", "."], cwd=clone_dir, check=True)
        subprocess.run(["git", "commit", "-m", f"Verifier test {token}"], cwd=clone_dir, check=True, capture_output=True)

        log_path = Path("/home/user/operator.log")
        old_log_size = log_path.stat().st_size if log_path.exists() else 0
        push_result = subprocess.run(
            ["git", "push", "origin", "HEAD:master"], cwd=clone_dir,
            capture_output=True, text=True
        )
        assert push_result.returncode == 0, f"Git push failed: {push_result.stderr}"

        for name, expected_content in manifests.items():
            deployed = Path(destinations[name], name)
            assert deployed.is_file(), f"{name} was not deployed to {destinations[name]}"
            assert deployed.read_text() == expected_content, f"Deployed content for {name} differs from the pushed manifest."

        assert log_path.is_file(), "operator.log was not created."
        with open(log_path, "rb") as f:
            f.seek(old_log_size)
            new_log_lines = f.read().decode(errors="replace").splitlines()
        for name, destination in destinations.items():
            expected = f"Deployed {name} to {destination}"
            assert expected in new_log_lines, f"Missing exact log entry: {expected}"
    finally:
        shutil.rmtree(clone_dir, ignore_errors=True)


def test_hook_invokes_operator_with_extracted_temporary_directory_and_cleans_it():
    token = uuid.uuid4().hex
    clone_dir = tempfile.mkdtemp()
    operator = Path("/home/user/operator")
    real_operator = Path(f"/tmp/operator-real-{token}")
    marker = Path(f"/tmp/operator-marker-{token}")
    captured = Path(f"/tmp/operator-captured-{token}.yaml")
    filename = f"hook-proof-{token}.yaml"
    content = f"""apiVersion: v1
kind: Secret
metadata:
  name: hook-proof-{token}
  namespace: kube-system
stringData:
  proof: {uuid.uuid4().hex}
"""

    try:
        subprocess.run(["git", "clone", "/home/user/manifests.git", clone_dir], check=True, capture_output=True)
        Path(clone_dir, filename).write_text(content)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=clone_dir, check=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=clone_dir, check=True)
        subprocess.run(["git", "add", "."], cwd=clone_dir, check=True)
        subprocess.run(["git", "commit", "-m", f"Hook proof {token}"], cwd=clone_dir, check=True, capture_output=True)

        operator.rename(real_operator)
        wrapper = f'''#!/bin/bash
printf '%s\\n' "$#" > {marker}
printf '%s\\n' "$1" >> {marker}
if [ -d "$1" ]; then printf 'directory-existed\\n' >> {marker}; fi
if [ -f "$1/{filename}" ]; then cp "$1/{filename}" {captured}; fi
exec {real_operator} "$@"
'''
        operator.write_text(wrapper)
        operator.chmod(0o755)

        result = subprocess.run(
            ["git", "push", "origin", "HEAD:master"], cwd=clone_dir,
            capture_output=True, text=True
        )
        assert result.returncode == 0, f"Git push failed: {result.stderr}"
        assert marker.is_file(), "The hook did not execute /home/user/operator."
        marker_lines = marker.read_text().splitlines()
        assert marker_lines[0] == "1", "The hook did not pass exactly one argument to the operator."
        assert "directory-existed" in marker_lines, "The operator argument was not an existing directory."
        temp_argument = marker_lines[1]
        assert captured.is_file(), "The temporary directory did not contain the pushed manifest."
        assert captured.read_text() == content, "The hook did not extract the pushed manifest content."
        assert not os.path.exists(temp_argument), "The hook did not delete its temporary directory."
        deployed = Path("/home/user/deploy/system", filename)
        assert deployed.read_text() == content, "The invoked operator did not deploy the pushed content."
    finally:
        if real_operator.exists():
            operator.unlink(missing_ok=True)
            real_operator.rename(operator)
        shutil.rmtree(clone_dir, ignore_errors=True)
        marker.unlink(missing_ok=True)
        captured.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
