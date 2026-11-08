#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_operator.py
import collections
import os
import pwd
import re
import shutil
import stat
import subprocess
import tarfile
import uuid

SCRIPT = "/home/user/operator.sh"
ACTIVE = "/home/user/active_manifests"
INCOMING = "/home/user/incoming_manifests"
BACKUPS = "/home/user/backups"
BACKUP = "/home/user/backups/manifest_backup.tar.gz"
FSTAB = "/home/user/mock_fstab"
FW_RULES = "/home/user/fw_rules.sh"


def test_operator_script_exists_and_executable():
    script_path = "/home/user/operator.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert st.st_mode & stat.S_IXUSR, f"Script {script_path} is not executable."


def test_backup_archive_created():
    backup_path = "/home/user/backups/manifest_backup.tar.gz"
    assert os.path.isfile(backup_path), f"Backup archive {backup_path} does not exist."

    with tarfile.open(backup_path, "r:gz") as tar:
        names = tar.getnames()
        assert any(name.endswith("old-config.yaml") for name in names), "Backup archive does not contain 'old-config.yaml'."


def test_manifests_synced():
    active_dir = "/home/user/active_manifests"
    for filename in ["pv-data.yaml", "svc-web.yaml", "svc-api.yaml"]:
        assert os.path.isfile(os.path.join(active_dir, filename)), f"File {filename} was not synced to {active_dir}."


def test_mock_fstab_generated():
    fstab_path = "/home/user/mock_fstab"
    assert os.path.isfile(fstab_path), f"File {fstab_path} does not exist."
    with open(fstab_path, "r") as f:
        content = f.read().strip().splitlines()
    expected_line = "/home/user/raw_data /mnt/data/db-volume none bind 0 0"
    assert expected_line in content, f"Expected line '{expected_line}' not found in {fstab_path}."


def test_fw_rules_generated():
    fw_rules_path = "/home/user/fw_rules.sh"
    assert os.path.isfile(fw_rules_path), f"File {fw_rules_path} does not exist."
    with open(fw_rules_path, "r") as f:
        content = f.read().strip().splitlines()
    expected_rules = [
        "iptables -A INPUT -p tcp --dport 30080 -j ACCEPT",
        "iptables -A INPUT -p tcp --dport 30443 -j ACCEPT",
    ]
    for rule in expected_rules:
        assert rule in content, f"Expected rule '{rule}' not found in {fw_rules_path}."


def write_file(directory, name, content):
    path = os.path.join(directory, name)
    with open(path, "w") as f:
        f.write(content)
    return path


def read_regular_files(directory):
    result = {}
    for name in os.listdir(directory):
        path = os.path.join(directory, name)
        if os.path.isfile(path):
            with open(path, "rb") as f:
                result[name] = f.read()
    return result


def expected_outputs():
    mounts = []
    rules = []
    for name in os.listdir(ACTIVE):
        if not name.endswith(".yaml"):
            continue
        path = os.path.join(ACTIVE, name)
        if not os.path.isfile(path):
            continue
        with open(path, "r") as f:
            text = f.read()
        if re.search(r"^kind: PersistentVolume$", text, re.MULTILINE):
            volume = re.search(r"^  name: (.+)$", text, re.MULTILINE)
            host_path = re.search(r"^    path: (.+)$", text, re.MULTILINE)
            assert volume and host_path
            mounts.append(f"{host_path.group(1)} /mnt/data/{volume.group(1)} none bind 0 0")
        if re.search(r"^kind: Service$", text, re.MULTILINE):
            port = re.search(r"^    nodePort: ([0-9]+)$", text, re.MULTILINE)
            assert port
            rules.append(f"iptables -A INPUT -p tcp --dport {port.group(1)} -j ACCEPT")
    return mounts, rules


def assert_backup_equals(expected):
    assert os.path.isfile(BACKUP), "The operator did not create the backup archive"
    with tarfile.open(BACKUP, "r:gz") as tar:
        archived = {}
        for member in tar.getmembers():
            if member.isfile():
                extracted = tar.extractfile(member)
                assert extracted is not None
                basename = os.path.basename(member.name.rstrip("/"))
                assert basename not in archived, f"Duplicate archived basename: {basename}"
                archived[basename] = extracted.read()
    assert archived == expected, "Backup does not exactly contain the pre-sync active manifests"


def assert_synced():
    incoming = read_regular_files(INCOMING)
    active = read_regular_files(ACTIVE)
    for name, data in incoming.items():
        assert name in active, f"Incoming file {name} was not copied"
        assert active[name] == data, f"Active file {name} does not match its incoming source"


def output_lines(path):
    assert os.path.isfile(path), f"Expected output file {path} was not created"
    with open(path, "r") as f:
        return [line.rstrip("\n") for line in f if line.rstrip("\n")]


def assert_generated_outputs():
    mounts, rules = expected_outputs()
    assert collections.Counter(output_lines(FSTAB)) == collections.Counter(mounts), \
        "mock_fstab does not exactly match the current PersistentVolume manifests"
    assert collections.Counter(output_lines(FW_RULES)) == collections.Counter(rules), \
        "fw_rules.sh does not exactly match the current Service manifests"


def run_as_user():
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        env={**os.environ, "HOME": "/home/user", "USER": "user"},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        preexec_fn=demote,
    )
    assert result.returncode == 0, f"operator.sh failed as user:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def chown_tree(path):
    account = pwd.getpwnam("user")
    for root, dirs, files in os.walk(path):
        os.chown(root, account.pw_uid, account.pw_gid)
        for name in dirs + files:
            os.chown(os.path.join(root, name), account.pw_uid, account.pw_gid)


def test_operator_executes_dynamic_and_repeated_workflow():
    token = uuid.uuid4().hex[:10]
    port1 = 31000 + (int(token[:4], 16) % 1000)
    port2 = 32000 + (int(token[4:8], 16) % 700)

    for path in (ACTIVE, INCOMING, BACKUPS):
        shutil.rmtree(path, ignore_errors=True)
        os.makedirs(path)
    for path in (FSTAB, FW_RULES):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    write_file(ACTIVE, "retained.yaml", "kind: ConfigMap\nmetadata:\n  name: retained-" + token + "\n")
    write_file(ACTIVE, "overwritten.yaml", "kind: ConfigMap\nmetadata:\n  name: old-version\n")
    write_file(ACTIVE, "retained-pv.yaml", f"kind: PersistentVolume\nmetadata:\n  name: retained-{token}\nspec:\n  hostPath:\n    path: /tmp/retained-{token}\n")

    write_file(INCOMING, "overwritten.yaml", f"kind: Service\nmetadata:\n  name: replacement-{token}\nspec:\n  ports:\n    nodePort: {port1}\n")
    write_file(INCOMING, "dynamic-pv.yaml", f"kind: PersistentVolume\nmetadata:\n  name: volume-{token}\nspec:\n  hostPath:\n    path: /tmp/data-{token}\n")
    write_file(INCOMING, "ignored.txt", "kind: Service\n    nodePort: 39999\n")
    chown_tree(ACTIVE)
    chown_tree(INCOMING)
    chown_tree(BACKUPS)

    first_backup_expected = read_regular_files(ACTIVE)
    run_as_user()
    assert_backup_equals(first_backup_expected)
    assert_synced()
    assert_generated_outputs()

    second_backup_expected = read_regular_files(ACTIVE)
    write_file(INCOMING, "dynamic-pv.yaml", f"kind: PersistentVolume\nmetadata:\n  name: changed-{token}\nspec:\n  hostPath:\n    path: /tmp/changed-{token}\n")
    write_file(INCOMING, "second-service.yaml", f"kind: Service\nmetadata:\n  name: second-{token}\nspec:\n  ports:\n    nodePort: {port2}\n")

    run_as_user()
    assert_backup_equals(second_backup_expected)
    assert_synced()
    assert_generated_outputs()
TEST_EOF

if python3 -m pytest /tmp/test_operator.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
