#!/bin/bash
mkdir -p /logs/verifier
passed=1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_terminated_containers_file():
    txt_path = "/home/user/terminated_containers.txt"
    assert os.path.isfile(txt_path), f"Output file {txt_path} is missing."

    with open(txt_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_containers = ["C-102", "C-104"]
    assert sorted(lines) == sorted(expected_containers), (
        f"Expected {txt_path} to contain exactly {expected_containers}, but found {lines}."
    )


def test_cloud_db_state():
    db_path = "/home/user/.cloud_db"
    assert os.path.isfile(db_path), f"Database file {db_path} is missing."

    with open(db_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    terminated_in_db = []
    for line in lines:
        parts = line.split(',')
        if len(parts) == 5 and parts[4] == "terminated":
            terminated_in_db.append(parts[0])

    expected_terminated = ["C-102", "C-104"]
    assert sorted(terminated_in_db) == sorted(expected_terminated), (
        f"Expected exactly {expected_terminated} to be marked as terminated in {db_path}, "
        f"but found {terminated_in_db}."
    )


def test_cost_pipeline_script_exists_and_executable():
    script_path = "/home/user/cost_pipeline.sh"
    assert os.path.isfile(script_path), f"Pipeline script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Pipeline script {script_path} is not executable."


def test_cloud_session_exists():
    session_path = "/home/user/.cloud_session"
    assert os.path.isfile(session_path), (
        f"Session file {session_path} is missing. "
        "The script must successfully log in using the cloud-manager tool."
    )
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || passed=0

if [ "$passed" -eq 1 ]; then
    baseline=$(mktemp /tmp/cloud_baseline.XXXXXX)
    call_log=$(mktemp /tmp/cloud_calls.XXXXXX)
    run_log=$(mktemp /tmp/pipeline_run.XXXXXX)

    BASELINE="$baseline" python3 - <<'PY'
import os
import secrets

ids = ["C-" + secrets.token_hex(5).upper() for _ in range(6)]
rows = [
    (ids[0], "5.75", "2", "4", "running"),   # wasteful
    (ids[1], "2.01", "4", "9", "running"),   # wasteful
    (ids[2], "8.40", "5", "1", "running"),   # CPU boundary
    (ids[3], "3.20", "1", "10", "running"),  # memory boundary
    (ids[4], "2.00", "0", "0", "running"),   # cost boundary
    (ids[5], "1.10", "2", "3", "running"),   # low cost
]
text = "".join(",".join(row) + "\n" for row in rows)
with open(os.environ["BASELINE"], "w") as f:
    f.write(text)
with open("/home/user/.cloud_db", "w") as f:
    f.write(text)
PY

    cat <<'MOCK_EOF' > /home/user/cloud-manager
#!/bin/bash
log=${CM_CALL_LOG:?missing verifier call log}

if [ "$1" = "login" ]; then
    read -r -p "Username: " user
    read -r -s -p "Password: " pass
    echo
    if [ "$user" = "finops_admin" ] && [ "$pass" = 'CostSave2023!' ]; then
        printf 'login_ok\n' >> "$log"
        touch /home/user/.cloud_session
        echo "Login successful."
        exit 0
    fi
    printf 'login_bad\n' >> "$log"
    echo "Login failed."
    exit 1
fi

if [ ! -f /home/user/.cloud_session ]; then
    printf 'unauthenticated\t%s\n' "$*" >> "$log"
    echo "Error: Not logged in."
    exit 1
fi

if [ "$1" = "list" ]; then
    printf 'list\n' >> "$log"
    echo "ContainerID,CostPerHr,CPU_Percent,Mem_Percent"
    awk -F, '$5 == "running" {print $1 "," $2 "," $3 "," $4}' /home/user/.cloud_db
    exit 0
fi

if [ "$1" = "terminate" ] && [ -n "$2" ]; then
    cid=$2
    read -r -p "Are you sure you want to terminate $cid? [y/N]: " confirm
    printf 'terminate\t%s\t%s\n' "$cid" "$confirm" >> "$log"
    if [ "$confirm" != "y" ]; then
        echo "Aborted."
        exit 1
    fi
    if ! grep -q "^${cid},.*,[Rr][Uu][Nn][Nn][Ii][Nn][Gg]$" /home/user/.cloud_db; then
        echo "Error: Unknown or non-running container."
        exit 1
    fi
    sed -i "s/^${cid},\(.*\),running$/${cid},\1,terminated/" /home/user/.cloud_db
    echo "Terminated $cid"
    exit 0
fi

echo "Usage: cloud-manager [login|list|terminate <ID>]"
exit 1
MOCK_EOF

    chmod 755 /home/user/cloud-manager
    chown user:user /home/user/.cloud_db "$call_log"
    chmod 600 "$call_log"
    rm -f /home/user/.cloud_session /home/user/terminated_containers.txt

    timeout 30s runuser -u user -- env CM_CALL_LOG="$call_log" /home/user/cost_pipeline.sh >"$run_log" 2>&1
    rc=$?
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
        echo "Pipeline timed out" >&2
        passed=0
    fi

    if [ "$passed" -eq 1 ]; then
        BASELINE="$baseline" CALL_LOG="$call_log" python3 - <<'PY' || passed=0
import os
from collections import Counter


def read_rows(path):
    rows = []
    with open(path) as f:
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split(',')
            assert len(parts) == 5, f"Malformed database row: {line!r}"
            rows.append(parts)
    return rows

baseline = read_rows(os.environ["BASELINE"])
expected = [
    row[0] for row in baseline
    if float(row[1]) > 2.00 and float(row[2]) < 5 and float(row[3]) < 10
]

assert os.path.isfile("/home/user/terminated_containers.txt"), "Pipeline did not create its output file"
with open("/home/user/terminated_containers.txt") as f:
    reported = [line.strip() for line in f if line.strip()]
assert sorted(reported) == sorted(expected), (
    f"Expected dynamically selected containers {expected}, but output contained {reported}"
)

final = read_rows("/home/user/.cloud_db")
assert len(final) == len(baseline), "Pipeline added or removed database rows"
base_by_id = {row[0]: row for row in baseline}
final_by_id = {row[0]: row for row in final}
assert set(final_by_id) == set(base_by_id), "Pipeline changed container IDs"
for cid, before in base_by_id.items():
    after = final_by_id[cid]
    assert after[:4] == before[:4], f"Pipeline changed metrics for {cid}"
    wanted_state = "terminated" if cid in expected else "running"
    assert after[4] == wanted_state, f"Unexpected state for {cid}: {after[4]}"

assert os.path.isfile("/home/user/.cloud_session"), "Pipeline did not successfully log in"
assert os.path.isfile("/home/user/cost_pipeline.sh")
assert os.access("/home/user/cost_pipeline.sh", os.X_OK)

with open(os.environ["CALL_LOG"]) as f:
    calls = [line.rstrip("\n").split("\t") for line in f if line.strip()]
assert sum(call == ["login_ok"] for call in calls) >= 1, "cloud-manager login was not completed"
assert sum(call == ["list"] for call in calls) >= 1, "cloud-manager list was not used"
assert not any(call[0] in ("login_bad", "unauthenticated") for call in calls), "Invalid or unauthenticated CLI use"
terminations = [call for call in calls if call[0] == "terminate"]
assert all(len(call) == 3 and call[2] == "y" for call in terminations), "Termination confirmation was not exactly y"
assert Counter(call[1] for call in terminations) == Counter(expected), (
    f"Expected cloud-manager terminate calls for {expected}, got {terminations}"
)
PY
    fi

    rm -f "$baseline" "$call_log" "$run_log"
fi

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
