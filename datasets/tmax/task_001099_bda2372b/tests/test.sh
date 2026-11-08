#!/bin/bash
set -e
mkdir -p /logs/verifier

ORIGINAL=/home/user/bin/validator
SAVED=/tmp/validator.verifier-original
MARKER=/tmp/validator.verifier-marker
BIN_DIR=/home/user/bin

cleanup() {
    rm -f "$ORIGINAL" "$MARKER"
    if [ -e "$SAVED" ]; then
        mv "$SAVED" "$ORIGINAL"
        chown "$ORIG_UID:$ORIG_GID" "$ORIGINAL" 2>/dev/null || true
        chmod "$ORIG_MODE" "$ORIGINAL" 2>/dev/null || true
    fi
    chown "$DIR_UID:$DIR_GID" "$BIN_DIR" 2>/dev/null || true
    chmod "$DIR_MODE" "$BIN_DIR" 2>/dev/null || true
}

if [ ! -f "$ORIGINAL" ] || [ ! -x "$ORIGINAL" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

ORIG_UID=$(stat -c '%u' "$ORIGINAL")
ORIG_GID=$(stat -c '%g' "$ORIGINAL")
ORIG_MODE=$(stat -c '%a' "$ORIGINAL")
DIR_UID=$(stat -c '%u' "$BIN_DIR")
DIR_GID=$(stat -c '%g' "$BIN_DIR")
DIR_MODE=$(stat -c '%a' "$BIN_DIR")

rm -f "$SAVED" "$MARKER"
mv "$ORIGINAL" "$SAVED"
chown root:root "$SAVED"
chmod 755 "$SAVED"
chown root:root "$BIN_DIR"
chmod 755 "$BIN_DIR"

cat > "$ORIGINAL" <<'WRAPPER_EOF'
#!/bin/bash
printf '%s\0%s' "${DB_PASS-}" "${AUTH_TOKEN-}" > /tmp/validator.verifier-marker
exec /tmp/validator.verifier-original "$@"
WRAPPER_EOF
chown root:root "$ORIGINAL"
chmod 755 "$ORIGINAL"
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import subprocess

SCRIPT_PATH = "/home/user/triage.sh"
LOG_PATH = "/home/user/incident_resolution.log"
MARKER_PATH = "/tmp/validator.verifier-marker"


def test_triage_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_triage_script_executes_validator_with_recovered_environment():
    account = pwd.getpwnam("user")
    if os.path.lexists(MARKER_PATH):
        os.unlink(MARKER_PATH)
    if os.path.lexists(LOG_PATH):
        os.unlink(LOG_PATH)

    with open(LOG_PATH, "wb") as output:
        os.chown(LOG_PATH, account.pw_uid, account.pw_gid)

        def demote():
            os.initgroups(account.pw_name, account.pw_gid)
            os.setgid(account.pw_gid)
            os.setuid(account.pw_uid)

        result = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            env={
                "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                "HOME": "/home/user",
                "USER": "user",
                "LOGNAME": "user",
            },
            stdout=output,
            stderr=subprocess.PIPE,
            preexec_fn=demote,
            timeout=20,
        )

    assert result.returncode == 0, (
        f"triage.sh failed with exit code {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(MARKER_PATH), (
        "triage.sh did not execute /home/user/bin/validator"
    )
    with open(MARKER_PATH, "rb") as marker:
        observed = marker.read()
    assert observed == b"h1dd3n_g1t_53cr3t\0v4l1d4t0r_k3y_99", (
        "validator was not executed with the recovered DB_PASS and AUTH_TOKEN values"
    )


def test_incident_resolution_log():
    assert os.path.isfile(LOG_PATH), f"The log file {LOG_PATH} does not exist."

    with open(LOG_PATH, "r") as f:
        content = f.read().strip()

    expected_content = "SYSTEM_OK: FLAG{1nc1d3nt_r3s0lv3d}"
    assert expected_content in content, (
        f"The log file does not contain the expected success message. Found: {content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
