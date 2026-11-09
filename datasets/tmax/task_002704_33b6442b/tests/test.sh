#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shlex
import stat
import string
import subprocess

HOME = "/home/user"
CPP = f"{HOME}/proxy.cpp"
LOG = f"{HOME}/proxy.log"


def random_text(prefix=""):
    alphabet = string.ascii_letters + string.digits + "_-"
    return prefix + "".join(secrets.choice(alphabet) for _ in range(24))


def run_proxy(binary, value):
    return subprocess.run(
        [binary], input=(value + "\n").encode(), capture_output=True, timeout=10
    )


def assert_proxy_behavior(binary):
    valid_inputs = [
        "COST_REQUEST_1",
        "COST",
        random_text("COST"),
        "COST " + random_text(),
    ]
    invalid_inputs = [
        "SPAM_REQUEST_2",
        "",
        random_text("COS"),
        random_text("cost"),
        " COST" + random_text(),
        random_text("X"),
    ]
    cases = [(v, "FORWARD") for v in valid_inputs] + [(v, "DROP") for v in invalid_inputs]
    secrets.SystemRandom().shuffle(cases)

    if os.path.lexists(LOG):
        os.unlink(LOG)

    expected_log = []
    for value, expected in cases:
        proc = run_proxy(binary, value)
        assert proc.returncode == 0, f"Proxy exited with {proc.returncode}: {proc.stderr.decode(errors='replace')}"
        assert proc.stdout.decode().strip() == expected, f"Expected {expected!r} for {value!r}, got {proc.stdout!r}"
        if expected == "DROP":
            expected_log.append(f"[BLOCKED] {value}\n")

    assert os.path.isfile(LOG), f"Log file {LOG} was not created."
    with open(LOG, "r", encoding="utf-8") as f:
        log_content = f.read()
    assert "[BLOCKED] SPAM_REQUEST_2" in log_content, "Log file did not contain the expected '[BLOCKED] <input>' message."
    assert log_content == "".join(expected_log), "The proxy did not append exactly one correctly formatted entry for each blocked input."


def test_proxy_cpp_compilation_and_logic():
    assert os.path.isfile(CPP), f"{CPP} does not exist."
    test_bin = f"/tmp/test_proxy_{secrets.token_hex(8)}"
    try:
        compile_proc = subprocess.run(["g++", CPP, "-o", test_bin], capture_output=True, timeout=30)
        assert compile_proc.returncode == 0, f"Failed to compile {CPP}:\n{compile_proc.stderr.decode()}"
        assert_proxy_behavior(test_bin)
    finally:
        if os.path.lexists(test_bin):
            os.unlink(test_bin)


def parse_logrotate_config(path):
    global_directives = []
    target_directives = None
    current_paths = None
    current_directives = []

    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    for raw in lines:
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue

        if current_paths is None:
            if "{" in line:
                header, remainder = line.split("{", 1)
                current_paths = shlex.split(header)
                current_directives = []
                line = remainder.strip()
                if not line:
                    continue
            else:
                global_directives.append(shlex.split(line))
                continue

        if "}" in line:
            before, after = line.split("}", 1)
            if before.strip():
                current_directives.append(shlex.split(before.strip()))
            if LOG in current_paths:
                assert target_directives is None, f"{LOG} is configured in multiple stanzas."
                target_directives = list(global_directives) + current_directives
            current_paths = None
            current_directives = []
            assert not after.strip(), "Unexpected content following a logrotate stanza."
        elif line:
            current_directives.append(shlex.split(line))

    assert current_paths is None, "Unclosed logrotate stanza."
    assert target_directives is not None, f"No logrotate stanza manages {LOG}."
    return [tokens for tokens in target_directives if tokens]


def test_logrotate_conf():
    conf_path = f"{HOME}/logrotate.conf"
    assert os.path.isfile(conf_path), f"{conf_path} does not exist."

    with open(conf_path, "r", encoding="utf-8") as f:
        content = f.read().lower()
    assert "daily" in content, "logrotate.conf is missing the 'daily' directive."
    assert "rotate 2" in content, "logrotate.conf is missing the 'rotate 2' directive."
    assert "compress" in content, "logrotate.conf is missing the 'compress' directive."
    assert "missingok" in content, "logrotate.conf is missing the 'missingok' directive."

    directives = parse_logrotate_config(conf_path)
    frequency_names = {"hourly", "daily", "weekly", "monthly", "yearly"}
    frequencies = [d[0].lower() for d in directives if d[0].lower() in frequency_names]
    assert frequencies and frequencies[-1] == "daily", f"The effective rotation frequency for {LOG} is not daily."

    rotations = [d[1:] for d in directives if d[0].lower() == "rotate"]
    assert rotations and rotations[-1] == ["2"], f"The effective rotate count for {LOG} is not exactly 2."

    compression = [d[0].lower() for d in directives if d[0].lower() in {"compress", "nocompress"}]
    assert compression and compression[-1] == "compress", f"Compression is not enabled for {LOG}."

    missing = [d[0].lower() for d in directives if d[0].lower() in {"missingok", "nomissingok"}]
    assert missing and missing[-1] == "missingok", f"missingok is not enabled for {LOG}."


def trace_commands(stderr):
    commands = []
    for line in stderr.decode(errors="replace").splitlines():
        if "__DEPLOY_TRACE__ " not in line:
            continue
        text = line.split("__DEPLOY_TRACE__ ", 1)[1].strip()
        try:
            commands.append(shlex.split(text))
        except ValueError:
            pass
    return commands


def positional_args(command):
    result = []
    options_done = False
    for arg in command[1:]:
        if not options_done and arg == "--":
            options_done = True
        elif not options_done and arg.startswith("-"):
            continue
        else:
            result.append(arg)
    return result


def test_deploy_script():
    script_path = f"{HOME}/deploy.sh"
    active_path = f"{HOME}/proxy_active"
    backup_path = f"{HOME}/proxy_backup"
    v2_path = f"{HOME}/proxy_v2"

    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    for path in (active_path, backup_path, v2_path):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                raise AssertionError(f"Unexpected directory at {path}")
            os.unlink(path)

    token = secrets.token_hex(24)
    original = f"#!/bin/sh\n# original-active-{token}\nexit 73\n".encode()
    with open(active_path, "wb") as f:
        f.write(original)
    os.chmod(active_path, 0o755)

    bash_env = f"/tmp/deploy_bash_env_{secrets.token_hex(8)}"
    with open(bash_env, "w", encoding="utf-8") as f:
        f.write("PS4='__DEPLOY_TRACE__ '\nset -x\n")
    env = os.environ.copy()
    env["BASH_ENV"] = bash_env

    try:
        deploy_proc = subprocess.run([script_path], capture_output=True, env=env, timeout=60)
    finally:
        os.unlink(bash_env)

    assert deploy_proc.returncode == 0, f"deploy.sh failed with error:\n{deploy_proc.stderr.decode(errors='replace')}"

    assert os.path.isfile(backup_path), f"Backup file {backup_path} does not exist."
    assert os.path.isfile(v2_path), f"Compiled binary {v2_path} does not exist."
    assert os.path.islink(active_path), f"{active_path} is not a symbolic link."
    assert os.access(v2_path, os.X_OK), f"{v2_path} is not executable."

    with open(backup_path, "rb") as f:
        assert f.read() == original, "proxy_backup is not the active proxy that existed immediately before deployment."
    with open(v2_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "proxy_v2 is not a compiled native binary."

    target = os.readlink(active_path)
    assert target == v2_path, f"Symlink {active_path} points to {target}, expected {v2_path}."

    commands = trace_commands(deploy_proc.stderr)
    compile_seen = False
    move_seen = False
    link_seen = False
    for command in commands:
        if not command:
            continue
        name = os.path.basename(command[0])
        args = command[1:]
        if name in {"g++", "c++"} and CPP in args:
            output_ok = any(arg == v2_path for i, arg in enumerate(args) if i > 0 and args[i - 1] == "-o")
            output_ok = output_ok or any(arg == "-o" + v2_path for arg in args)
            compile_seen = compile_seen or output_ok
        if name == "mv" and positional_args(command)[-2:] == [active_path, backup_path]:
            move_seen = True
        if name == "ln":
            operands = positional_args(command)
            has_symbolic_flag = any(arg.startswith("-") and "s" in arg[1:] for arg in command[1:])
            if has_symbolic_flag and operands[-2:] == [v2_path, active_path]:
                link_seen = True

    assert compile_seen, "deploy.sh did not compile proxy.cpp into proxy_v2."
    assert move_seen, "deploy.sh did not move proxy_active to proxy_backup."
    assert link_seen, "deploy.sh did not create the required symbolic link with ln -s."

    assert_proxy_behavior(v2_path)


if __name__ == "__main__":
    test_proxy_cpp_compilation_and_logic()
    test_logrotate_conf()
    test_deploy_script()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
