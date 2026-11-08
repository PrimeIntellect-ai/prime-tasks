#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import json
import os
import runpy
import secrets

SCRIPT_PATH = "/home/user/organizer.py"
SOURCE_DIR = "/home/user/project_logs"
TARGET_DIR = "/home/user/organized_logs"
CONFIG_PATH = "/home/user/organizer_config.json"

ORIGINAL_LOGS = {
    "security_logs/warning_x99_auth.log": """[INFO] 2023-10-25 10:00:00 Boot sequence initiated
[DEBUG] Fetching user payload
<<<JSON_START>>>
{
  "module": "auth",
  "severity": "warning",
  "id": "x99_auth"
}
<<<JSON_END>>>
[INFO] 2023-10-25 10:00:01 Boot sequence completed
""",
    "backend_logs/critical_db_88_conn.log": """[ERROR] Connection timeout
[DEBUG] Retrying connection
<<<JSON_START>>>
{
  "module": "database",
  "severity": "critical",
  "id": "db_88_conn"
}
<<<JSON_END>>>
[FATAL] System halted
""",
    "frontend_logs/info_ui_77_render.log": """[INFO] Render complete
<<<JSON_START>>>
{
  "module": "ui",
  "severity": "info",
  "id": "ui_77_render"
}
<<<JSON_END>>>
[DEBUG] Memory cleared
""",
}


def test_script_exists_and_uses_flock():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "fcntl.flock" in content, f"Script {SCRIPT_PATH} does not seem to use fcntl.flock as required."


def test_project_logs_directory_empty():
    assert os.path.isdir(SOURCE_DIR), f"Source directory {SOURCE_DIR} is missing."
    files = os.listdir(SOURCE_DIR)
    assert len(files) == 0, f"Source directory {SOURCE_DIR} is not empty. Contains: {files}"


def test_organized_logs_exist_and_correct():
    assert os.path.isdir(TARGET_DIR), f"Target directory {TARGET_DIR} is missing."

    expected_files = {
        "security_logs/warning_x99_auth.log": "x99_auth",
        "backend_logs/critical_db_88_conn.log": "db_88_conn",
        "frontend_logs/info_ui_77_render.log": "ui_77_render",
    }

    for rel_path, id_str in expected_files.items():
        full_path = os.path.join(TARGET_DIR, rel_path)
        assert os.path.isfile(full_path), f"Expected organized log file {full_path} is missing."
        with open(full_path, "r") as f:
            content = f.read()
        assert "<<<JSON_START>>>" in content, f"Log content missing JSON_START in {full_path}"
        assert id_str in content, f"Expected ID '{id_str}' not found in {full_path}"
        assert content == ORIGINAL_LOGS[rel_path], f"Original log contents were not preserved in {full_path}"


def test_script_processes_fresh_logs_and_really_locks_during_move():
    token = secrets.token_hex(8)
    cases = [
        {
            "module": f"runtime_module_a_{token}",
            "subdir": f"runtime_destination_a_{token}",
            "severity": f"notice_{token}",
            "id": f"generated_a_{token}",
            "name": f"fresh_a_{token}.log",
            "prefix": f"runtime prefix A {token}\nsecond line A\n",
            "suffix": f"runtime suffix A {token}\n",
        },
        {
            "module": f"runtime_module_b_{token}",
            "subdir": f"runtime_destination_b_{token}",
            "severity": f"urgent_{token}",
            "id": f"generated_b_{token}",
            "name": f"fresh_b_{token}.log",
            "prefix": f"runtime prefix B {token}\nsecond line B\n",
            "suffix": f"runtime suffix B {token}\n",
        },
    ]

    with open(CONFIG_PATH, "r") as f:
        config = json.load(f)
    for case in cases:
        config["mapping"][case["module"]] = case["subdir"]
    with open(CONFIG_PATH, "w") as f:
        json.dump(config, f)

    identities = {}
    expected_contents = {}
    expected_destinations = {}
    for case in cases:
        payload = {
            "module": case["module"],
            "severity": case["severity"],
            "id": case["id"],
        }
        content = (
            case["prefix"]
            + "<<<JSON_START>>>\n"
            + json.dumps(payload, indent=2)
            + "\n<<<JSON_END>>>\n"
            + case["suffix"]
        )
        source = os.path.join(SOURCE_DIR, case["name"])
        destination = os.path.join(
            TARGET_DIR,
            case["subdir"],
            f"{case['severity']}_{case['id']}.log",
        )
        with open(source, "w") as f:
            f.write(content)
        st = os.stat(source)
        key = (st.st_dev, st.st_ino)
        identities[key] = case
        expected_contents[key] = content
        expected_destinations[key] = os.path.abspath(destination)

    real_flock = fcntl.flock
    real_rename = os.rename
    real_replace = os.replace
    held_fds = {}
    exclusive_seen = set()
    moved_while_locked = set()

    def fd_identity(fd):
        try:
            st = os.fstat(fd)
            return (st.st_dev, st.st_ino)
        except OSError:
            return None

    def checked_flock(fd, operation):
        key = fd_identity(fd)
        result = real_flock(fd, operation)
        if key in identities:
            if operation & fcntl.LOCK_UN:
                held_fds.pop(fd, None)
            elif operation & fcntl.LOCK_EX:
                exclusive_seen.add(key)
                held_fds[fd] = key
        return result

    def note_move(src, dst):
        try:
            st = os.stat(src)
            key = (st.st_dev, st.st_ino)
        except (FileNotFoundError, TypeError):
            return
        if key not in identities:
            return
        active = any(
            held_key == key and fd_identity(fd) == key
            for fd, held_key in list(held_fds.items())
        )
        assert active, f"{src} was moved without an active exclusive flock"
        assert os.path.abspath(os.fspath(dst)) == expected_destinations[key], (
            f"Fresh log was moved to the wrong destination: {dst}"
        )
        moved_while_locked.add(key)

    def checked_rename(src, dst, *args, **kwargs):
        note_move(src, dst)
        return real_rename(src, dst, *args, **kwargs)

    def checked_replace(src, dst, *args, **kwargs):
        note_move(src, dst)
        return real_replace(src, dst, *args, **kwargs)

    fcntl.flock = checked_flock
    os.rename = checked_rename
    os.replace = checked_replace
    try:
        runpy.run_path(SCRIPT_PATH, run_name="__main__")
    finally:
        fcntl.flock = real_flock
        os.rename = real_rename
        os.replace = real_replace

    assert exclusive_seen == set(identities), "The script did not acquire LOCK_EX on every fresh source log"
    assert moved_while_locked == set(identities), "Not every fresh source log was moved while locked"

    for key, case in identities.items():
        source = os.path.join(SOURCE_DIR, case["name"])
        destination = expected_destinations[key]
        assert not os.path.exists(source), f"Fresh source log was not moved: {source}"
        assert os.path.isfile(destination), f"Fresh organized log is missing: {destination}"
        with open(destination, "r") as f:
            assert f.read() == expected_contents[key], f"Full contents were not preserved in {destination}"

        with open(destination, "r") as f:
            real_flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            real_flock(f.fileno(), fcntl.LOCK_UN)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
