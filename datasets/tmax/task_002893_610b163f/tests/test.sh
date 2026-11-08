#!/bin/bash
mkdir -p /logs/verifier

TOOLS_DIR="$(mktemp -d /run/verifier-tools.XXXXXX)" || {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}
AUDIT_LOG="$TOOLS_DIR/audit.log"
MANIFEST="$TOOLS_DIR/manifest"
touch "$AUDIT_LOG" "$MANIFEST"
chmod 666 "$AUDIT_LOG"
chmod 755 "$TOOLS_DIR"

restore_wrappers() {
    if [ -f "$MANIFEST" ]; then
        while IFS='|' read -r target original; do
            [ -n "$target" ] || continue
            rm -f "$target"
            mv "$original" "$target" 2>/dev/null || true
        done < "$MANIFEST"
    fi
    rm -rf "$TOOLS_DIR"
}
trap restore_wrappers EXIT

install_wrapper() {
    name="$1"
    target="$(readlink -f "$(command -v "$name")")" || return 1
    original="$TOOLS_DIR/${name}.real"
    mv "$target" "$original" || return 1
    printf '%s|%s\n' "$target" "$original" >> "$MANIFEST"

    cat > "$target" <<WRAPPER_EOF
#!/bin/sh
out=""
if [ "$name" = "ip" ]; then
    out=\$(readlink /proc/self/fd/1 2>/dev/null || true)
fi
args="\$*"
printf '%s\n' "CALL|$name|\$args|OUT=\$out" >> "$AUDIT_LOG"
"$original" "\$@"
rc=\$?
printf '%s\n' "DONE|$name|\$args|RC=\$rc|OUT=\$out" >> "$AUDIT_LOG"
exit \$rc
WRAPPER_EOF
    chmod 755 "$target"
}

setup_ok=1
for cmd in unshare bash ip mount mkdir cp; do
    install_wrapper "$cmd" || setup_ok=0
done

if [ "$setup_ok" -ne 1 ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shlex
import subprocess
import pytest

SCRIPT = "/home/user/automate_container.py"
OUTPUT = "/home/user/routes_output.json"
AUDIT = os.environ["AUDIT_LOG"]


def test_script_exists():
    """Verify that the user created the automation script."""
    assert os.path.isfile(SCRIPT), "The script /home/user/automate_container.py does not exist."


def _tokens(event):
    return shlex.split(event[2])


def _successful_done(events, call_index):
    call = events[call_index]
    for i in range(call_index + 1, len(events)):
        event = events[i]
        if event[0] == "DONE" and event[1] == call[1] and event[2] == call[2] and "RC=0" in event[3:]:
            return i
    pytest.fail(f"Command did not complete successfully: {call[1]} {call[2]}")


def _find_call(events, predicate, start=0):
    for i in range(start, len(events)):
        if events[i][0] == "CALL" and predicate(events[i]):
            return i
    pytest.fail("A required namespace command was not executed")


def test_script_execution_and_output():
    """Run the script, verify its namespace operations, and verify the resulting output file."""
    try:
        os.remove(OUTPUT)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "python3", SCRIPT],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Script execution failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}\nStdout: {result.stdout}"
    )

    assert os.path.exists(OUTPUT), f"The expected output file {OUTPUT} was not created."
    with open(OUTPUT, "r") as f:
        try:
            routes = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {OUTPUT} does not contain valid JSON.")

    assert isinstance(routes, list), f"The JSON in {OUTPUT} should be a list of routes."

    found_route = False
    for route in routes:
        if route.get('dst') == '192.168.100.0/24' and route.get('dev') == 'net0':
            found_route = True
            break
    assert found_route, "The correct route for 192.168.100.0/24 on net0 was not found in the output JSON."

    with open(AUDIT, "r") as f:
        events = [line.rstrip("\n").split("|") for line in f if line.strip()]

    exact_unshare = "--user --map-root-user --net --mount --fork /bin/bash --noprofile --norc"
    unshare_i = _find_call(events, lambda e: e[1] == "unshare" and e[2] == exact_unshare)
    bash_i = _find_call(events, lambda e: e[1] == "bash" and _tokens(e) == ["--noprofile", "--norc"], unshare_i + 1)

    def ip_words(e):
        return _tokens(e) if e[1] == "ip" else []

    lo_i = _find_call(events, lambda e: e[1] == "ip" and "link" in ip_words(e) and "set" in ip_words(e) and "lo" in ip_words(e) and "up" in ip_words(e), bash_i + 1)
    dummy_i = _find_call(events, lambda e: e[1] == "ip" and "link" in ip_words(e) and "add" in ip_words(e) and "net0" in ip_words(e) and "type" in ip_words(e) and "dummy" in ip_words(e), lo_i + 1)
    addr_i = _find_call(events, lambda e: e[1] == "ip" and ("addr" in ip_words(e) or "address" in ip_words(e)) and "add" in ip_words(e) and "192.168.100.1/24" in ip_words(e) and "net0" in ip_words(e), dummy_i + 1)
    up_i = _find_call(events, lambda e: e[1] == "ip" and "link" in ip_words(e) and "set" in ip_words(e) and "net0" in ip_words(e) and "up" in ip_words(e), addr_i + 1)
    mkdir_i = _find_call(events, lambda e: e[1] == "mkdir" and "/mnt/ramdisk" in _tokens(e), up_i + 1)

    def is_tmpfs_mount(e):
        words = _tokens(e)
        return e[1] == "mount" and "/mnt/ramdisk" in words and "-t" in words and words.index("-t") + 1 < len(words) and words[words.index("-t") + 1] == "tmpfs"

    mount_i = _find_call(events, is_tmpfs_mount, mkdir_i + 1)

    def is_route_dump(e):
        words = _tokens(e)
        json_flag = "-j" in words or "--json" in words or "-json" in words
        return e[1] == "ip" and json_flag and "route" in words and "OUT=/mnt/ramdisk/routes.json" in e[3:]

    route_i = _find_call(events, is_route_dump, mount_i + 1)
    cp_i = _find_call(events, lambda e: e[1] == "cp" and "/mnt/ramdisk/routes.json" in _tokens(e) and OUTPUT in _tokens(e) and _tokens(e).index("/mnt/ramdisk/routes.json") < _tokens(e).index(OUTPUT), route_i + 1)

    step_calls = [lo_i, dummy_i, addr_i, up_i, mkdir_i, mount_i, route_i, cp_i]
    for position, call_i in enumerate(step_calls):
        done_i = _successful_done(events, call_i)
        if position + 1 < len(step_calls):
            assert done_i < step_calls[position + 1], "Required namespace steps were not completed sequentially"

    bash_done = _successful_done(events, bash_i)
    unshare_done = _successful_done(events, unshare_i)
    assert cp_i < bash_done < unshare_done, "The namespace shell was not exited gracefully after copying the routes"
TEST_EOF

if AUDIT_LOG="$AUDIT_LOG" python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
