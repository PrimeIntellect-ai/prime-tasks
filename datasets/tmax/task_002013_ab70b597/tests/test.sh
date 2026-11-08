#!/bin/bash
set +e
mkdir -p /logs/verifier

EMU_LAUNCH_PID=""
NGINX_LAUNCH_PID=""

cleanup() {
    runuser -u user -- nginx -p /home/user/project/ -c /home/user/project/nginx.conf -s stop >/dev/null 2>&1 || true
    [ -n "$NGINX_LAUNCH_PID" ] && kill "$NGINX_LAUNCH_PID" >/dev/null 2>&1 || true
    [ -n "$EMU_LAUNCH_PID" ] && kill "$EMU_LAUNCH_PID" >/dev/null 2>&1 || true
    pkill -x nginx >/dev/null 2>&1 || true
    pkill -x emulator >/dev/null 2>&1 || true
}

run_checks() {
    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re

def test_success_log_exists():
    log_path = "/home/user/success.log"
    assert os.path.exists(log_path), f"File {log_path} does not exist. Did you run the curl command and save the output?"

def test_success_log_content():
    log_path = "/home/user/success.log"
    with open(log_path, "r") as f:
        content = f.read()

    assert re.search(r"X-Sandbox-Secure:\s*true", content, re.IGNORECASE), "The 'X-Sandbox-Secure: true' header is missing from the success log."
    assert "EXECUTION_SUCCESS" in content, "The body 'EXECUTION_SUCCESS' is missing from the success log."
    assert re.search(r"^HTTP/\S+\s+200\b", content, re.MULTILINE), "The success log does not contain a complete successful HTTP response."

def test_c_lib_compiled():
    so_path = "/home/user/project/c_lib/libcrypto_dummy.so"
    assert os.path.exists(so_path), f"Shared object {so_path} does not exist. Did you compile the C library?"

def test_nginx_conf_exists():
    conf_path = "/home/user/project/nginx.conf"
    assert os.path.exists(conf_path), f"Nginx config {conf_path} does not exist."
    with open(conf_path, "r") as f:
        content = f.read()
    assert "8080" in content, "Nginx config does not seem to listen on port 8080."
    assert "9000" in content, "Nginx config does not seem to proxy to port 9000."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    # Ensure the submitted library is a loadable shared object implementing the
    # expected C interface, rather than an arbitrary file with the right name.
    python3 - << 'PY' || return 1
import ctypes
p = "/home/user/project/c_lib/libcrypto_dummy.so"
with open(p, "rb") as f:
    assert f.read(4) == b"\x7fELF", "libcrypto_dummy.so is not an ELF object"
lib = ctypes.CDLL(p)
verify = lib.verify_bytecode
verify.argtypes = [ctypes.c_char_p]
verify.restype = ctypes.c_int
assert verify(b"1") == 1
assert verify(b"0") == 0
assert verify(b"random-invalid-bytecode") == 0
PY

    # Rebuild from the submitted Rust sources and linking configuration.
    cd /home/user/project/emulator || return 1
    timeout 180 cargo clean || return 1
    timeout 180 cargo build || return 1
    [ -x /home/user/project/emulator/target/debug/emulator ] || return 1

    cleanup
    sleep 1

    # Both services must be startable without root. LD_LIBRARY_PATH only makes
    # the submitted C library available at runtime; cargo must still have linked it.
    runuser -u user -- env LD_LIBRARY_PATH=/home/user/project/c_lib \
        /home/user/project/emulator/target/debug/emulator \
        > /home/user/project/nginx_temp/verifier_emulator.log 2>&1 &
    EMU_LAUNCH_PID=$!

    for _ in $(seq 1 30); do
        curl -sS --max-time 1 http://127.0.0.1:9000/run?code=1 >/dev/null 2>&1 && break
        sleep 0.2
    done
    curl -sS --max-time 2 http://127.0.0.1:9000/run?code=1 >/dev/null || return 1

    # Parsing and startup as the unprivileged user validate the user-space pid,
    # log, and temporary-path configuration in addition to the proxy directives.
    runuser -u user -- nginx -t -p /home/user/project/ -c /home/user/project/nginx.conf || return 1
    runuser -u user -- nginx -p /home/user/project/ -c /home/user/project/nginx.conf \
        > /home/user/project/nginx_temp/verifier_nginx.log 2>&1 &
    NGINX_LAUNCH_PID=$!

    ready=0
    for _ in $(seq 1 30); do
        if curl -sS --max-time 1 http://127.0.0.1:8080/run?code=1 >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 0.2
    done
    [ "$ready" -eq 1 ] || return 1

    nonce="invalid_${RANDOM}_${RANDOM}"
    code=$(curl -sS --max-time 5 -D /tmp/secure_headers_ok -o /tmp/secure_body_ok \
        -w '%{http_code}' "http://127.0.0.1:8080/run?code=1") || return 1
    [ "$code" = "200" ] || return 1
    grep -Eiq '^X-Sandbox-Secure:[[:space:]]*true[[:space:]]*$' /tmp/secure_headers_ok || return 1
    [ "$(tr -d '\r\n' < /tmp/secure_body_ok)" = "EXECUTION_SUCCESS" ] || return 1

    code=$(curl -sS --max-time 5 -D /tmp/secure_headers_bad -o /tmp/secure_body_bad \
        -w '%{http_code}' "http://127.0.0.1:8080/run?code=${nonce}") || return 1
    [ "$code" = "200" ] || return 1
    grep -Eiq '^X-Sandbox-Secure:[[:space:]]*true[[:space:]]*$' /tmp/secure_headers_bad || return 1
    [ "$(tr -d '\r\n' < /tmp/secure_body_bad)" = "EXECUTION_FAILED" ] || return 1

    return 0
}

run_checks
status=$?
cleanup

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
