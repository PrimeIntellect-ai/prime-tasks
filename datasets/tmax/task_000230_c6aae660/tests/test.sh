#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import stat
import subprocess


def run_as_user(args):
    return subprocess.run(
        ["runuser", "-u", "user", "--"] + args,
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )


def expected_paths(raw_path):
    with open(raw_path, "rb") as f:
        content = f.read()
    filename = os.path.basename(raw_path)
    stem = os.path.splitext(filename)[0]
    digest = hashlib.md5(content).hexdigest()
    version = f"/home/user/manifests/versions/{stem}_{digest}.json"
    active = f"/home/user/manifests/active/{filename}"
    return content, version, active


def assert_manifest_processed(raw_path):
    content, version_path, active_path = expected_paths(raw_path)
    assert os.path.isfile(version_path), f"Versioned file {version_path} is missing."
    with open(version_path, "rb") as f:
        assert f.read() == content, f"Versioned file {version_path} does not match its raw manifest."
    assert os.path.islink(active_path), f"{active_path} is not a symlink."
    target = os.readlink(active_path)
    resolved = os.path.abspath(os.path.join(os.path.dirname(active_path), target))
    assert resolved == version_path, f"Symlink {active_path} does not point to {version_path}."
    assert os.path.exists(active_path), f"Symlink {active_path} is dangling."


def test_directories_exist():
    dirs = [
        "/home/user/manifests/raw",
        "/home/user/manifests/active",
        "/home/user/manifests/versions",
        "/home/user/logs",
        "/home/user/.config/validator",
    ]
    for directory in dirs:
        assert os.path.isdir(directory), f"Directory {directory} is missing."


def test_init_flag():
    flag_path = "/home/user/.config/validator/init.flag"
    assert os.path.isfile(flag_path), f"File {flag_path} is missing."
    with open(flag_path, "r") as f:
        content = f.read().strip()
    assert content == "READY", f"Expected {flag_path} to contain 'READY', but got '{content}'."


def test_operator_script_exists():
    script_path = "/home/user/operator.py"
    assert os.path.isfile(script_path), f"File {script_path} is missing."
    with open(script_path, "r") as f:
        source = f.read()
    try:
        compile(source, script_path, "exec")
    except SyntaxError as exc:
        assert False, f"{script_path} is not a valid Python script: {exc}"


def test_run_system_sh_executable():
    script_path = "/home/user/run_system.sh"
    assert os.path.isfile(script_path), f"File {script_path} is missing."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."


def test_operator_and_run_system_are_functional():
    token = secrets.token_hex(12)
    name = f"verifier_{token}.json"
    raw_path = os.path.join("/home/user/manifests/raw", name)
    active_path = os.path.join("/home/user/manifests/active", name)

    first_content = (f'{{"generated":"{token}","revision":1}}\n').encode()
    with open(raw_path, "wb") as f:
        f.write(first_content)
    os.chmod(raw_path, 0o644)

    if os.path.lexists(active_path):
        os.unlink(active_path)
    os.symlink("/definitely/dangling", active_path)

    run_as_user(["python3", "/home/user/operator.py"])
    assert_manifest_processed(raw_path)
    first_version = expected_paths(raw_path)[1]

    before = sorted(
        entry for entry in os.listdir("/home/user/manifests/versions")
        if entry.startswith(f"verifier_{token}_")
    )
    run_as_user(["python3", "/home/user/operator.py"])
    after = sorted(
        entry for entry in os.listdir("/home/user/manifests/versions")
        if entry.startswith(f"verifier_{token}_")
    )
    assert after == before, "Re-running operator.py changed the version set for unchanged input."
    assert_manifest_processed(raw_path)

    second_content = (f'{{"generated":"{token}","revision":2}}\n').encode()
    with open(raw_path, "wb") as f:
        f.write(second_content)
    os.chmod(raw_path, 0o644)
    run_as_user(["python3", "/home/user/operator.py"])
    assert_manifest_processed(raw_path)
    second_version = expected_paths(raw_path)[1]
    assert second_version != first_version
    assert os.path.isfile(first_version), "Updating a manifest removed its prior version."

    sequence_token = secrets.token_hex(16)
    sequence_name = f"sequence_{sequence_token}.json"
    sequence_raw = os.path.join("/home/user/manifests/raw", sequence_name)
    sequence_active = os.path.join("/home/user/manifests/active", sequence_name)
    with open(sequence_raw, "wb") as f:
        f.write((f'{{"sequence":"{sequence_token}"}}\n').encode())
    os.chmod(sequence_raw, 0o644)
    if os.path.lexists(sequence_active):
        os.unlink(sequence_active)

    flag_path = "/home/user/.config/validator/init.flag"
    if os.path.lexists(flag_path):
        os.unlink(flag_path)

    operator_path = "/home/user/operator.py"
    validator_path = "/home/user/validator.py"
    operator_backup = f"/tmp/operator-backup-{sequence_token}.py"
    validator_backup = f"/tmp/validator-backup-{sequence_token}.py"
    operator_marker = f"/tmp/operator-marker-{sequence_token}"
    validator_marker = f"/tmp/validator-marker-{sequence_token}"
    expected_report = f"SEQUENCE_OK_{sequence_token}"

    os.replace(operator_path, operator_backup)
    os.replace(validator_path, validator_backup)
    try:
        with open(operator_path, "w") as f:
            f.write(
                "#!/usr/bin/env python3\n"
                "import runpy\n"
                f"open({operator_marker!r}, 'w').write('called')\n"
                f"runpy.run_path({operator_backup!r}, run_name='__main__')\n"
            )
        os.chmod(operator_path, 0o755)

        with open(validator_path, "w") as f:
            f.write(
                "import os, sys\n"
                f"flag = {flag_path!r}\n"
                "if not os.path.isfile(flag) or open(flag, 'rb').read() != b'READY\\n':\n"
                "    sys.exit('init.flag was not initialized before validator execution')\n"
                f"active = {sequence_active!r}\n"
                "if not os.path.islink(active) or not os.path.exists(active):\n"
                "    sys.exit('operator did not activate the generated manifest before validation')\n"
                f"open({validator_marker!r}, 'w').write('called')\n"
                f"print({expected_report!r})\n"
            )
        os.chmod(validator_path, 0o644)

        run_as_user(["/home/user/run_system.sh"])
        assert os.path.isfile(operator_marker), "run_system.sh did not execute /home/user/operator.py."
        assert os.path.isfile(validator_marker), "run_system.sh did not execute /home/user/validator.py."
        with open("/home/user/logs/validation_report.txt", "r") as f:
            assert f.read().strip() == expected_report, "run_system.sh did not redirect validator stdout."
        assert_manifest_processed(sequence_raw)
        with open(flag_path, "rb") as f:
            assert f.read() == b"READY\n", "run_system.sh did not write exactly READY followed by a newline."
    finally:
        if os.path.lexists(operator_path):
            os.unlink(operator_path)
        if os.path.exists(operator_backup):
            os.replace(operator_backup, operator_path)
        if os.path.lexists(validator_path):
            os.unlink(validator_path)
        if os.path.exists(validator_backup):
            os.replace(validator_backup, validator_path)

    # Execute the restored, real artifacts once more and leave the required final report.
    run_as_user(["/home/user/run_system.sh"])


def test_active_symlinks_and_versions():
    active_dir = "/home/user/manifests/active"
    raw_dir = "/home/user/manifests/raw"
    versions_dir = "/home/user/manifests/versions"

    for app in ["app1.json", "app2.json"]:
        raw_path = os.path.join(raw_dir, app)
        active_path = os.path.join(active_dir, app)
        assert os.path.isfile(raw_path), f"Raw file {raw_path} is missing."
        assert os.path.islink(active_path), f"{active_path} is not a symlink."

        with open(raw_path, "rb") as f:
            content = f.read()
        md5_hash = hashlib.md5(content).hexdigest()
        app_name = os.path.splitext(app)[0]
        expected_version_file = f"{app_name}_{md5_hash}.json"
        expected_version_path = os.path.join(versions_dir, expected_version_file)

        assert os.path.isfile(expected_version_path), f"Versioned file {expected_version_path} is missing."
        with open(expected_version_path, "rb") as f:
            assert f.read() == content, f"Versioned file {expected_version_path} differs from {raw_path}."

        target = os.readlink(active_path)
        assert os.path.abspath(os.path.join(active_dir, target)) == expected_version_path, \
            f"Symlink {active_path} does not point to {expected_version_path}."

    for filename in os.listdir(raw_dir):
        if filename.endswith(".json") and os.path.isfile(os.path.join(raw_dir, filename)):
            assert_manifest_processed(os.path.join(raw_dir, filename))


def test_validation_report():
    report_path = "/home/user/logs/validation_report.txt"
    assert os.path.isfile(report_path), f"Validation report {report_path} is missing."
    with open(report_path, "r") as f:
        content = f.read().strip()
    expected = "VALIDATION_SUCCESS: All manifests are active and dependencies met."
    assert content == expected, f"Validation report content mismatch. Expected '{expected}', got '{content}'."


def test_crontab_installed():
    try:
        result = subprocess.run(
            ["crontab", "-u", "user", "-l"],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
    except subprocess.CalledProcessError:
        assert False, "Failed to read user-level crontab or crontab is empty."

    assert "run_system.sh" in result.stdout, "run_system.sh is not scheduled in the user crontab."
    valid = False
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split(None, 5)
        if len(fields) == 6 and fields[:5] == ["*", "*", "*", "*", "*"]:
            if "/home/user/run_system.sh" in fields[5]:
                valid = True
                break
    assert valid, "/home/user/run_system.sh is not scheduled every minute in user's crontab."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
