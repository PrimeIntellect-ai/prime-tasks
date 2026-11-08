#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import subprocess
import tempfile

RESTORED = "/home/user/projects/restored"
ARCHIVE = "/home/user/projects/archive_mount/data/backups/old/backup.arc"


def test_restored_directory_exists():
    assert os.path.isdir("/home/user/projects/restored/"), "/home/user/projects/restored/ directory does not exist."


def test_valid_files_extracted():
    config_path = "/home/user/projects/restored/config.json"
    main_path = "/home/user/projects/restored/main.py"

    assert os.path.isfile(config_path), f"Expected file {config_path} was not extracted."
    assert os.path.isfile(main_path), f"Expected file {main_path} was not extracted."

    with open(config_path, "r") as f:
        assert f.read() == '{"host": "localhost", "port": 8080}', "Content of config.json is incorrect."

    with open(main_path, "r") as f:
        assert f.read() == 'print("Hello World!")', "Content of main.py is incorrect."


def test_corrupted_files_not_extracted():
    app_data_path = "/home/user/projects/restored/app_data.csv"
    readme_path = "/home/user/projects/restored/readme.txt"

    assert not os.path.exists(app_data_path), f"Corrupted file {app_data_path} should not have been extracted."
    assert not os.path.exists(readme_path), f"Corrupted file {readme_path} should not have been extracted."


def test_corrupted_log():
    log_path = "/home/user/projects/restored/corrupted.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert "app_data.csv" in lines, "app_data.csv is missing from corrupted.log"
    assert "readme.txt" in lines, "readme.txt is missing from corrupted.log"
    assert len(lines) == 2, f"corrupted.log should contain exactly 2 entries, found {len(lines)}"


def find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"__pycache__", ".cache", ".local"}]
        for name in files:
            path = os.path.join(root, name)
            if not os.path.isfile(path):
                continue
            is_python = name.endswith(".py")
            if not is_python:
                try:
                    with open(path, "rb") as f:
                        is_python = b"python" in f.readline(256).lower() and f.tell() <= 256
                except OSError:
                    continue
            if is_python:
                scripts.append(path)
    return sorted(set(scripts))


def make_entry(filename, content, valid):
    digest = hashlib.md5(content).hexdigest()
    if not valid:
        digest = ("0" if digest[0] != "0" else "1") + digest[1:]
    return (
        f"===FILENAME: {filename}===\n"
        f"===CHECKSUM: {digest}===\n"
        f"{content.hex()}\n"
        "===END_FILE===\n"
    )


def test_python_parser_executes_and_handles_unseen_archive():
    candidates = find_python_scripts()
    assert candidates, "No Python extraction script was found under /home/user."

    token = secrets.token_hex(8)
    valid_files = {
        f"valid_text_{token}.dat": b"unseen archive payload\nwith two lines\n",
        f"valid_binary_{token}.bin": bytes(range(256)),
    }
    corrupt_files = {
        f"bad_alpha_{token}.dat": b"this entry has a deliberately wrong checksum",
        f"bad_beta_{token}.bin": b"\x00\xff\x10corrupt\x80",
    }

    archive_text = ""
    archive_text += make_entry(next(iter(valid_files)), next(iter(valid_files.values())), True)
    archive_text += make_entry(next(iter(corrupt_files)), next(iter(corrupt_files.values())), False)
    archive_text += make_entry(list(valid_files)[1], list(valid_files.values())[1], True)
    archive_text += make_entry(list(corrupt_files)[1], list(corrupt_files.values())[1], False)

    with open(ARCHIVE, "rb") as f:
        original_archive = f.read()

    temp_root = tempfile.mkdtemp(prefix="archive_verifier_")
    baseline = os.path.join(temp_root, "restored_baseline")
    shutil.copytree(RESTORED, baseline)
    attempts = []
    passed = False

    try:
        for script in candidates:
            if os.path.isdir(RESTORED):
                shutil.rmtree(RESTORED)
            shutil.copytree(baseline, RESTORED)

            for name in ["config.json", "main.py", "app_data.csv", "readme.txt", "corrupted.log", *valid_files, *corrupt_files]:
                path = os.path.join(RESTORED, name)
                if os.path.lexists(path):
                    if os.path.isdir(path) and not os.path.islink(path):
                        shutil.rmtree(path)
                    else:
                        os.unlink(path)

            with open(ARCHIVE, "w", encoding="ascii") as f:
                f.write(archive_text)

            if not os.path.isfile(script):
                attempts.append(f"{script}: script disappeared before execution")
                continue

            try:
                result = subprocess.run(
                    ["python3", script],
                    cwd=os.path.dirname(script) or "/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )
            except subprocess.TimeoutExpired:
                attempts.append(f"{script}: timed out")
                continue

            if result.returncode != 0:
                attempts.append(f"{script}: exited with status {result.returncode}")
                continue

            errors = []
            for name, expected in valid_files.items():
                path = os.path.join(RESTORED, name)
                if not os.path.isfile(path):
                    errors.append(f"did not extract {name}")
                else:
                    with open(path, "rb") as f:
                        if f.read() != expected:
                            errors.append(f"decoded {name} incorrectly")

            for name in corrupt_files:
                if os.path.exists(os.path.join(RESTORED, name)):
                    errors.append(f"extracted corrupt entry {name}")

            log_path = os.path.join(RESTORED, "corrupted.log")
            if not os.path.isfile(log_path):
                errors.append("did not create corrupted.log")
            else:
                with open(log_path, "r", encoding="utf-8") as f:
                    lines = [line.strip() for line in f if line.strip()]
                if sorted(lines) != sorted(corrupt_files):
                    errors.append(f"incorrect corrupted.log entries: {lines!r}")

            if not errors:
                passed = True
                break
            attempts.append(f"{script}: " + "; ".join(errors))
    finally:
        with open(ARCHIVE, "wb") as f:
            f.write(original_archive)
        if os.path.isdir(RESTORED):
            shutil.rmtree(RESTORED)
        shutil.copytree(baseline, RESTORED)
        shutil.rmtree(temp_root)

    assert passed, "No submitted Python script correctly processed an unseen archive. " + " | ".join(attempts)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
