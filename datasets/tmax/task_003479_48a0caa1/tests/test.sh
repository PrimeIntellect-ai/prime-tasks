#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import tarfile

CONFIG_MANAGER_DIR = "/home/user/config_manager"
SYSTEM_CONF = os.path.join(CONFIG_MANAGER_DIR, "system.conf")
FINAL_BACKUP = os.path.join(CONFIG_MANAGER_DIR, "final_backup.tar.gz")

EXPECTED_CONTENTS = """DEBUG_MODE=true
TIMEOUT=60
MAX_USERS=500
LOG_LEVEL=info"""

def test_system_conf_final_contents():
    assert os.path.isfile(SYSTEM_CONF), f"File {SYSTEM_CONF} does not exist"

    with open(SYSTEM_CONF, "r", encoding="utf-8") as f:
        contents = f.read().strip()

    assert contents == EXPECTED_CONTENTS, f"Contents of {SYSTEM_CONF} do not match the expected final state.\nGot:\n{contents}\nExpected:\n{EXPECTED_CONTENTS}"

def test_final_backup_archive():
    assert os.path.isfile(FINAL_BACKUP), f"Archive {FINAL_BACKUP} does not exist"
    assert tarfile.is_tarfile(FINAL_BACKUP), f"{FINAL_BACKUP} is not a valid tar archive"

    with tarfile.open(FINAL_BACKUP, "r:gz") as tar:
        members = tar.getnames()
        # It should contain just system.conf at its root
        # allow system.conf or ./system.conf
        valid_names = {"system.conf", "./system.conf"}
        assert len(members) == 1, f"Expected exactly 1 file in {FINAL_BACKUP}, found {len(members)}: {members}"
        assert members[0] in valid_names, f"Expected file named system.conf in archive, got {members[0]}"

        member = tar.getmember(members[0])
        assert member.isfile(), f"Expected {members[0]} to be a regular file"

        with tar.extractfile(member) as f:
            contents = f.read().decode("utf-8").strip()

        assert contents == EXPECTED_CONTENTS, f"Contents of system.conf inside {FINAL_BACKUP} do not match the expected final state."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
