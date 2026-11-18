#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import subprocess
import sys
import uuid

OPERATOR = "/home/user/operator.py"
MANIFEST = "/home/user/k8s_manifests/app.yaml"
BACKUPS_DIR = "/home/user/k8s_backups"
MAIL_DIR = "/home/user/mail_spool"

INITIAL_CONTENT = (
    b"apiVersion: apps/v1\n"
    b"kind: Deployment\n"
    b"metadata:\n"
    b"  name: my-app\n"
)
MODIFIED_CONTENT = INITIAL_CONTENT + b"\n  # modified\n"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def expected_email(filename, digest):
    return (
        f"To: admin@local\n"
        f"Subject: Manifest Backup: {filename}\n"
        f"Hash: {digest}"
    )


def snapshot_dirs():
    result = {}
    for directory in (BACKUPS_DIR, MAIL_DIR):
        for path in sorted(glob.glob(os.path.join(directory, "*"))):
            if os.path.isfile(path):
                stat = os.stat(path)
                with open(path, "rb") as f:
                    data = f.read()
                result[path] = (data, stat.st_mtime_ns)
    return result


def run_operator():
    result = subprocess.run(
        [sys.executable, OPERATOR],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"operator.py exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_operator_script_exists():
    assert os.path.exists(OPERATOR), "The operator script /home/user/operator.py is missing."
    assert os.path.isfile(OPERATOR), "/home/user/operator.py is not a file."


def test_manifest_modified_correctly():
    assert os.path.exists(MANIFEST), f"Manifest file {MANIFEST} not found."

    with open(MANIFEST, "rb") as f:
        content = f.read()

    assert content.endswith(b"\n  # modified\n"), (
        "Manifest was not modified correctly with '\\n  # modified\\n'."
    )
    assert content == MODIFIED_CONTENT, (
        "app.yaml does not contain the required initial manifest followed by exactly "
        "'\\n  # modified\\n'."
    )


def test_backups_and_emails_exist_and_match():
    assert os.path.isdir(BACKUPS_DIR), f"Directory {BACKUPS_DIR} not found."
    assert os.path.isdir(MAIL_DIR), f"Directory {MAIL_DIR} not found."

    backups = glob.glob(os.path.join(BACKUPS_DIR, "app.yaml.*.bak"))
    assert len(backups) == 2, (
        f"Expected exactly 2 backup files in {BACKUPS_DIR}, found {len(backups)}."
    )

    emails = glob.glob(os.path.join(MAIL_DIR, "app.yaml.*.eml"))
    assert len(emails) == 2, (
        f"Expected exactly 2 email files in {MAIL_DIR}, found {len(emails)}."
    )

    expected_versions = {
        sha256(INITIAL_CONTENT): INITIAL_CONTENT,
        sha256(MODIFIED_CONTENT): MODIFIED_CONTENT,
    }
    observed_hashes = set()

    for backup in backups:
        filename = os.path.basename(backup)
        parts = filename.split(".")
        assert len(parts) >= 4, f"Backup filename {filename} does not match expected format."
        hash_val = parts[-2]
        assert len(hash_val) == 64 and all(c in "0123456789abcdef" for c in hash_val), (
            f"Backup filename {filename} does not contain a lowercase SHA-256 hash."
        )

        eml_file = os.path.join(MAIL_DIR, f"app.yaml.{hash_val}.eml")
        assert os.path.exists(eml_file), f"Missing corresponding email file for hash {hash_val}."

        with open(eml_file, "r") as f:
            eml_content = f.read()

        expected_eml = f"To: admin@local\nSubject: Manifest Backup: app.yaml\nHash: {hash_val}"
        assert expected_eml.strip() in eml_content.strip(), (
            f"Email content incorrect in {eml_file}."
        )

        with open(backup, "rb") as f:
            backup_content = f.read()
        actual_hash = sha256(backup_content)
        assert actual_hash == hash_val, (
            f"Backup {filename} content does not match the SHA-256 hash in its filename."
        )
        assert hash_val in expected_versions, f"Unexpected app.yaml version in {filename}."
        assert backup_content == expected_versions[hash_val], (
            f"Backup {filename} does not contain the required manifest version."
        )
        assert eml_content == expected_email("app.yaml", hash_val), (
            f"Email content in {eml_file} is not exact."
        )
        observed_hashes.add(hash_val)

    assert observed_hashes == set(expected_versions), (
        "The two backups are not the required initial and modified app.yaml versions."
    )


def test_operator_executes_and_is_idempotent():
    before = snapshot_dirs()
    run_operator()
    assert snapshot_dirs() == before, (
        "Running operator.py on already-backed-up manifests was not idempotent."
    )

    probe_name = f"verifier-{uuid.uuid4().hex}.yaml"
    probe_path = os.path.join("/home/user/k8s_manifests", probe_name)
    probe_content = os.urandom(37) + b"\nkind: ConfigMap\n"
    probe_hash = sha256(probe_content)
    probe_backup = os.path.join(BACKUPS_DIR, f"{probe_name}.{probe_hash}.bak")
    probe_email = os.path.join(MAIL_DIR, f"{probe_name}.{probe_hash}.eml")

    try:
        with open(probe_path, "wb") as f:
            f.write(probe_content)

        run_operator()

        assert os.path.isfile(probe_backup), (
            "operator.py did not create the correctly named backup for a new YAML manifest."
        )
        with open(probe_backup, "rb") as f:
            assert f.read() == probe_content, "The new backup does not match its manifest."

        assert os.path.isfile(probe_email), (
            "operator.py did not create the correctly named email for a new YAML manifest."
        )
        with open(probe_email, "r") as f:
            assert f.read() == expected_email(probe_name, probe_hash), (
                "The new email notification content is not exact."
            )

        after_first = snapshot_dirs()
        run_operator()
        assert snapshot_dirs() == after_first, (
            "A second operator run changed files for an already-backed-up version."
        )
    finally:
        for path in (probe_path, probe_backup, probe_email):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
