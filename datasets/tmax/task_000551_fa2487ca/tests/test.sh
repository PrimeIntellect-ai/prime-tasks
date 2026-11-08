#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
STATE="/root/.audit_verify_${TOKEN}"
KEY_BACKUP="${STATE}/keys"
REAL_BWRAP="/usr/bin/.bwrap.real.${TOKEN}"
REAL_OPENSSL="/usr/bin/.openssl.real.${TOKEN}"
mkdir -p "$KEY_BACKUP"
chmod 700 "$STATE" "$KEY_BACKUP"
cp -a /home/user/artifacts/ssh_keys/key1 /home/user/artifacts/ssh_keys/key2 /home/user/artifacts/ssh_keys/key3 "$KEY_BACKUP/"

cleanup() {
    set +e
    if [ -e "$REAL_BWRAP" ]; then
        rm -f /usr/bin/bwrap
        mv "$REAL_BWRAP" /usr/bin/bwrap
    fi
    if [ -e "$REAL_OPENSSL" ]; then
        rm -f /usr/bin/openssl
        mv "$REAL_OPENSSL" /usr/bin/openssl
    fi
    for key in key1 key2 key3; do
        if [ -e "$KEY_BACKUP/$key" ]; then
            cp -a "$KEY_BACKUP/$key" "/home/user/artifacts/ssh_keys/$key"
        fi
    done
    rm -rf "$STATE"
}
trap cleanup EXIT

# Replace the three test inputs with fresh keys. The sole unencrypted key is
# deliberately not key2, and its fingerprint is generated for this run.
PASS1="p_${TOKEN}_1"
PASS2="p_${TOKEN}_2"
ssh-keygen -q -t rsa -b 2048 -N "$PASS1" -f "$STATE/generated1"
ssh-keygen -q -t ed25519 -N "$PASS2" -f "$STATE/generated2"
ssh-keygen -q -t ecdsa -b 256 -N "" -f "$STATE/generated3"
cp "$STATE/generated1" /home/user/artifacts/ssh_keys/key1
cp "$STATE/generated2" /home/user/artifacts/ssh_keys/key2
cp "$STATE/generated3" /home/user/artifacts/ssh_keys/key3
chmod 600 /home/user/artifacts/ssh_keys/key1 /home/user/artifacts/ssh_keys/key2 /home/user/artifacts/ssh_keys/key3
ssh-keygen -lf /home/user/artifacts/ssh_keys/key3 | awk '{print $2}' > "$STATE/expected_fingerprint"

mv /usr/bin/bwrap "$REAL_BWRAP"
mv /usr/bin/openssl "$REAL_OPENSSL"

cat > /usr/bin/bwrap <<WRAP_EOF
#!/bin/bash
real='$REAL_BWRAP'
state='$STATE'
token='$TOKEN'
unshare=0
robind=0
tmpfs=0
args=("\$@")
for ((i=0; i<\${#args[@]}; i++)); do
    [ "\${args[i]}" = "--unshare-all" ] && unshare=1
    if [ "\${args[i]}" = "--ro-bind" ] && [ "\${args[i+1]:-}" = "/" ] && [ "\${args[i+2]:-}" = "/" ]; then
        robind=1
    fi
    if [ "\${args[i]}" = "--tmpfs" ] && [ "\${args[i+1]:-}" = "/tmp" ]; then
        tmpfs=1
    fi
done
if [ "\$unshare\$robind\$tmpfs" = "111" ]; then
    printf '%s\n' compliant > "\$state/bwrap_seen"
    export AUDIT_VERIFY_TOKEN="\$token"
    exec 3>> "\$state/openssl_events"
    exec "\$real" --preserve-fds 1 "\$@"
fi
exec "\$real" "\$@"
WRAP_EOF
chmod 755 /usr/bin/bwrap

cat > /usr/bin/openssl <<WRAP_EOF
#!/bin/bash
real='$REAL_OPENSSL'
token='$TOKEN'
is_verify=0
for arg in "\$@"; do
    [ "\$arg" = "verify" ] && is_verify=1
done
if [ "\${AUDIT_VERIFY_TOKEN:-}" = "\$token" ] && [ "\$is_verify" = 1 ]; then
    tmp="\$(mktemp /tmp/audit-openssl.XXXXXX)"
    "\$real" "\$@" > "\$tmp"
    rc=\$?
    {
        echo BEGIN
        for arg in "\$@"; do
            printf 'A:'
            printf '%s' "\$arg" | base64 -w0
            printf '\n'
        done
        printf 'O:'
        base64 -w0 "\$tmp"
        printf '\nR:%s\nEND\n' "\$rc"
    } >&3
    cat "\$tmp"
    rm -f "\$tmp"
    exit "\$rc"
fi
exec "\$real" "\$@"
WRAP_EOF
chmod 755 /usr/bin/openssl

export AUDIT_VERIFY_STATE="$STATE"
rm -f /home/user/audit_log.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import subprocess

SCRIPT = "/home/user/secure_audit.sh"
LOG = "/home/user/audit_log.txt"
STATE = os.environ["AUDIT_VERIFY_STATE"]


def test_00_execute_secure_audit_script():
    result = subprocess.run(
        [SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=60
    )
    assert result.returncode == 0, (
        f"Audit script exited with {result.returncode}. stderr: {result.stderr}"
    )


def test_secure_audit_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_secure_audit_script_uses_bwrap():
    with open(SCRIPT, "r") as f:
        content = f.read()
    assert "bwrap" in content, "The script does not use 'bwrap' as required."
    assert "--unshare-all" in content, "The script does not use '--unshare-all' with bwrap."
    assert "--ro-bind / /" in content, "The script does not use '--ro-bind / /' with bwrap."
    assert "--tmpfs /tmp" in content, "The script does not use '--tmpfs /tmp' with bwrap."


def _openssl_events():
    path = os.path.join(STATE, "openssl_events")
    assert os.path.isfile(path), "No openssl verify command ran inside the compliant bwrap sandbox."
    events = []
    current = None
    with open(path, "r", encoding="ascii") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if line == "BEGIN":
                current = {"args": []}
            elif line == "END" and current is not None:
                events.append(current)
                current = None
            elif current is not None and line.startswith("A:"):
                current["args"].append(base64.b64decode(line[2:]).decode())
            elif current is not None and line.startswith("O:"):
                current["stdout"] = base64.b64decode(line[2:]).decode()
            elif current is not None and line.startswith("R:"):
                current["returncode"] = int(line[2:])
    return events


def test_certificate_verification_actually_ran_in_bwrap():
    assert os.path.isfile(os.path.join(STATE, "bwrap_seen")), (
        "bwrap was not invoked with --unshare-all, --ro-bind / /, and --tmpfs /tmp."
    )
    matching = []
    for event in _openssl_events():
        args = event["args"]
        if "verify" in args and "/home/user/artifacts/certs/leaf.pem" in args:
            matching.append(event)
    assert matching, "Sandboxed openssl verify did not verify leaf.pem."
    event = matching[-1]
    assert event.get("returncode") == 0, "Sandboxed certificate verification failed."
    args = event["args"]
    assert any(a == "-CAfile" or a.startswith("-CAfile=") for a in args), (
        "openssl verify did not use a constructed CA bundle via -CAfile."
    )

    with open(LOG, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    actual_stdout = event.get("stdout", "").strip()
    assert lines[1] == actual_stdout, (
        "Audit log line 2 is not the actual stdout of the sandboxed openssl verify command."
    )


def test_audit_log_contents():
    assert os.path.isfile(LOG), f"Audit log {LOG} does not exist."
    with open(os.path.join(STATE, "expected_fingerprint"), "r") as f:
        expected_fingerprint = f.read().strip()
    expected_line1 = f"Vulnerable Key Fingerprint: {expected_fingerprint}"
    expected_line2 = "/home/user/artifacts/certs/leaf.pem: OK"
    with open(LOG, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert len(lines) >= 2, f"Audit log {LOG} does not contain enough lines."
    assert lines[0] == expected_line1, (
        f"Line 1 mismatch. Expected: '{expected_line1}', Got: '{lines[0]}'"
    )
    assert lines[1] == expected_line2, (
        f"Line 2 mismatch. Expected: '{expected_line2}', Got: '{lines[1]}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
