#!/bin/bash
set -u
mkdir -p /logs/verifier

run_verification() {
    # Preserve the original final-state assertions.
    python3 - <<'PY'
import os
import stat

found = "/home/user/found_backup.txt"
assert os.path.isfile(found), f"File {found} does not exist."
with open(found, "r") as f:
    content = f.read().strip()
assert content == "service_77.bin", f"Expected 'service_77.bin' in {found}, but found '{content}'."
assert stat.S_IMODE(os.stat(found).st_mode) & stat.S_IRUSR, f"File {found} is not readable."

exploit = "/home/user/exploit.bin"
assert os.path.isfile(exploit), f"File {exploit} does not exist."
expected_pt = b'{"user":"attacker","role":"system_root"}'
key = b"\xde\xad\xbe\xef"
expected_ct = bytes(expected_pt[i] ^ key[i % 4] for i in range(len(expected_pt)))
with open(exploit, "rb") as f:
    actual_ct = f.read()
assert actual_ct == expected_ct, f"The contents of {exploit} do not match the expected ciphertext."
assert stat.S_IMODE(os.stat(exploit).st_mode) & stat.S_IRUSR, f"File {exploit} is not readable."
PY
    [ $? -eq 0 ] || return 1

    # Require submitted Go source and compile it into fresh executables.
    mapfile -d '' sources < <(find /home/user -type f -name '*.go' -print0)
    [ ${#sources[@]} -gt 0 ] || return 1

    build_dir=$(mktemp -d)
    state_dir=$(mktemp -d)
    cp -a /home/user/captures "$state_dir/captures"
    cp -a /home/user/found_backup.txt "$state_dir/found_backup.txt"
    cp -a /home/user/exploit.bin "$state_dir/exploit.bin"

    restore_state() {
        rm -rf /home/user/captures
        cp -a "$state_dir/captures" /home/user/captures
        cp -a "$state_dir/found_backup.txt" /home/user/found_backup.txt
        cp -a "$state_dir/exploit.bin" /home/user/exploit.bin
        rm -rf "$build_dir" "$state_dir"
    }
    trap restore_state RETURN

    declare -a binaries=()
    declare -a workdirs=()
    declare -A seen_dirs=()
    n=0

    # First try building each source directory as a normal Go package.
    for src in "${sources[@]}"; do
        dir=$(dirname "$src")
        if [ -z "${seen_dirs[$dir]+x}" ]; then
            seen_dirs[$dir]=1
            out="$build_dir/program_$n"
            if (cd "$dir" && go build -o "$out" . >/dev/null 2>&1) || \
               (cd "$dir" && GO111MODULE=off go build -o "$out" . >/dev/null 2>&1); then
                binaries+=("$out")
                workdirs+=("$dir")
                n=$((n + 1))
            fi
        fi
    done

    # Also support multiple standalone Go programs in one directory.
    for src in "${sources[@]}"; do
        out="$build_dir/program_$n"
        if go build -o "$out" "$src" >/dev/null 2>&1; then
            binaries+=("$out")
            workdirs+=("$(dirname "$src")")
            n=$((n + 1))
        fi
    done

    [ ${#binaries[@]} -gt 0 ] || return 1

    # Replace the captures with an independently generated case so hardcoded
    # output files cannot pass. The submitted, freshly compiled Go artifact(s)
    # must recover the new key, scan for the randomized backup filename, and
    # regenerate the exploit ciphertext.
    rm -rf /home/user/captures
    mkdir -p /home/user/captures
    VERIFY_STATE="$state_dir" python3 - <<'PY'
import os
import secrets

root = "/home/user/captures"
state = os.environ["VERIFY_STATE"]
key = secrets.token_bytes(4)
suffix = secrets.token_hex(6)
backup_name = f"capture_{suffix}.bin"

def enc(data):
    return bytes(b ^ key[i % 4] for i, b in enumerate(data))

captures = {
    "admin_login.bin": b'{"user":"admin","role":"administrator"}',
    f"ordinary_{secrets.token_hex(4)}.bin": b'{"user":"charlie","role":"user"}',
    f"audit_{secrets.token_hex(4)}.bin": b'{"user":"auditor","role":"read_only"}',
    backup_name: b'{"user":"rotating_service","role":"system_backup"}',
}
for name, plaintext in captures.items():
    with open(os.path.join(root, name), "wb") as f:
        f.write(enc(plaintext))

payload = b'{"user":"attacker","role":"system_root"}'
with open(os.path.join(state, "dynamic_name"), "w") as f:
    f.write(backup_name)
with open(os.path.join(state, "dynamic_exploit"), "wb") as f:
    f.write(enc(payload))
PY
    rm -f /home/user/found_backup.txt /home/user/exploit.bin

    success=0
    for i in "${!binaries[@]}"; do
        (cd "${workdirs[$i]}" && timeout 15s "${binaries[$i]}" >/dev/null 2>&1) || true

        if VERIFY_STATE="$state_dir" python3 - <<'PY'
import os
import stat

state = os.environ["VERIFY_STATE"]
found = "/home/user/found_backup.txt"
exploit = "/home/user/exploit.bin"
if not os.path.isfile(found) or not os.path.isfile(exploit):
    raise SystemExit(1)
with open(os.path.join(state, "dynamic_name")) as f:
    expected_name = f.read()
with open(found) as f:
    actual_name = f.read().strip()
if actual_name != expected_name:
    raise SystemExit(1)
with open(os.path.join(state, "dynamic_exploit"), "rb") as f:
    expected_ct = f.read()
with open(exploit, "rb") as f:
    actual_ct = f.read()
if actual_ct != expected_ct:
    raise SystemExit(1)
if not (stat.S_IMODE(os.stat(found).st_mode) & stat.S_IRUSR):
    raise SystemExit(1)
if not (stat.S_IMODE(os.stat(exploit).st_mode) & stat.S_IRUSR):
    raise SystemExit(1)
PY
        then
            success=1
            break
        fi
    done

    [ "$success" -eq 1 ]
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
