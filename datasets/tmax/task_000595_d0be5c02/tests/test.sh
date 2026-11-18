#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_operator.py
import os
import re
import stat
import shutil
import subprocess
import sys
import tarfile
import uuid
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import yaml

BASE = "/home/user/k8s-operator"
SCRIPT = os.path.join(BASE, "operator.py")
TOKYO = ZoneInfo("Asia/Tokyo")
ANNOTATION = "operator.k8s.io/processed-at"
ANNOTATION_RE = re.compile(r'operator\.k8s\.io/processed-at:\s*"?\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \+0900"?')
BACKUP_RE = re.compile(r"^backup_\d{8}_\d{6}\.tar\.gz$")
LOG_RE = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \+0900)\] SUCCESS: Backed up to (backup_\d{8}_\d{6}\.tar\.gz) and processed (\d+) manifests\.$")


def assert_true(value, message):
    if not value:
        raise AssertionError(message)


def reset_dir(path):
    if os.path.lexists(path):
        if os.path.islink(path) or not os.path.isdir(path):
            os.unlink(path)
            os.makedirs(path)
        else:
            for entry in os.listdir(path):
                target = os.path.join(path, entry)
                if os.path.isdir(target) and not os.path.islink(target):
                    shutil.rmtree(target)
                else:
                    os.unlink(target)
    else:
        os.makedirs(path)


def prepare(active_files, incoming_files):
    for name in ("active", "incoming", "backups"):
        reset_dir(os.path.join(BASE, name))
    log_path = os.path.join(BASE, "operator.log")
    if os.path.lexists(log_path):
        if os.path.isdir(log_path) and not os.path.islink(log_path):
            shutil.rmtree(log_path)
        else:
            os.unlink(log_path)
    config_dir = os.path.join(BASE, "config")
    os.makedirs(config_dir, exist_ok=True)
    with open(os.path.join(config_dir, "operator.ini"), "w", encoding="utf-8") as f:
        f.write("[settings]\ntimezone = Asia/Tokyo\nbackup_format = tar.gz\n")
    for name, content in active_files.items():
        with open(os.path.join(BASE, "active", name), "w", encoding="utf-8") as f:
            f.write(content)
    for name, content in incoming_files.items():
        with open(os.path.join(BASE, "incoming", name), "w", encoding="utf-8") as f:
            f.write(content)


def run_operator():
    before = datetime.now(TOKYO)
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd=BASE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    after = datetime.now(TOKYO)
    assert_true(result.returncode == 0, f"operator.py failed with exit code {result.returncode}:\nstdout={result.stdout}\nstderr={result.stderr}")
    return before, after


def parse_current_timestamp(value, before, after, label):
    assert_true(isinstance(value, str), f"{label} must be a YAML string")
    try:
        parsed = datetime.strptime(value, "%Y-%m-%d %H:%M:%S %z")
    except ValueError as exc:
        raise AssertionError(f"{label} has an invalid timestamp: {value}") from exc
    assert_true(parsed.utcoffset() == timedelta(hours=9), f"{label} is not in Asia/Tokyo: {value}")
    slack = timedelta(seconds=3)
    assert_true(before - slack <= parsed <= after + slack, f"{label} is not the current Tokyo time: {value}")
    return parsed


def backup_info(before, after):
    backup_dir = os.path.join(BASE, "backups")
    files = os.listdir(backup_dir)
    tar_files = [name for name in files if name.endswith(".tar.gz")]
    assert_true(len(tar_files) == 1, f"Expected exactly 1 tar.gz file in backups, found {len(tar_files)}")
    name = tar_files[0]
    assert_true(BACKUP_RE.fullmatch(name) is not None, f"Backup filename {name} does not match required format.")
    stamp = datetime.strptime(name, "backup_%Y%m%d_%H%M%S.tar.gz").replace(tzinfo=TOKYO)
    slack = timedelta(seconds=3)
    assert_true(before - slack <= stamp <= after + slack, f"Backup filename does not use the current Tokyo time: {name}")
    return name, os.path.join(backup_dir, name)


def archive_files(path):
    result = {}
    with tarfile.open(path, "r:gz") as archive:
        for member in archive.getmembers():
            normalized = member.name[2:] if member.name.startswith("./") else member.name
            if normalized in ("", "."):
                continue
            assert_true("/" not in normalized.rstrip("/"), f"Archive member is not at the archive root: {member.name}")
            if member.isfile():
                stream = archive.extractfile(member)
                assert_true(stream is not None, f"Could not extract {member.name} from backup")
                result[normalized] = stream.read()
    return result


def load_manifest(name):
    path = os.path.join(BASE, "active", name)
    assert_true(os.path.isfile(path), f"Active manifest missing: {path}")
    with open(path, "r", encoding="utf-8") as f:
        raw = f.read()
    data = yaml.safe_load(raw)
    assert_true(isinstance(data, dict), f"Active manifest is not a YAML mapping: {name}")
    metadata = data.get("metadata")
    assert_true(isinstance(metadata, dict), f"metadata is missing or invalid in {name}")
    annotations = metadata.get("annotations")
    assert_true(isinstance(annotations, dict), f"metadata.annotations is missing or invalid in {name}")
    assert_true(ANNOTATION in annotations, f"Processed-at annotation is not under metadata.annotations in {name}")
    return raw, data, annotations[ANNOTATION]


def check_log(expected_backup, expected_count, before, after, require_original_pattern=False):
    path = os.path.join(BASE, "operator.log")
    assert_true(os.path.isfile(path), f"Log file missing: {path}")
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().strip().split("\n")
    assert_true(len(lines) >= 1 and lines[-1], "Log file is empty.")
    last = lines[-1]
    if require_original_pattern:
        original = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \+0900\] SUCCESS: Backed up to backup_\d{8}_\d{6}\.tar\.gz and processed 2 manifests\.$")
        assert_true(original.fullmatch(last) is not None, f"Log line does not match required format: {last}")
    match = LOG_RE.fullmatch(last)
    assert_true(match is not None, f"Log line does not match required format: {last}")
    assert_true(match.group(2) == expected_backup, "Log does not name the backup that was created")
    assert_true(int(match.group(3)) == expected_count, f"Log has the wrong processed manifest count: {last}")
    parse_current_timestamp(match.group(1), before, after, "log timestamp")


def initial_fixture_test():
    old_app = "apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: my-app\nspec:\n  replicas: 1\n"
    new_app = "apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: my-app\nspec:\n  replicas: 3\n"
    service = "apiVersion: v1\nkind: Service\nmetadata:\n  name: my-service\nspec:\n  ports:\n  - port: 80\n"
    prepare({"app.yaml": old_app}, {"app.yaml": new_app, "service.yaml": service})
    before, after = run_operator()

    backup_name, backup_path = backup_info(before, after)
    archived = archive_files(backup_path)
    assert_true("app.yaml" in archived, "Backup does not contain app.yaml at the root level.")
    backup_content = archived["app.yaml"].decode("utf-8")
    assert_true("replicas: 1" in backup_content, "Backup app.yaml does not contain 'replicas: 1' (it should be the original file).")
    assert_true(ANNOTATION not in backup_content, "Backup app.yaml should not contain the processed-at annotation.")

    app_raw, app_data, app_stamp = load_manifest("app.yaml")
    service_raw, _, service_stamp = load_manifest("service.yaml")
    assert_true("replicas: 3" in app_raw, "Active app.yaml does not have 'replicas: 3' from incoming.")
    assert_true(ANNOTATION_RE.search(app_raw) is not None, "Active app.yaml missing correctly formatted processed-at annotation.")
    assert_true(ANNOTATION_RE.search(service_raw) is not None, "Active service.yaml missing correctly formatted processed-at annotation.")
    assert_true(app_data.get("spec", {}).get("replicas") == 3, "Active app.yaml did not preserve the incoming replicas value")
    parse_current_timestamp(app_stamp, before, after, "app.yaml annotation")
    parse_current_timestamp(service_stamp, before, after, "service.yaml annotation")

    incoming = os.listdir(os.path.join(BASE, "incoming"))
    assert_true(len(incoming) == 0, f"Incoming directory is not empty: {incoming}")
    check_log(backup_name, 2, before, after, require_original_pattern=True)


def randomized_fixture_test():
    token = uuid.uuid4().hex
    workload_name = f"workload_{token}.yaml"
    service_name = f"service_{token}.yaml"
    replicas = 4 + (int(token[:4], 16) % 20)
    port = 10000 + (int(token[4:8], 16) % 40000)

    old_workload = (
        "apiVersion: apps/v1\nkind: Deployment\nmetadata:\n"
        f"  name: old-{token}\n  labels:\n    fixture: old-{token}\n"
        "spec:\n  replicas: 1\n"
    )
    new_workload = (
        "apiVersion: apps/v1\nkind: Deployment\nmetadata:\n"
        f"  name: new-{token}\n  labels:\n    fixture: incoming-{token}\n"
        f"spec:\n  replicas: {replicas}\n"
    )
    new_service = (
        "apiVersion: v1\nkind: Service\nmetadata:\n"
        f"  name: svc-{token}\n"
        f"spec:\n  selector:\n    fixture: incoming-{token}\n  ports:\n  - port: {port}\n"
    )

    prepare({workload_name: old_workload}, {workload_name: new_workload, service_name: new_service})
    before, after = run_operator()
    backup_name, backup_path = backup_info(before, after)
    archived = archive_files(backup_path)
    assert_true(set(archived) == {workload_name}, f"Backup did not contain exactly the pre-run active files: {sorted(archived)}")
    assert_true(archived[workload_name] == old_workload.encode("utf-8"), "Backup content is not the pre-run active manifest")

    workload_raw, workload, workload_stamp = load_manifest(workload_name)
    service_raw, service, service_stamp = load_manifest(service_name)
    assert_true(ANNOTATION_RE.search(workload_raw) is not None, "Random workload annotation text has the wrong format")
    assert_true(ANNOTATION_RE.search(service_raw) is not None, "Random service annotation text has the wrong format")
    assert_true(workload.get("metadata", {}).get("name") == f"new-{token}", "Incoming workload was not deployed")
    assert_true(workload.get("metadata", {}).get("labels", {}).get("fixture") == f"incoming-{token}", "Workload content was not preserved")
    assert_true(workload.get("spec", {}).get("replicas") == replicas, "Random workload replicas were not preserved")
    assert_true(service.get("metadata", {}).get("name") == f"svc-{token}", "Incoming service was not deployed")
    assert_true(service.get("spec", {}).get("ports", [{}])[0].get("port") == port, "Random service port was not preserved")
    parse_current_timestamp(workload_stamp, before, after, "random workload annotation")
    parse_current_timestamp(service_stamp, before, after, "random service annotation")

    incoming = os.listdir(os.path.join(BASE, "incoming"))
    assert_true(len(incoming) == 0, f"Incoming directory is not empty after randomized run: {incoming}")
    check_log(backup_name, 2, before, after)


def main():
    assert_true(os.path.isfile(SCRIPT), f"Operator script missing: {SCRIPT}")
    assert_true(not os.path.islink(SCRIPT), "operator.py must be a regular file, not a symlink")
    mode = os.stat(SCRIPT).st_mode
    assert_true(stat.S_ISREG(mode), "operator.py is not a regular file")
    assert_true(os.path.getsize(SCRIPT) > 0, "operator.py is empty")
    initial_fixture_test()
    randomized_fixture_test()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_operator.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
