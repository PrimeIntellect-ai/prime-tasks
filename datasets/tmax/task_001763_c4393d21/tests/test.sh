#!/bin/bash
set -u
mkdir -p /logs/verifier
ok=1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re

def get_expected_data():
    csv_path = "/home/user/new_hires.csv"
    log_path = "/home/user/access.log"
    users = []
    usernames = []

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            first = row['FirstName']
            last = row['LastName']
            base_user = (first[0] + last).lower()[:8]
            uname = base_user
            counter = 1
            while uname in usernames:
                uname = base_user + str(counter)
                counter += 1
            usernames.append(uname)
            row['Username'] = uname
            users.append(row)

    locked_users = set()
    with open(log_path, 'r') as f:
        for line in f:
            if "STATUS=LOCKED" in line:
                m = re.search(r'\[([^\]]+)\]', line)
                if m:
                    locked_users.add(m.group(1))
    return users, locked_users

def test_passwd_file():
    users, _ = get_expected_data()
    passwd_path = "/home/user/site_data/passwd"
    assert os.path.isfile(passwd_path), f"File {passwd_path} does not exist."
    with open(passwd_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == len(users), f"Expected {len(users)} entries in passwd, found {len(lines)}."
    dept_to_gid = {"Engineering": "2000", "Sales": "2001", "HR": "2002"}
    uid = 1000
    for i, user in enumerate(users):
        expected_line = f"{user['Username']}:x:{uid + i}:{dept_to_gid[user['Department']]}:{user['FirstName']} {user['LastName']}:/home/user/site_data/home/{user['Username']}:/bin/bash"
        assert lines[i] == expected_line, f"Passwd entry mismatch at line {i+1}. Expected '{expected_line}', got '{lines[i]}'."

def test_home_directories():
    users, _ = get_expected_data()
    for user in users:
        home_dir = f"/home/user/site_data/home/{user['Username']}"
        assert os.path.isdir(home_dir), f"Home directory {home_dir} does not exist."

def test_mail_spool():
    users, _ = get_expected_data()
    for user in users:
        spool_file = f"/home/user/site_data/mail_spool/{user['Username']}.txt"
        assert os.path.isfile(spool_file), f"Mail spool file {spool_file} does not exist."
        with open(spool_file, 'r') as f:
            content = f.read().strip().split('\n')
        assert len(content) == 2, f"Expected 2 lines in {spool_file}, got {len(content)}."
        assert content[0] == f"To: {user['Email']}", f"Incorrect To line in {spool_file}."
        assert content[1] == f"Subject: Welcome to {user['Department']}, {user['FirstName']}!", f"Incorrect Subject line in {spool_file}."

def test_locked_emails():
    users, locked_users = get_expected_data()
    locked_emails_path = "/home/user/site_data/locked_emails.txt"
    assert os.path.isfile(locked_emails_path), f"File {locked_emails_path} does not exist."
    expected_locked_emails = set()
    for user in users:
        if user['Username'] in locked_users:
            expected_locked_emails.add(user['Email'])
    with open(locked_emails_path, 'r') as f:
        actual_locked_emails = set(line.strip() for line in f if line.strip())
    assert actual_locked_emails == expected_locked_emails, f"Locked emails mismatch. Expected {expected_locked_emails}, got {actual_locked_emails}."

def test_mailing_lists():
    users, locked_users = get_expected_data()
    expected_lists = {}
    for user in users:
        if user['Username'] not in locked_users:
            dept = user['Department']
            expected_lists.setdefault(dept, set()).add(user['Email'])
    all_depts = set(u['Department'] for u in users)
    for dept in all_depts:
        list_file = f"/home/user/site_data/lists/{dept}.list"
        expected_emails = expected_lists.get(dept, set())
        if not expected_emails:
            if os.path.exists(list_file):
                with open(list_file, 'r') as f:
                    content = f.read().strip()
                assert not content, f"List file {list_file} should be empty, but contains data."
        else:
            assert os.path.isfile(list_file), f"List file {list_file} does not exist."
            with open(list_file, 'r') as f:
                actual_emails = set(line.strip() for line in f if line.strip())
            assert actual_emails == expected_emails, f"Mailing list {dept} mismatch. Expected {expected_emails}, got {actual_emails}."
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0

cat << 'BEHAVIOR_EOF' > /tmp/test_onboard_behavior.py
import csv
import os
import re
import shutil
import subprocess
import tempfile
import uuid

SCRIPT = "/home/user/onboard.sh"
SITE = "/home/user/site_data"
ACCESS = "/home/user/access.log"
ORIGINAL_CSV = "/home/user/new_hires.csv"

def nonempty_lines(path):
    with open(path, encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]

def main():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist or is not a regular file"
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable"
    with open(SCRIPT, "rb") as f:
        first_line = f.readline(256).decode("utf-8", "replace").strip()
    assert re.match(r"^#!\s*(?:/usr/bin/env\s+(?:-S\s+)?bash|\S*/bash)(?:\s|$)", first_line), \
        f"{SCRIPT} is not an executable Bash script"

    backup_root = tempfile.mkdtemp(prefix="onboard-verifier-")
    site_backup = os.path.join(backup_root, "site_data")
    shutil.copytree(SITE, site_backup)
    with open(ACCESS, "rb") as f:
        access_backup = f.read()
    with open(ORIGINAL_CSV, "rb") as f:
        csv_backup = f.read()

    token = uuid.uuid4().hex[:10]
    dynamic_csv = f"/home/user/verification_hires_{token}.csv"
    rows = [
        {"FirstName": "Nora", "LastName": f"Quill{token}", "Department": "Engineering", "Email": f"nora.{token}@example.test"},
        {"FirstName": "Noah", "LastName": f"Quill{token}", "Department": "Sales", "Email": f"noah.{token}@example.test"},
        {"FirstName": "Priya", "LastName": f"Vale{token}", "Department": "HR", "Email": f"priya.{token}@example.test"},
        {"FirstName": "Ravi", "LastName": f"Stone{token}", "Department": "Engineering", "Email": f"ravi.{token}@example.test"},
    ]

    usernames = []
    for row in rows:
        base = (row["FirstName"][0] + row["LastName"]).lower()[:8]
        username = base
        counter = 1
        while username in usernames:
            username = base + str(counter)
            counter += 1
        row["Username"] = username
        usernames.append(username)

    locked = {usernames[1], usernames[3]}
    try:
        shutil.rmtree(SITE)
        os.makedirs(os.path.join(SITE, "home"))
        os.makedirs(os.path.join(SITE, "lists"))
        os.makedirs(os.path.join(SITE, "mail_spool"))
        open(os.path.join(SITE, "passwd"), "w").close()

        with open(dynamic_csv, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=["FirstName", "LastName", "Department", "Email"])
            writer.writeheader()
            for row in rows:
                writer.writerow({k: row[k] for k in writer.fieldnames})

        with open(ACCESS, "w", encoding="utf-8") as f:
            f.write(f"2026-01-01 09:00:00 [{usernames[0]}] login STATUS=SUCCESS\n")
            f.write(f"2026-01-01 09:01:00 [{usernames[1]}] login STATUS=LOCKED\n")
            f.write(f"2026-01-01 09:02:00 [{usernames[2]}] login STATUS=SUCCESS\n")
            f.write(f"2026-01-01 09:03:00 [{usernames[3]}] login STATUS=LOCKED\n")

        result = subprocess.run([SCRIPT, dynamic_csv], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, timeout=30)
        assert result.returncode == 0, \
            f"onboard.sh failed on a fresh runtime input (exit {result.returncode}):\n{result.stderr}"

        dept_to_gid = {"Engineering": "2000", "Sales": "2001", "HR": "2002"}
        expected_passwd = [
            f"{row['Username']}:x:{1000+i}:{dept_to_gid[row['Department']]}:{row['FirstName']} {row['LastName']}:/home/user/site_data/home/{row['Username']}:/bin/bash"
            for i, row in enumerate(rows)
        ]
        assert nonempty_lines(os.path.join(SITE, "passwd")) == expected_passwd

        for row in rows:
            username = row["Username"]
            assert os.path.isdir(os.path.join(SITE, "home", username))
            spool = os.path.join(SITE, "mail_spool", username + ".txt")
            assert os.path.isfile(spool)
            with open(spool, encoding="utf-8") as f:
                content = f.read().strip().split("\n")
            assert content == [
                f"To: {row['Email']}",
                f"Subject: Welcome to {row['Department']}, {row['FirstName']}!",
            ]

        expected_locked = {row["Email"] for row in rows if row["Username"] in locked}
        locked_file = os.path.join(SITE, "locked_emails.txt")
        assert os.path.isfile(locked_file)
        assert set(nonempty_lines(locked_file)) == expected_locked

        for dept in ("Engineering", "Sales", "HR"):
            expected = {
                row["Email"] for row in rows
                if row["Department"] == dept and row["Username"] not in locked
            }
            list_path = os.path.join(SITE, "lists", dept + ".list")
            if expected:
                assert os.path.isfile(list_path)
                assert set(nonempty_lines(list_path)) == expected
            elif os.path.exists(list_path):
                assert nonempty_lines(list_path) == []
    finally:
        if os.path.exists(SITE):
            shutil.rmtree(SITE)
        shutil.copytree(site_backup, SITE)
        with open(ACCESS, "wb") as f:
            f.write(access_backup)
        with open(ORIGINAL_CSV, "wb") as f:
            f.write(csv_backup)
        if os.path.exists(dynamic_csv):
            os.remove(dynamic_csv)
        shutil.rmtree(backup_root)

if __name__ == "__main__":
    main()
BEHAVIOR_EOF

python3 /tmp/test_onboard_behavior.py 2>&1 || ok=0

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
