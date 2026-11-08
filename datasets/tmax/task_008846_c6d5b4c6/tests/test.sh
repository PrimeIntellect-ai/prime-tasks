#!/bin/bash
mkdir -p /logs/verifier

DROPPER_BACKUP=""
BWRAP_REAL=""
BWRAP_BACKUP=""
AUDIT_LOG=""

cleanup() {
    if [ -n "$DROPPER_BACKUP" ] && [ -f "$DROPPER_BACKUP" ]; then
        cp -a "$DROPPER_BACKUP" /home/user/dropper
        rm -f "$DROPPER_BACKUP"
    fi
    if [ -n "$BWRAP_REAL" ] && [ -n "$BWRAP_BACKUP" ] && [ -e "$BWRAP_BACKUP" ]; then
        rm -f "$BWRAP_REAL"
        mv "$BWRAP_BACKUP" "$BWRAP_REAL"
    fi
    [ -n "$AUDIT_LOG" ] && rm -f "$AUDIT_LOG"
}
trap cleanup EXIT

run_tests() {
    test -f /home/user/analyzer.cpp || return 1

    # Compile the submitted source into the exact artifact required by the task.
    g++ -o /home/user/analyzer /home/user/analyzer.cpp -lcrypto || return 1
    test -f /home/user/analyzer && test -x /home/user/analyzer || return 1

    DROPPER_BACKUP=$(mktemp /tmp/dropper.original.XXXXXX) || return 1
    cp -a /home/user/dropper "$DROPPER_BACKUP" || return 1

    # Interpose only to record Bubblewrap's actual argv, then immediately execute
    # the genuine Bubblewrap binary. This also catches absolute bwrap paths.
    BWRAP_REAL=$(readlink -f "$(command -v bwrap)") || return 1
    BWRAP_BACKUP="${BWRAP_REAL}.verifier.$$"
    mv "$BWRAP_REAL" "$BWRAP_BACKUP" || return 1
    cat > "$BWRAP_REAL" <<WRAP_EOF
#!/bin/bash
printf '%s\\0' "\$@" > "\$BWRAP_AUDIT_LOG"
exec "$BWRAP_BACKUP" "\$@"
WRAP_EOF
    chmod 755 "$BWRAP_REAL" || return 1

    # Replace the payload temporarily with an unpredictable executable so that
    # hardcoded hashes and output cannot satisfy the behavioral test.
    TOKEN=$(python3 -c 'import secrets; print("VERIFIER_DYNAMIC_" + secrets.token_hex(24))') || return 1
    cat > /tmp/verifier_dropper.cpp <<EOF
#include <iostream>
int main() { std::cout << "$TOKEN" << std::endl; return 0; }
EOF
    g++ -o /home/user/dropper /tmp/verifier_dropper.cpp || return 1
    chmod 755 /home/user/dropper || return 1
    rm -f /tmp/verifier_dropper.cpp /home/user/dropper_hash.txt /home/user/dropper_output.txt

    AUDIT_LOG=$(mktemp -u /tmp/bwrap.audit.XXXXXX) || return 1
    timeout 30s runuser -u user -- env BWRAP_AUDIT_LOG="$AUDIT_LOG" /home/user/analyzer || return 1

    python3 - "$TOKEN" "$AUDIT_LOG" <<'PY' || return 1
import hashlib
import os
import stat
import sys

token, audit_log = sys.argv[1:]

analyzer = "/home/user/analyzer"
st = os.stat(analyzer)
assert stat.S_ISREG(st.st_mode), "analyzer is not a regular file"
assert st.st_mode & 0o111, "analyzer is not executable"
with open(analyzer, "rb") as f:
    assert f.read(4) == b"\x7fELF", "analyzer is not a compiled ELF executable"

with open("/home/user/dropper", "rb") as f:
    expected_hash = hashlib.sha256(f.read()).hexdigest()
with open("/home/user/dropper_hash.txt", "r") as f:
    assert f.read().strip() == expected_hash, "analyzer did not hash the dynamic payload"
with open("/home/user/dropper_output.txt", "r") as f:
    assert f.read() == token + "\n", "analyzer did not capture the dynamic payload output"

with open(audit_log, "rb") as f:
    args = f.read().split(b"\0")
if args and args[-1] == b"":
    args.pop()
expected = [
    b"--ro-bind", b"/", b"/", b"--dev", b"/dev",
    b"--unshare-all", b"/home/user/dropper",
]
assert args == expected, "analyzer did not invoke Bubblewrap with the exact required arguments"
PY

    # Restore the supplied payload and run the compiled analyzer again so the
    # required final artifacts describe the original payload.
    cp -a "$DROPPER_BACKUP" /home/user/dropper || return 1
    rm -f /home/user/dropper_hash.txt /home/user/dropper_output.txt "$AUDIT_LOG"
    timeout 30s runuser -u user -- env BWRAP_AUDIT_LOG="$AUDIT_LOG" /home/user/analyzer || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib
import pytest

def test_cert_verify_log():
    log_path = "/home/user/cert_verify.log"
    assert os.path.isfile(log_path), f"Missing file: {log_path}"

    with open(log_path, "r") as f:
        content = f.read()

    assert "/home/user/cert.pem: OK" in content, "cert_verify.log does not contain the expected verification success message."

def test_dropper_hash():
    dropper_path = "/home/user/dropper"
    hash_path = "/home/user/dropper_hash.txt"

    assert os.path.isfile(dropper_path), f"Missing file: {dropper_path}"
    assert os.path.isfile(hash_path), f"Missing file: {hash_path}"

    sha256 = hashlib.sha256()
    with open(dropper_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    expected_hash = sha256.hexdigest()

    with open(hash_path, "r") as f:
        actual_hash = f.read().strip()

    assert actual_hash == expected_hash, f"Hash in {hash_path} does not match the actual SHA-256 hash of {dropper_path}."

def test_dropper_output():
    output_path = "/home/user/dropper_output.txt"
    assert os.path.isfile(output_path), f"Missing file: {output_path}"

    with open(output_path, "r") as f:
        content = f.read()

    expected_output = "EXPLOIT_PAYLOAD_EXECUTION_SUCCESSFUL_C2_CONNECTING...\n"
    assert content == expected_output, "dropper_output.txt does not contain the exact expected output from the sandboxed execution."

def test_analyzer_cpp():
    cpp_path = "/home/user/analyzer.cpp"
    assert os.path.isfile(cpp_path), f"Missing file: {cpp_path}"

    with open(cpp_path, "r") as f:
        content = f.read()

    assert "#include <openssl/sha.h>" in content, "analyzer.cpp is missing the required OpenSSL SHA header inclusion."
    assert "bwrap" in content, "analyzer.cpp does not contain the required bwrap invocation."
    assert "--ro-bind / /" in content, "analyzer.cpp does not contain the required bwrap arguments."
    assert "--dev /dev" in content, "analyzer.cpp does not contain the required bwrap arguments."
    assert "--unshare-all" in content, "analyzer.cpp does not contain the required bwrap arguments."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if run_tests; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
