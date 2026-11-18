#!/bin/bash
mkdir -p /logs/verifier

workdir=$(mktemp -d /tmp/rotator-verifier.XXXXXX)
trace_file="$workdir/rotator.strace"
test_file="$workdir/test_final_state.py"
token_backup="$workdir/token.txt"
ok=1

binary=/home/user/bin/rotator
token=/home/user/token.txt
log=/home/user/rotated_password.log

# Require the supplied token and the compiled executable artifact.
if [ ! -f "$token" ] || [ -L "$token" ] || [ ! -s "$token" ]; then
    ok=0
fi
if [ ! -f "$binary" ] || [ -L "$binary" ] || [ ! -x "$binary" ]; then
    ok=0
fi
if [ "$ok" -eq 1 ]; then
    magic=$(dd if="$binary" bs=1 count=4 2>/dev/null | od -An -tx1 | tr -d '[:space:]')
    [ "$magic" = "7f454c46" ] || ok=0
fi

# First exercise the binary with a known-invalid token. It must reject it and
# must not create a successful-rotation log.
if [ "$ok" -eq 1 ]; then
    cp -- "$token" "$token_backup" || ok=0
fi
if [ "$ok" -eq 1 ]; then
    rm -f -- "$log" || ok=0
    printf '%s\n' 'e30=.e30=.invalid' > "$token" || ok=0
fi
if [ "$ok" -eq 1 ]; then
    /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/timeout 10s "$binary" >"$workdir/invalid.stdout" 2>"$workdir/invalid.stderr"
    invalid_rc=$?
    if [ "$invalid_rc" -eq 0 ] || [ -e "$log" ]; then
        ok=0
    fi
fi

# Restore the agent's crafted token, remove any pre-created result, and execute
# the binary under strace so the successful log creation is attributable to it.
if [ -f "$token_backup" ]; then
    cat "$token_backup" > "$token" || ok=0
else
    ok=0
fi
rm -f -- "$log" || ok=0

if [ "$ok" -eq 1 ]; then
    /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/timeout 10s \
        /usr/bin/strace -f -qq -s 4096 -e trace=openat,write \
        -o "$trace_file" "$binary" >"$workdir/valid.stdout" 2>"$workdir/valid.stderr"
    [ $? -eq 0 ] || ok=0
fi

if [ "$ok" -eq 1 ]; then
    grep -Fq '"/home/user/token.txt"' "$trace_file" || ok=0
    grep -Fq '"/home/user/rotated_password.log"' "$trace_file" || ok=0
    grep -Fq 'admin:SuperSecret123!\n' "$trace_file" || ok=0
fi

cat << 'TEST_EOF' > "$test_file"
import os

def test_rotated_password_log_exists():
    """Verify that the rotated_password.log file was created."""
    log_path = "/home/user/rotated_password.log"
    assert os.path.isfile(log_path), f"The file {log_path} does not exist. The binary did not run successfully or the exploit failed."

def test_rotated_password_log_content():
    """Verify that the rotated_password.log contains the correct rotated credentials."""
    log_path = "/home/user/rotated_password.log"
    assert os.path.isfile(log_path), f"The file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_content = "admin:SuperSecret123!"
    assert content == expected_content, f"The content of {log_path} is incorrect. Expected '{expected_content}', got '{content}'."
TEST_EOF

if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$test_file" -x --tb=short >"$workdir/pytest.out" 2>&1; then
    ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -rf -- "$workdir"
