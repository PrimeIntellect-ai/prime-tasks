#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import tempfile
import uuid

HOOK_PATH = "/home/user/infra.git/hooks/pre-receive"
BARE_REPO = "/home/user/infra.git"
LOG_PATH = "/home/user/finops_alerts.log"
LIMIT = 104857600


def clone_repo(tmpdir):
    subprocess.run(["git", "clone", BARE_REPO, tmpdir], check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "verifier@example.com"], cwd=tmpdir, check=True)
    subprocess.run(["git", "config", "user.name", "Verifier"], cwd=tmpdir, check=True)


def commit_file(repo, path, message):
    subprocess.run(["git", "add", path], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "commit", "-m", message], cwd=repo, check=True, capture_output=True)
    return subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=repo, check=True,
        capture_output=True, text=True
    ).stdout.strip()


def test_hook_exists_and_executable():
    assert os.path.isfile(HOOK_PATH), f"Hook file {HOOK_PATH} does not exist."
    st = os.stat(HOOK_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Hook file {HOOK_PATH} is not executable."


def test_push_valid_config():
    with tempfile.TemporaryDirectory() as tmpdir:
        clone_repo(tmpdir)

        valid_json_path = os.path.join(tmpdir, "valid_vm.json")
        with open(valid_json_path, "w") as f:
            json.dump({
                "vm_name": "web-01",
                "image_path": "/home/user/storage/small.qcow2"
            }, f)

        commit_file(tmpdir, "valid_vm.json", "Add valid VM")
        result = subprocess.run(
            ["git", "push", "origin", "master"], cwd=tmpdir,
            capture_output=True, text=True
        )
        assert result.returncode == 0, f"Pushing a valid config failed. stderr: {result.stderr}"


def test_push_invalid_config_and_logging():
    with tempfile.TemporaryDirectory() as tmpdir:
        clone_repo(tmpdir)

        invalid_json_path = os.path.join(tmpdir, "invalid_vm.json")
        with open(invalid_json_path, "w") as f:
            json.dump({
                "vm_name": "db-01",
                "image_path": "/home/user/storage/large.qcow2"
            }, f)

        commit_hash = commit_file(tmpdir, "invalid_vm.json", "Add invalid VM")
        result = subprocess.run(
            ["git", "push", "origin", "master"], cwd=tmpdir,
            capture_output=True, text=True
        )

        assert result.returncode != 0, "Pushing an invalid config was allowed but should have been rejected."
        message = "FinOps Policy Violation: Image /home/user/storage/large.qcow2 is too large."
        assert message in result.stderr or message in result.stdout, \
            "The expected rejection message was not printed to stdout/stderr."

        assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
        with open(LOG_PATH, "r") as f:
            log_contents = f.read()

        expected_log = f"[REJECTED] {commit_hash} attempted to provision /home/user/storage/large.qcow2"
        assert expected_log in log_contents, \
            f"Expected log entry '{expected_log}' not found in {LOG_PATH}."


def test_random_images_and_modified_json_are_measured_by_physical_size():
    token = uuid.uuid4().hex
    image_a = f"/home/user/storage/{uuid.uuid4().hex}.qcow2"
    image_b = f"/home/user/storage/{uuid.uuid4().hex}.qcow2"
    image_c = f"/home/user/storage/{uuid.uuid4().hex}.qcow2"
    images = [image_a, image_b, image_c]

    try:
        # All images have virtual capacities above 100 MB. Only image_c is
        # physically allocated above the policy limit.
        for image in images:
            subprocess.run(
                ["qemu-img", "create", "-f", "qcow2", image, "512M"],
                check=True, capture_output=True
            )

        with open(image_c, "r+b", buffering=0) as f:
            os.posix_fallocate(f.fileno(), 0, 106 * 1024 * 1024)

        assert os.stat(image_a).st_blocks * 512 <= LIMIT
        assert os.stat(image_b).st_blocks * 512 <= LIMIT
        assert os.stat(image_c).st_blocks * 512 > LIMIT

        with tempfile.TemporaryDirectory() as tmpdir:
            clone_repo(tmpdir)
            branch = f"verify-{token}"
            config_name = f"vm-{uuid.uuid4().hex}.json"
            config_path = os.path.join(tmpdir, config_name)

            # Exercise an added JSON file with noncanonical formatting and a
            # large virtual capacity but small physical allocation.
            with open(config_path, "w") as f:
                f.write('{\n  "metadata": {"purpose": "dynamic-test"},\n')
                f.write(f'  "image_path" : {json.dumps(image_a)},\n')
                f.write('  "vm_name": "dynamic-a"\n}\n')
            commit_file(tmpdir, config_name, "Add dynamic valid VM")
            result = subprocess.run(
                ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
                cwd=tmpdir, capture_output=True, text=True
            )
            assert result.returncode == 0, \
                f"A randomly named, physically small image was rejected: {result.stderr}"

            # A modified JSON file referencing another physically small image
            # must also remain allowed.
            with open(config_path, "w") as f:
                json.dump({"image_path": image_b, "vm_name": "dynamic-b"}, f, indent=3)
            commit_file(tmpdir, config_name, "Modify dynamic VM to another valid image")
            result = subprocess.run(
                ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
                cwd=tmpdir, capture_output=True, text=True
            )
            assert result.returncode == 0, \
                f"A valid modified JSON file was rejected: {result.stderr}"

            # Modify that same arbitrary file to reference the unpredictably
            # named image whose physical allocation exceeds the threshold.
            with open(config_path, "w") as f:
                f.write('{"vm_name":"dynamic-c", "image_path":')
                f.write(json.dumps(image_c))
                f.write('}\n')
            rejected_commit = commit_file(tmpdir, config_name, "Modify dynamic VM to oversized image")
            result = subprocess.run(
                ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
                cwd=tmpdir, capture_output=True, text=True
            )

            assert result.returncode != 0, \
                "A modified JSON file referencing a physically oversized random image was allowed."
            expected_message = f"FinOps Policy Violation: Image {image_c} is too large."
            assert expected_message in result.stdout or expected_message in result.stderr, \
                "The dynamic oversized image rejection message was not printed."

            assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
            with open(LOG_PATH, "r") as f:
                log_lines = f.read().splitlines()
            expected_log = f"[REJECTED] {rejected_commit} attempted to provision {image_c}"
            assert expected_log in log_lines, \
                f"Exact dynamic rejection log entry '{expected_log}' was not found."
    finally:
        for image in images:
            try:
                os.remove(image)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
