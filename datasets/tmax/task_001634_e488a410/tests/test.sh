#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shlex
import stat
import subprocess
import tempfile


def test_bashrc_exports():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"File missing: {bashrc_path}"

    with open(bashrc_path, "r") as f:
        content = f.read()

    assert "export SG_USER=admin" in content, "export SG_USER=admin is missing from .bashrc"
    assert "export SG_PASS=secret123" in content, "export SG_PASS=secret123 is missing from .bashrc"

    result = subprocess.run(
        ["bash", "--noprofile", "--rcfile", bashrc_path, "-ic", "printf '%s\\n%s\\n' \"$SG_USER\" \"$SG_PASS\""],
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == ["admin", "secret123"], ".bashrc does not export the required values in an interactive shell"


def test_success_log():
    log_path = "/home/user/success.log"
    assert os.path.isfile(log_path), f"File missing: {log_path}"

    with open(log_path, "r") as f:
        content = f.read().strip().splitlines()

    expected = [
        "[SUCCESS] 10.0.1.0/24 via 192.168.1.254",
        "[SUCCESS] 172.16.0.0/16 via 192.168.1.254",
        "[SUCCESS] 192.168.100.0/24 via 10.0.0.1"
    ]

    assert content == expected, f"success.log content does not match expected output.\nExpected:\n{expected}\nGot:\n{content}"


def test_scripts_exist_and_executable():
    scripts = [
        "/home/user/auto-sg.exp",
        "/home/user/diagnose.sh"
    ]

    for script in scripts:
        assert os.path.isfile(script), f"Script is missing: {script}"
        assert os.access(script, os.X_OK), f"Script is not executable: {script}"

    with open("/home/user/auto-sg.exp", "r", errors="replace") as f:
        auto_first_line = f.readline().lower()
    with open("/home/user/diagnose.sh", "r", errors="replace") as f:
        diagnose_first_line = f.readline().lower()
    assert auto_first_line.startswith("#!") and "expect" in auto_first_line, "auto-sg.exp must be an executable Expect script"
    assert diagnose_first_line.startswith("#!") and ("bash" in diagnose_first_line or "sh" in diagnose_first_line), "diagnose.sh must be an executable shell script"


def test_scripts_behavior_with_derived_inputs():
    auto_path = "/home/user/auto-sg.exp"
    diagnose_path = "/home/user/diagnose.sh"
    console_path = "/home/user/sg-console.sh"
    routes_path = "/home/user/routes.txt"
    log_path = "/home/user/success.log"
    state_path = "/home/user/.sg_routes"

    managed = [auto_path, console_path, routes_path, log_path, state_path]
    backups = {}
    for path in managed:
        if os.path.exists(path):
            with open(path, "rb") as f:
                backups[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
        else:
            backups[path] = None

    token = secrets.token_hex(8)
    trace_path = os.path.join(tempfile.gettempdir(), f"sg-trace-{token}")
    call_path = os.path.join(tempfile.gettempdir(), f"sg-calls-{token}")

    try:
        # Exercise the submitted Expect program against a fresh interactive
        # console which records every value and command it actually receives.
        octet = secrets.randbelow(180) + 20
        destination = f"10.{octet}.{secrets.randbelow(200) + 1}.0/24"
        gateway = f"192.0.2.{secrets.randbelow(200) + 1}"
        nonce = f"CONSOLE-{token}"
        console = f'''#!/bin/bash
trace={shlex.quote(trace_path)}
printf 'Secure Gateway Console {nonce}\\n'
printf 'Username: '
IFS= read -r user
printf 'Password: '
IFS= read -r pass
printf '\\n'
printf 'AUTH\\t%s\\t%s\\n' "$user" "$pass" >> "$trace"
if [ "$user" != admin ] || [ "$pass" != secret123 ]; then
    echo 'Access denied.'
    exit 1
fi
echo 'Access granted.'
while true; do
    printf 'SG> '
    IFS= read -r line || exit 1
    printf 'CMD\\t%s\\n' "$line" >> "$trace"
    case "$line" in
        "route add {destination} {gateway}") echo 'Route added.' ;;
        "ping {destination}") echo 'Reply from {destination}' ;;
        exit) echo 'Goodbye.'; exit 0 ;;
        *) echo 'Unknown command.' ;;
    esac
done
'''
        with open(console_path, "w") as f:
            f.write(console)
        os.chmod(console_path, 0o755)
        if os.path.exists(trace_path):
            os.remove(trace_path)

        env = os.environ.copy()
        env.update({"SG_USER": "admin", "SG_PASS": "secret123"})
        result = subprocess.run(
            [auto_path, destination, gateway],
            cwd="/home/user",
            env=env,
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert result.returncode == 0, f"auto-sg.exp failed:\nstdout={result.stdout}\nstderr={result.stderr}"
        assert nonce in result.stdout, "auto-sg.exp did not preserve the spawned console's native output"
        assert f"Reply from {destination}" in result.stdout, "auto-sg.exp did not complete the ping interaction"
        assert os.path.isfile(trace_path), "auto-sg.exp did not spawn /home/user/sg-console.sh"
        with open(trace_path) as f:
            trace = f.read().splitlines()
        assert trace == [
            "AUTH\tadmin\tsecret123",
            f"CMD\troute add {destination} {gateway}",
            f"CMD\tping {destination}",
            "CMD\texit",
        ], f"Unexpected console interaction: {trace}"

        # Replace the already-tested Expect program temporarily with a dynamic
        # test double. This proves diagnose.sh reads every route, passes both
        # fields to auto-sg.exp, and logs only outputs containing the required
        # successful reply for that destination.
        base = secrets.randbelow(120) + 30
        cases = [
            (f"10.{base}.1.0/24", f"198.51.100.{secrets.randbelow(50) + 1}", True),
            (f"10.{base}.2.0/24", f"198.51.100.{secrets.randbelow(50) + 60}", False),
            (f"10.{base}.3.0/24", f"203.0.113.{secrets.randbelow(100) + 1}", True),
        ]
        with open(routes_path, "w") as f:
            for dest, gw, _ in cases:
                f.write(f"{dest} {gw}\n")
        if os.path.exists(log_path):
            os.remove(log_path)
        if os.path.exists(call_path):
            os.remove(call_path)

        successful = [dest for dest, _, ok in cases if ok]
        shim = f'''#!/usr/bin/expect -f
set dest [lindex $argv 0]
set gw [lindex $argv 1]
set fh [open {shlex.quote(call_path)} a]
puts $fh "$dest\\t$gw"
close $fh
if {{$dest eq "{successful[0]}" || $dest eq "{successful[1]}"}} {{
    puts "Reply from $dest"
}} else {{
    puts "Destination unreachable"
}}
'''
        with open(auto_path, "w") as f:
            f.write(shim)
        os.chmod(auto_path, 0o755)

        result = subprocess.run(
            [diagnose_path],
            cwd="/home/user",
            env=env,
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert result.returncode == 0, f"diagnose.sh failed:\nstdout={result.stdout}\nstderr={result.stderr}"
        assert os.path.isfile(call_path), "diagnose.sh did not invoke auto-sg.exp"
        with open(call_path) as f:
            calls = f.read().splitlines()
        expected_calls = [f"{dest}\t{gw}" for dest, gw, _ in cases]
        assert calls == expected_calls, f"diagnose.sh passed incorrect route arguments: {calls}"
        assert os.path.isfile(log_path), "diagnose.sh did not create success.log"
        with open(log_path) as f:
            lines = f.read().strip().splitlines()
        expected_lines = [f"[SUCCESS] {dest} via {gw}" for dest, gw, ok in cases if ok]
        assert lines == expected_lines, f"diagnose.sh did not parse dynamic ping results correctly. Expected {expected_lines}, got {lines}"
    finally:
        for path, backup in backups.items():
            if backup is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                data, mode = backup
                with open(path, "wb") as f:
                    f.write(data)
                os.chmod(path, mode)
        for path in (trace_path, call_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
