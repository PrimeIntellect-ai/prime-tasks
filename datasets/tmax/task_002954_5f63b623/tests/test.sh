#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import subprocess

import cv2
import pytest

SCRIPT_FILE = "/home/user/generate_routes.sh"
ROUTING_FILE = "/home/user/routing.conf"
GROUP_FILE = "/home/user/group_mock"
PASSWD_FILE = "/home/user/passwd_mock"
TEAM_FILE = "/app/team.csv"
VIDEO_FILE = "/app/traffic_monitor.mp4"


def read_team_data():
    users = []
    teams = []
    members = {}
    with open(TEAM_FILE, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["username", "team_name"]
        for row in reader:
            username = row["username"]
            team = row["team_name"]
            users.append((username, team))
            if team not in members:
                teams.append(team)
                members[team] = []
            members[team].append(username)
    return users, teams, members


def weights_from_video():
    cap = cv2.VideoCapture(VIDEO_FILE)
    assert cap.isOpened(), f"Could not open {VIDEO_FILE}"
    online = [0, 0, 0]
    frames = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames += 1
        height, width = frame.shape[:2]
        for index, fraction in enumerate((1 / 6, 1 / 2, 5 / 6)):
            b, g, r = frame[int(height * fraction), width // 2]
            if int(g) > int(r) and int(g) > int(b):
                online[index] += 1
    cap.release()
    assert frames == 60, f"Expected 60 video frames, found {frames}"
    total = sum(online)
    assert total > 0, "Video contains no online frames"
    return tuple(count / total for count in online)


@pytest.fixture(scope="session", autouse=True)
def run_route_generator():
    assert os.path.isfile(SCRIPT_FILE), f"Routing generator script missing at {SCRIPT_FILE}"
    if os.path.lexists(ROUTING_FILE):
        assert os.path.isfile(ROUTING_FILE) or os.path.islink(ROUTING_FILE), \
            f"Cannot replace non-file path at {ROUTING_FILE}"
        os.unlink(ROUTING_FILE)
    result = subprocess.run(
        ["/bin/bash", SCRIPT_FILE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"generate_routes.sh failed with exit status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(ROUTING_FILE), \
        f"generate_routes.sh did not create {ROUTING_FILE}"


def test_routing_conf_mse():
    """Test that the routing configuration weights are within the acceptable MSE threshold."""
    assert os.path.isfile(ROUTING_FILE), f"Routing configuration file missing at {ROUTING_FILE}"

    with open(ROUTING_FILE, "r") as f:
        content = f.read()

    exact = re.fullmatch(
        r"route_weights node1=(0\.\d{3}) node2=(0\.\d{3}) node3=(0\.\d{3})\n?",
        content,
    )
    assert exact is not None, \
        "routing.conf must contain exactly one routing line with three-decimal weights"

    # Preserve the original format/value checks.
    match = re.search(r"route_weights node1=([0-9.]+) node2=([0-9.]+) node3=([0-9.]+)", content)
    assert match is not None, "Routing configuration format is incorrect or missing."
    w1, w2, w3 = float(match.group(1)), float(match.group(2)), float(match.group(3))

    gt_w1, gt_w2, gt_w3 = 45 / 135, 30 / 135, 60 / 135
    mse = ((w1 - gt_w1) ** 2 + (w2 - gt_w2) ** 2 + (w3 - gt_w3) ** 2) / 3.0
    assert mse <= 0.0001, \
        f"MSE {mse} exceeds threshold 0.0001. Weights found: {w1}, {w2}, {w3}"

    derived = weights_from_video()
    expected_strings = tuple(f"{weight:.3f}" for weight in derived)
    assert exact.groups() == expected_strings, \
        f"Weights do not match the video: expected {expected_strings}, found {exact.groups()}"


def test_group_mock():
    """Test that group_mock has exactly the CSV teams and sequential GIDs."""
    assert os.path.isfile(GROUP_FILE), f"Group mock file missing at {GROUP_FILE}"

    with open(GROUP_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    parsed_groups = {}
    for line in lines:
        parts = line.split(":")
        assert len(parts) == 4, f"Invalid group line format: {line}"
        team, pwd, gid, users = parts
        assert team not in parsed_groups, f"Duplicate group entry for {team}"
        assert pwd == "x", f"Group {team} must use password field x"
        users_list = sorted(users.split(","))
        parsed_groups[team] = {"gid": int(gid), "users": users_list}

    # Preserve the original concrete membership assertions.
    assert "backend" in parsed_groups, "Missing 'backend' team in group_mock"
    assert parsed_groups["backend"]["users"] == ["alice", "charlie"], "Incorrect users in 'backend' team"
    assert "frontend" in parsed_groups, "Missing 'frontend' team in group_mock"
    assert parsed_groups["frontend"]["users"] == ["bob"], "Incorrect users in 'frontend' team"
    assert "devops" in parsed_groups, "Missing 'devops' team in group_mock"
    assert parsed_groups["devops"]["users"] == ["diana"], "Incorrect users in 'devops' team"

    gids = [g["gid"] for g in parsed_groups.values()]
    assert len(set(gids)) == 3, "GIDs must be unique for each team"
    assert all(g >= 2000 for g in gids), "GIDs must start at 2000"

    _, teams, expected_members = read_team_data()
    assert set(parsed_groups) == set(teams), "group_mock must contain exactly the teams from team.csv"
    assert len(lines) == len(teams), "group_mock must contain exactly one line per team"
    assert sorted(gids) == list(range(2000, 2000 + len(teams))), \
        "GIDs must be a consecutive sequence starting at 2000"
    for team in teams:
        assert parsed_groups[team]["users"] == sorted(expected_members[team]), \
            f"Incorrect users in team {team}"


def test_passwd_mock():
    """Test that passwd_mock has exactly the CSV users and sequential UIDs."""
    assert os.path.isfile(PASSWD_FILE), f"Passwd mock file missing at {PASSWD_FILE}"
    assert os.path.isfile(GROUP_FILE), f"Group mock file missing at {GROUP_FILE}"

    with open(GROUP_FILE, "r") as f:
        group_lines = [line.strip() for line in f if line.strip()]

    team_to_gid = {}
    for line in group_lines:
        parts = line.split(":")
        team_to_gid[parts[0]] = int(parts[2])

    with open(PASSWD_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    parsed_users = {}
    for line in lines:
        parts = line.split(":")
        assert len(parts) == 7, f"Invalid passwd line format: {line}"
        user, pwd, uid, gid, gecos, home, shell = parts
        assert user not in parsed_users, f"Duplicate passwd entry for {user}"
        parsed_users[user] = {
            "uid": int(uid),
            "gid": int(gid),
            "home": home,
            "shell": shell,
        }

    expected_users = {
        "alice": "backend",
        "bob": "frontend",
        "charlie": "backend",
        "diana": "devops",
    }
    assert set(parsed_users.keys()) == set(expected_users.keys()), "Mismatch in expected users in passwd_mock"

    uids = [u["uid"] for u in parsed_users.values()]
    assert len(set(uids)) == 4, "UIDs must be unique for each user"
    assert all(u >= 3000 for u in uids), "UIDs must start at 3000"

    for user, team in expected_users.items():
        assert parsed_users[user]["gid"] == team_to_gid[team], f"User {user} has incorrect GID for team {team}"
        assert parsed_users[user]["home"] == f"/home/{user}", f"User {user} has incorrect home directory"
        assert parsed_users[user]["shell"] == "/bin/bash", f"User {user} has incorrect shell"

    csv_users, _, _ = read_team_data()
    expected_from_csv = dict(csv_users)
    assert set(parsed_users) == set(expected_from_csv), \
        "passwd_mock must contain exactly the users from team.csv"
    assert len(lines) == len(csv_users), "passwd_mock must contain exactly one line per user"
    assert sorted(uids) == list(range(3000, 3000 + len(csv_users))), \
        "UIDs must be a consecutive sequence starting at 3000"
    for user, team in csv_users:
        assert parsed_users[user]["gid"] == team_to_gid[team], \
            f"User {user} has incorrect primary GID"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
