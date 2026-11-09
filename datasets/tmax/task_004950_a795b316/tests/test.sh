#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import base64
import hashlib
import pytest

REPORT_PATH = "/home/user/report.json"
PROC_DUMP_DIR = "/home/user/proc_dump"
HASHES_PATH = "/home/user/hashes.txt"

def get_authorized_hashes():
    hashes = set()
    if os.path.exists(HASHES_PATH):
        with open(HASHES_PATH, "r") as f:
            for line in f:
                h = line.strip()
                if h:
                    hashes.add(h)
    return hashes

def compute_expected_findings():
    authorized_hashes = get_authorized_hashes()
    expected_findings = []

    if not os.path.isdir(PROC_DUMP_DIR):
        return expected_findings

    for pid_str in os.listdir(PROC_DUMP_DIR):
        if not pid_str.isdigit():
            continue

        pid = int(pid_str)
        pid_dir = os.path.join(PROC_DUMP_DIR, pid_str)

        exe_path = os.path.join(pid_dir, "exe")
        integrity_valid = False
        if os.path.isfile(exe_path):
            with open(exe_path, "rb") as f:
                exe_data = f.read()
                exe_hash = hashlib.sha256(exe_data).hexdigest()
                if exe_hash in authorized_hashes:
                    integrity_valid = True

        cmdline_path = os.path.join(pid_dir, "cmdline")
        redacted_token = ""
        if os.path.isfile(cmdline_path):
            with open(cmdline_path, "rb") as f:
                cmdline_data = f.read()

            args = cmdline_data.split(b'\0')
            for arg in args:
                if arg.startswith(b'--token='):
                    b64_token = arg[8:]
                    try:
                        decoded = base64.b64decode(b64_token).decode('utf-8')
                        if len(decoded) > 2:
                            redacted_token = decoded[:2] + '*' * (len(decoded) - 2)
                        else:
                            redacted_token = decoded[:2]
                    except Exception:
                        pass
                    break

        expected_findings.append({
            "pid": pid,
            "redacted_token": redacted_token,
            "integrity_valid": integrity_valid
        })

    expected_findings.sort(key=lambda x: x["pid"])
    return expected_findings

def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."

def test_report_json_format():
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Report is not valid JSON.")

    assert isinstance(data, dict), "Report JSON must be an object."
    assert "csp_policy" in data, "Missing 'csp_policy' key in report."
    assert "findings" in data, "Missing 'findings' key in report."

def test_csp_policy():
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    assert data.get("csp_policy") == "default-src 'none';", "Incorrect csp_policy value."

def test_findings_content():
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    actual_findings = data.get("findings", [])
    expected_findings = compute_expected_findings()

    assert len(actual_findings) == len(expected_findings), \
        f"Expected {len(expected_findings)} findings, got {len(actual_findings)}."

    pids = [f.get("pid") for f in actual_findings]
    assert pids == sorted(pids), "Findings are not sorted by pid in ascending order."

    for expected, actual in zip(expected_findings, actual_findings):
        assert actual.get("pid") == expected["pid"], \
            f"PID mismatch: expected {expected['pid']}, got {actual.get('pid')}"
        assert actual.get("redacted_token") == expected["redacted_token"], \
            f"Redacted token mismatch for PID {expected['pid']}: expected '{expected['redacted_token']}', got '{actual.get('redacted_token')}'"
        assert actual.get("integrity_valid") == expected["integrity_valid"], \
            f"Integrity valid mismatch for PID {expected['pid']}: expected {expected['integrity_valid']}, got {actual.get('integrity_valid')}"
TEST_EOF

verify_task() (
    set -e
    PROJECT=/home/user/auditor
    MANIFEST="$PROJECT/Cargo.toml"

    test -d "$PROJECT"
    test -f "$MANIFEST"

    selection=$(cargo metadata --manifest-path "$MANIFEST" --no-deps --format-version 1 | python3 -c '
import json, os, sys
m = json.load(sys.stdin)
manifest = os.path.realpath(sys.argv[1])
packages = [p for p in m["packages"] if os.path.realpath(p["manifest_path"]) == manifest]
if len(packages) != 1:
    raise SystemExit("Cargo.toml must define a package")
p = packages[0]
bins = [t for t in p["targets"] if "bin" in t.get("kind", [])]
if p.get("default_run"):
    bins = [t for t in bins if t["name"] == p["default_run"]]
if len(bins) != 1:
    raise SystemExit("Cargo project must have one unambiguous runnable binary")
t = bins[0]
src = os.path.realpath(t["src_path"])
root = os.path.realpath(os.path.dirname(manifest))
if not src.endswith(".rs") or not os.path.isfile(src) or os.path.commonpath([root, src]) != root:
    raise SystemExit("binary target must be backed by Rust source inside the project")
print(t["name"] + "\t" + src)
' "$MANIFEST")

    case "$selection" in
        *$'\t'*) ;;
        *) exit 1 ;;
    esac
    BIN_NAME=${selection%%$'\t'*}
    SRC_PATH=${selection#*$'\t'}
    test -f "$SRC_PATH"

    BUILD_LOG=$(mktemp)
    timeout 120s cargo build --manifest-path "$MANIFEST" --bin "$BIN_NAME" --message-format=json-render-diagnostics > "$BUILD_LOG"
    EXECUTABLE=$(python3 - "$BUILD_LOG" "$BIN_NAME" "$SRC_PATH" <<'PY'
import json, os, sys
log, name, source = sys.argv[1:]
found = []
with open(log, encoding="utf-8") as f:
    for line in f:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        target = event.get("target", {})
        executable = event.get("executable")
        if (event.get("reason") == "compiler-artifact" and executable
                and target.get("name") == name
                and "bin" in target.get("kind", [])
                and os.path.realpath(target.get("src_path", "")) == os.path.realpath(source)):
            found.append(executable)
if not found:
    raise SystemExit("no compiled Rust binary artifact found")
print(found[-1])
PY
)
    test -f "$EXECUTABLE"
    test -x "$EXECUTABLE"

    rm -f /home/user/report.json
    (cd "$PROJECT" && timeout 30s "$EXECUTABLE")
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

    python3 <<'PY'
import base64
import hashlib
import os

root = "/home/user/proc_dump"
cases = {
    1042: (b"changed_alpha", "two"),
    2055: (b"changed_beta", "updated_secret"),
    3099: (b"changed_gamma", "ok"),
    7777: (b"new_authorized_binary", "xy_dynamic_42"),
}
for pid, (exe_data, token) in cases.items():
    directory = os.path.join(root, str(pid))
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, "exe"), "wb") as f:
        f.write(exe_data)
    encoded = base64.b64encode(token.encode("utf-8"))
    with open(os.path.join(directory, "cmdline"), "wb") as f:
        f.write(b"dynamic_app\0--mode=audit\0--token=" + encoded + b"\0")

# The changed 2055 and new 7777 executables are authorized; the others are not.
with open("/home/user/hashes.txt", "w", encoding="ascii") as f:
    for pid in (2055, 7777):
        exe_path = os.path.join(root, str(pid), "exe")
        with open(exe_path, "rb") as exe:
            f.write(hashlib.sha256(exe.read()).hexdigest() + "\n")
PY

    rm -f /home/user/report.json
    (cd "$PROJECT" && timeout 30s "$EXECUTABLE")
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
)

if verify_task 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
