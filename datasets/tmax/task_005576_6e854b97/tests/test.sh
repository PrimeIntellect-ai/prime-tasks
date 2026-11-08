#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import shutil
import subprocess
import tarfile
import tempfile
import uuid

EXPECTED_CONTENTS = {
    "server_alpha/app.conf": "ServerName alpha\nPort 443\nLogLevel warn\n# Valid comment\n",
    "server_alpha/system.conf": "OS Linux\nMemory 16G\n",
    "server_alpha/legacy.conf": "OldSetting 1\nPort 443\n",
    "server_beta/db.conf": "DBName beta\nPort 443\nLogLevel info\n",
    "server_beta/cache.conf": "CacheSize 1G\nLogLevel warn\n",
    "server_gamma/web.conf": "Worker 4\nPort 80\nLogLevel warn\n",
}


def test_changelog_content():
    changelog_path = "/home/user/changelog.txt"
    assert os.path.exists(changelog_path), f"Changelog file missing at {changelog_path}"

    expected_content = (
        "Modified files:\n"
        "server_alpha/app.conf\n"
        "server_alpha/legacy.conf\n"
        "server_beta/cache.conf\n"
        "server_beta/db.conf\n"
        "Total modified: 4\n"
    )

    with open(changelog_path, "r") as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), (
        f"Changelog content does not match expected output.\n"
        f"Expected:\n{expected_content}\nGot:\n{content}"
    )


def test_normalized_archive_exists_and_structure():
    archive_path = "/home/user/normalized_configs.tar.gz"
    assert os.path.exists(archive_path), f"Normalized archive missing at {archive_path}"
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar.gz file"

    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()

        expected_files = [
            "server_alpha/app.conf",
            "server_alpha/system.conf",
            "server_alpha/legacy.conf",
            "server_beta/db.conf",
            "server_beta/cache.conf",
            "server_gamma/web.conf",
        ]

        for expected in expected_files:
            assert expected in names, f"Expected file {expected} not found at root of {archive_path}"

        for name in names:
            assert not name.startswith("extracted/"), (
                f"Archive incorrectly contains 'extracted/' prefix: {name}"
            )


def test_normalized_archive_contents():
    archive_path = "/home/user/normalized_configs.tar.gz"
    assert os.path.exists(archive_path), f"Normalized archive missing at {archive_path}"

    with tarfile.open(archive_path, "r:gz") as tar:
        for fname, expected_text in EXPECTED_CONTENTS.items():
            try:
                member = tar.extractfile(fname)
                assert member is not None, f"File {fname} is not a regular file in archive"
                content = member.read().decode("utf-8")
                assert content == expected_text, (
                    f"Content mismatch in {fname}.\n"
                    f"Expected:\n{expected_text}\nGot:\n{content}"
                )
            except KeyError:
                assert False, f"File {fname} missing from archive"


def test_script_exists():
    possible_scripts = glob.glob("/home/user/normalize.*")
    valid_extensions = {".py", ".sh", ".rb", ".pl"}

    found = False
    for script in possible_scripts:
        ext = os.path.splitext(script)[1]
        if ext in valid_extensions and os.path.isfile(script):
            found = True
            break

    assert found, "Could not find normalize script (e.g., normalize.py, normalize.sh) in /home/user/"


def test_extracted_directory_final_state():
    extracted = "/home/user/extracted"
    assert os.path.isdir(extracted), f"Extracted directory missing at {extracted}"

    for relative_path, expected_text in EXPECTED_CONTENTS.items():
        path = os.path.join(extracted, relative_path)
        assert os.path.isfile(path), f"Expected extracted file missing: {path}"
        with open(path, "r") as f:
            content = f.read()
        assert content == expected_text, (
            f"Content mismatch in extracted file {relative_path}.\n"
            f"Expected:\n{expected_text}\nGot:\n{content}"
        )


def test_normalization_script_behavior():
    extracted = "/home/user/extracted"
    changelog = "/home/user/changelog.txt"
    candidates = [
        path for path in sorted(glob.glob("/home/user/normalize.*"))
        if os.path.isfile(path) and os.path.splitext(path)[1] in {".py", ".sh", ".rb", ".pl"}
    ]
    assert candidates, "No normalization script available to execute"

    commands = {
        ".py": ["python3"],
        ".sh": ["bash"],
        ".rb": ["ruby"],
        ".pl": ["perl"],
    }

    token = uuid.uuid4().hex
    probe_relative = f"server_probe_{token}/nested/probe.conf"
    unchanged_relative = f"server_probe_{token}/nested/unchanged.conf"
    probe_input = (
        f"Marker {token}\n"
        "Port 8080\n"
        "LogLevel debug\n"
        f"  # DEPRECATED remove-{token}\n"
        "Port 80800\n"
    )
    probe_expected = (
        f"Marker {token}\n"
        "Port 443\n"
        "LogLevel warn\n"
        "Port 80800\n"
    )
    unchanged_text = f"Marker {token}\nPort 80\nLogLevel warn\n# Valid comment\n"
    expected_log = f"Modified files:\n{probe_relative}\nTotal modified: 1\n"

    errors = []
    with tempfile.TemporaryDirectory() as temp_dir:
        baseline = os.path.join(temp_dir, "extracted")
        shutil.copytree(extracted, baseline)
        with open(changelog, "rb") as f:
            baseline_log = f.read()

        for script in candidates:
            if os.path.exists(extracted):
                shutil.rmtree(extracted)
            shutil.copytree(baseline, extracted)
            with open(changelog, "wb") as f:
                f.write(baseline_log)

            probe_path = os.path.join(extracted, probe_relative)
            unchanged_path = os.path.join(extracted, unchanged_relative)
            os.makedirs(os.path.dirname(probe_path), exist_ok=True)
            with open(probe_path, "w") as f:
                f.write(probe_input)
            with open(unchanged_path, "w") as f:
                f.write(unchanged_text)

            ext = os.path.splitext(script)[1]
            interpreter = commands[ext][0]
            if shutil.which(interpreter) is None:
                errors.append(f"{script}: required interpreter {interpreter} is unavailable")
                continue

            try:
                result = subprocess.run(
                    commands[ext] + [script],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
                assert result.returncode == 0, (
                    f"script exited with {result.returncode}; stderr: {result.stderr}"
                )
                with open(probe_path, "r") as f:
                    assert f.read() == probe_expected, "probe configuration was not normalized correctly"
                with open(unchanged_path, "r") as f:
                    assert f.read() == unchanged_text, "unchanged configuration was modified"
                with open(changelog, "r") as f:
                    assert f.read() == expected_log, "script did not generate the expected dynamic changelog"

                for relative_path, expected_text in EXPECTED_CONTENTS.items():
                    with open(os.path.join(extracted, relative_path), "r") as f:
                        assert f.read() == expected_text, (
                            f"script damaged existing normalized file {relative_path}"
                        )
                return
            except (AssertionError, OSError, subprocess.TimeoutExpired) as exc:
                errors.append(f"{script}: {exc}")

    assert False, "No normalization script passed behavioral execution:\n" + "\n".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
