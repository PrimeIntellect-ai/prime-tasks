#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set +e
mkdir -p /logs/verifier

python3 <<'PY'
import json
import os
import secrets
import signal
import subprocess
import time
from pathlib import Path

import requests

BASE = "http://127.0.0.1:8443"
ROLES = Path("/home/user/user_roles.csv")
HIER = Path("/home/user/role_hierarchy.csv")
ORACLE = Path("/app/sod_oracle")


def get(path, timeout=5):
    r = requests.get(BASE + path, timeout=timeout)
    assert r.status_code == 200, f"GET {path}: expected 200, got {r.status_code}"
    return r.json()


def validate_audit(data, user, perms, compliant, toxic):
    assert type(data) is dict
    assert set(data) == {"user_id", "effective_permissions", "is_compliant", "toxic_pair"}, data
    assert data["user_id"] == user
    assert type(data["user_id"]) is str
    assert type(data["effective_permissions"]) is list
    assert all(type(x) is str for x in data["effective_permissions"])
    assert data["effective_permissions"] == sorted(data["effective_permissions"]), "permissions are not sorted"
    assert len(data["effective_permissions"]) == len(set(data["effective_permissions"])), "permissions are not unique"
    assert sorted(data["effective_permissions"]) == sorted(perms)
    assert type(data["is_compliant"]) is bool
    assert data["is_compliant"] is compliant
    assert type(data["toxic_pair"]) is list
    assert all(type(x) is str for x in data["toxic_pair"])
    assert sorted(data["toxic_pair"]) == sorted(toxic)


def validate_stats(data, expected):
    assert type(data) is list
    assert len(data) == 3
    actual = {}
    for item in data:
        assert type(item) is dict
        assert set(item) == {"permission", "user_count"}, item
        assert type(item["permission"]) is str
        assert type(item["user_count"]) is int and type(item["user_count"]) is not bool
        assert item["permission"] not in actual
        actual[item["permission"]] = item["user_count"]
    assert actual == expected, (actual, expected)


def listener_pid(port=8443):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == "0A":
                try:
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
                except ValueError:
                    pass
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd = proc / "fd"
        try:
            for ent in fd.iterdir():
                try:
                    target = os.readlink(ent)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(proc.name)
        except OSError:
            continue
    raise AssertionError("could not identify the process listening on port 8443")


def capture_launch(pid):
    raw = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    args = [x.decode(errors="surrogateescape") for x in raw if x]
    assert args, "server has an empty command line"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = {}
    for entry in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0"):
        if b"=" in entry:
            k, v = entry.split(b"=", 1)
            env[k.decode(errors="surrogateescape")] = v.decode(errors="surrogateescape")
    return args, cwd, env


def stop_pid(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(30):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    time.sleep(0.2)


def wait_server():
    last = None
    for _ in range(60):
        try:
            requests.get(BASE + "/", timeout=0.3)
            return
        except requests.RequestException as e:
            last = e
            time.sleep(0.1)
    raise AssertionError(f"restarted server did not listen on 127.0.0.1:8443: {last}")


saved_roles = ROLES.read_bytes()
saved_hier = HIER.read_bytes()
saved_oracle = ORACLE.read_bytes()
saved_mode = ORACLE.stat().st_mode
new_server = None
launch = None
try:
    # Preserve all original behavioral assertions and add the omitted fixture user.
    validate_audit(get("/api/v1/audit/alice"), "alice",
                   ["APPROVE_TRANSFER", "FUNDS_TRANSFER", "GENERATE_REPORT", "VIEW_LEDGER"],
                   False, ["APPROVE_TRANSFER", "FUNDS_TRANSFER"])
    validate_audit(get("/api/v1/audit/bob"), "bob",
                   ["GENERATE_REPORT", "VIEW_LEDGER"], True, [])
    validate_audit(get("/api/v1/audit/diana"), "diana",
                   ["CREATE_VENDOR", "PAY_VENDOR"], False,
                   ["CREATE_VENDOR", "PAY_VENDOR"])
    validate_audit(get("/api/v1/audit/charlie"), "charlie",
                   ["CREATE_VENDOR", "MANAGE_USERS"], True, [])
    validate_stats(get("/api/v1/stats/centrality"),
                   {"CREATE_VENDOR": 2, "GENERATE_REPORT": 2, "VIEW_LEDGER": 2})

    # Capture and restart the submitted server against unpredictable fixture data.
    pid = listener_pid()
    launch = capture_launch(pid)
    stop_pid(pid)

    suffix = secrets.token_hex(8).upper()
    users = [f"audit_u{i}_{suffix}" for i in range(1, 5)]
    roles = [f"ROLE_{i}_{suffix}" for i in range(1, 5)]
    branch1 = f"BRANCH_A_{suffix}"
    branch2 = f"BRANCH_B_{suffix}"
    toxic_a = f"ALPHA_{suffix}"
    toxic_b = f"ZETA_{suffix}"
    common4 = f"COMMON4_{suffix}"
    common3a = f"COMMON3A_{suffix}"
    common3b = f"COMMON3B_{suffix}"
    log = Path(f"/tmp/oracle_calls_{suffix}")

    ROLES.write_text("user_id,role_name\n" + "".join(
        f"{u},{r}\n" for u, r in zip(users, roles)
    ))
    HIER.write_text(
        "parent,child\n"
        f"{roles[0]},{branch1}\n"
        f"{roles[0]},{branch2}\n"
        f"{branch1},{toxic_a}\n"
        f"{branch1},{toxic_b}\n"
        f"{branch1},{common4}\n"
        f"{branch1},{common3a}\n"
        f"{branch1},{common3b}\n"
        f"{branch2},{common4}\n"
        f"{roles[1]},{common4}\n"
        f"{roles[1]},{common3a}\n"
        f"{roles[1]},{common3b}\n"
        f"{roles[2]},{common4}\n"
        f"{roles[2]},{common3a}\n"
        f"{roles[3]},{common4}\n"
        f"{roles[3]},{common3b}\n"
    )
    ORACLE.write_text(
        "#!/bin/bash\n"
        f"printf '%s\\n' \"$*\" >> {log}\n"
        "ha=0; hb=0\n"
        "for x in \"$@\"; do\n"
        f"  [ \"$x\" = \"{toxic_a}\" ] && ha=1\n"
        f"  [ \"$x\" = \"{toxic_b}\" ] && hb=1\n"
        "done\n"
        "if [ \"$ha\" = 1 ] && [ \"$hb\" = 1 ]; then\n"
        f"  echo 'TOXIC: {toxic_a}, {toxic_b}'\n"
        "  exit 1\n"
        "fi\n"
        "echo SAFE\n"
        "exit 0\n"
    )
    os.chmod(ORACLE, 0o755)

    args, cwd, env = launch
    new_server = subprocess.Popen(args, cwd=cwd, env=env,
                                  stdin=subprocess.DEVNULL,
                                  stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL)
    wait_server()

    expected_u1 = [toxic_a, toxic_b, common4, common3a, common3b]
    validate_audit(get(f"/api/v1/audit/{users[0]}"), users[0], expected_u1,
                   False, [toxic_a, toxic_b])
    validate_audit(get(f"/api/v1/audit/{users[1]}"), users[1],
                   [common4, common3a, common3b], True, [])
    validate_audit(get(f"/api/v1/audit/{users[2]}"), users[2],
                   [common4, common3a], True, [])
    validate_audit(get(f"/api/v1/audit/{users[3]}"), users[3],
                   [common4, common3b], True, [])
    validate_stats(get("/api/v1/stats/centrality"),
                   {common4: 4, common3a: 3, common3b: 3})

    # Unknown users must not be confused with a known user. Both conventional
    # API behaviors are accepted because the task does not prescribe a status.
    unknown = f"unknown_{suffix}"
    r = requests.get(BASE + f"/api/v1/audit/{unknown}", timeout=5)
    assert r.status_code in (200, 404)
    if r.status_code == 200:
        validate_audit(r.json(), unknown, [], True, [])

    assert log.exists(), "the service did not invoke /app/sod_oracle"
    calls = [line.split() for line in log.read_text().splitlines()]
    assert any(set(call) == set(expected_u1) and len(call) == len(expected_u1)
               for call in calls), "oracle was not called with u1's flattened unique permissions"
finally:
    ROLES.write_bytes(saved_roles)
    HIER.write_bytes(saved_hier)
    ORACLE.write_bytes(saved_oracle)
    os.chmod(ORACLE, saved_mode)
    if new_server is not None and new_server.poll() is None:
        new_server.terminate()
        try:
            new_server.wait(timeout=2)
        except subprocess.TimeoutExpired:
            new_server.kill()
    if launch is not None:
        args, cwd, env = launch
        try:
            subprocess.Popen(args, cwd=cwd, env=env,
                             stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
        except Exception:
            pass
PY
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
