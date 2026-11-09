#!/bin/bash
set +e
mkdir -p /logs/verifier
ok=1

cat > /tmp/test_final_state.py <<'PY'
import json
import os

REPORT_PATH = "/home/user/observability_report.json"
STATE_DIR = "/home/user/mock_containers"

def test_original_assertions():
    assert os.path.exists(REPORT_PATH), f"Report file not found at {REPORT_PATH}."
    assert os.path.isfile(REPORT_PATH), f"Path {REPORT_PATH} is not a file."
    with open(REPORT_PATH) as f:
        data = json.load(f)
    assert "restarted_containers" in data
    assert "ui_errors" in data
    restarted = data.get("restarted_containers", [])
    assert isinstance(restarted, list)
    assert set(restarted) == {"def20002", "jkl40004"}
    ui_errors = data.get("ui_errors", {})
    assert isinstance(ui_errors, dict)
    expected = {
        "abc10001": ["Widget 'Network' timeout."],
        "def20002": ["Out of memory in panel 'Disk'."],
        "jkl40004": ["Widget 'CPU' timeout.", "Alert manager disconnected."]
    }
    assert set(ui_errors) == set(expected)
    for cid, messages in expected.items():
        assert isinstance(ui_errors[cid], list)
        assert ui_errors[cid] == messages
    expected_mem = {
        "c1_mem": "250MB", "c2_mem": "100MB",
        "c3_mem": "150MB", "c4_mem": "100MB"
    }
    for name, value in expected_mem.items():
        path = os.path.join(STATE_DIR, name)
        assert os.path.exists(path), f"State file {path} missing."
        with open(path) as f:
            assert f.read().strip() == value
PY
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short >/tmp/original-tests.log 2>&1 || ok=0

SRC=/home/user/auto_tuner.go
BIN=/tmp/auto_tuner_submission
MGR=/home/user/container_mgr.sh
MGR_BACKUP=/tmp/container_mgr.sh.backup
AWK_REAL=""
AWK_SAVE=""
GREP_REAL=""
GREP_SAVE=""

cleanup() {
    if [ -n "$AWK_SAVE" ] && [ -e "$AWK_SAVE" ]; then rm -f "$AWK_REAL"; mv "$AWK_SAVE" "$AWK_REAL"; fi
    if [ -n "$GREP_SAVE" ] && [ -e "$GREP_SAVE" ]; then rm -f "$GREP_REAL"; mv "$GREP_SAVE" "$GREP_REAL"; fi
    if [ -e "$MGR_BACKUP" ]; then cp -p "$MGR_BACKUP" "$MGR"; fi
}
trap cleanup EXIT

if [ "$ok" = 1 ]; then
    [ -f "$SRC" ] && [ ! -L "$SRC" ] || ok=0
fi

if [ "$ok" = 1 ]; then
    python3 - <<'PY' || ok=0
import re
p = "/home/user/auto_tuner.go"
s = open(p).read()
m = re.search(r'(?m)(?:\b([A-Za-z_]\w*|\.)\s+)?"os/exec"', s)
assert m, "auto_tuner.go must import os/exec"
alias = m.group(1) or "exec"
if alias == ".":
    pattern = r'\b(?:Command|CommandContext)\s*\('
else:
    pattern = r'\b' + re.escape(alias) + r'\s*\.\s*(?:Command|CommandContext)\s*\('
assert re.search(pattern, s), "auto_tuner.go must call os/exec Command or CommandContext"
PY
fi

if [ "$ok" = 1 ]; then
    (cd /home/user && go build -o "$BIN" "$SRC") >/tmp/go-build.log 2>&1 || ok=0
    [ -x "$BIN" ] || ok=0
fi

if [ "$ok" = 1 ]; then
    cp -p "$MGR" "$MGR_BACKUP" || ok=0
    rm -rf /tmp/dynamic_containers
    mkdir -p /tmp/dynamic_containers
    : > /tmp/manager_calls
    : > /tmp/tool_calls
    python3 - <<'PY' || ok=0
import json, os, secrets
root = "/tmp/dynamic_containers"
ids = ["rt" + secrets.token_hex(4) for _ in range(4)]
mem = ["731MB", "287MB", "999MB", "500MB"]
errors = [
    ["Dynamic network " + secrets.token_hex(5) + "."],
    [],
    ["Dynamic CPU " + secrets.token_hex(5) + ".", "Dynamic source " + secrets.token_hex(5) + "."],
    ["Boundary message " + secrets.token_hex(5) + "."]
]
for i in range(4):
    n = i + 1
    open(f"{root}/c{n}_id", "w").write(ids[i] + "\n")
    open(f"{root}/c{n}_mem", "w").write(mem[i] + "\n")
    lines = ["[INFO] dynamic start"]
    lines += ["[ERROR] Dashboard UI Error: " + x for x in errors[i]]
    lines += ["[INFO] dynamic end"]
    open(f"{root}/c{n}_logs", "w").write("\n".join(lines) + "\n")
expected = {
    "restarted_containers": [ids[0], ids[2]],
    "ui_errors": {ids[i]: errors[i] for i in range(4) if errors[i]}
}
json.dump(expected, open("/tmp/dynamic_expected.json", "w"))
PY
fi

if [ "$ok" = 1 ]; then
cat > "$MGR" <<'SH'
#!/bin/bash
D=/tmp/dynamic_containers
printf '%s\t%s\n' "$1" "$2" >> /tmp/manager_calls
case "$1" in
  list)
    echo "CONTAINER ID   IMAGE      STATUS   MEM USAGE"
    for n in 1 2 3 4; do
      echo "$(cat "$D/c${n}_id")       dynamic-app Running  $(cat "$D/c${n}_mem")"
    done
    ;;
  logs)
    for n in 1 2 3 4; do
      if [ "$2" = "$(cat "$D/c${n}_id")" ]; then cat "$D/c${n}_logs"; exit 0; fi
    done
    exit 1
    ;;
  restart)
    for n in 1 2 3 4; do
      if [ "$2" = "$(cat "$D/c${n}_id")" ]; then
        echo "100MB" > "$D/c${n}_mem"
        echo "Container $2 restarted."
        exit 0
      fi
    done
    exit 1
    ;;
  *) exit 1 ;;
esac
SH
    chmod +x "$MGR" || ok=0
fi

if [ "$ok" = 1 ]; then
    AWK_REAL=$(readlink -f "$(command -v awk)")
    GREP_REAL=$(readlink -f "$(command -v grep)")
    AWK_SAVE="${AWK_REAL}.verifier-real"
    GREP_SAVE="${GREP_REAL}.verifier-real"
    mv "$AWK_REAL" "$AWK_SAVE" || ok=0
    if [ "$ok" = 1 ]; then
cat > "$AWK_REAL" <<EOF
#!/bin/bash
printf 'awk\t%s\n' "\$*" >> /tmp/tool_calls
exec "$AWK_SAVE" "\$@"
EOF
        chmod +x "$AWK_REAL" || ok=0
    fi
    if [ "$ok" = 1 ]; then
        mv "$GREP_REAL" "$GREP_SAVE" || ok=0
    fi
    if [ "$ok" = 1 ]; then
cat > "$GREP_REAL" <<EOF
#!/bin/bash
printf 'grep\t%s\n' "\$*" >> /tmp/tool_calls
exec "$GREP_SAVE" "\$@"
EOF
        chmod +x "$GREP_REAL" || ok=0
    fi
fi

if [ "$ok" = 1 ]; then
    rm -f /home/user/observability_report.json
    (cd /home/user && timeout 25s "$BIN") >/tmp/dynamic-run.log 2>&1 || ok=0
fi

# Restore system tools before running the validation utilities.
if [ -n "$AWK_SAVE" ] && [ -e "$AWK_SAVE" ]; then rm -f "$AWK_REAL"; mv "$AWK_SAVE" "$AWK_REAL"; AWK_SAVE=""; fi
if [ -n "$GREP_SAVE" ] && [ -e "$GREP_SAVE" ]; then rm -f "$GREP_REAL"; mv "$GREP_SAVE" "$GREP_REAL"; GREP_SAVE=""; fi

if [ "$ok" = 1 ]; then
    python3 - <<'PY' || ok=0
import json, os
report_path = "/home/user/observability_report.json"
assert os.path.isfile(report_path)
with open(report_path) as f:
    actual = json.load(f)
with open("/tmp/dynamic_expected.json") as f:
    expected = json.load(f)
assert set(actual) == {"restarted_containers", "ui_errors"}
assert actual["restarted_containers"] == expected["restarted_containers"]
assert actual["ui_errors"] == expected["ui_errors"]

ids = [open(f"/tmp/dynamic_containers/c{i}_id").read().strip() for i in range(1,5)]
mem = [open(f"/tmp/dynamic_containers/c{i}_mem").read().strip() for i in range(1,5)]
assert mem == ["100MB", "287MB", "100MB", "500MB"]

calls = [line.rstrip("\n").split("\t", 1) for line in open("/tmp/manager_calls")]
assert any(c[0] == "list" for c in calls)
logged = {c[1] for c in calls if c[0] == "logs" and len(c) > 1}
restarted = [c[1] for c in calls if c[0] == "restart" and len(c) > 1]
assert logged == set(ids), (logged, ids)
assert restarted == [ids[0], ids[2]], restarted

tools = open("/tmp/tool_calls").read().splitlines()
assert any(x.startswith("awk\t") for x in tools), tools
assert any(x.startswith("grep\t") and "Dashboard UI Error" in x for x in tools), tools
PY
fi

cleanup
trap - EXIT
if [ "$ok" = 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
