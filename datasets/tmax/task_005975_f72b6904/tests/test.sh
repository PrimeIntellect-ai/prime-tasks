#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shlex
import shutil
import stat
import subprocess
import tempfile


def test_hardened_users_txt():
    """Retain the original fixture and permission checks."""
    hardened_path = "/home/user/hardened_users.txt"
    assert os.path.isfile(hardened_path), f"{hardened_path} does not exist."

    perms = stat.S_IMODE(os.stat(hardened_path).st_mode)
    assert perms == 0o444, f"Expected permissions 0444 for {hardened_path}, got {oct(perms)}"

    expected_contents = (
        "alice:wheel:/bin/bash\n"
        "bob:developers:/usr/sbin/nologin\n"
        "charlie:interns:/usr/sbin/nologin\n"
        "david:wheel:/bin/zsh\n"
        "eve:contractors:/usr/sbin/nologin"
    )
    with open(hardened_path, "r") as f:
        actual_contents = f.read().strip()
    assert actual_contents == expected_contents, f"Contents of {hardened_path} do not match the expected hardened state."


def test_setup_env_idempotence():
    """Retain the original rerun/idempotence assertion."""
    script_path = "/home/user/setup_env.sh"
    hardened_path = "/home/user/hardened_users.txt"
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {script_path} failed with error: {result.stderr}"

    expected_contents = (
        "alice:wheel:/bin/bash\n"
        "bob:developers:/usr/sbin/nologin\n"
        "charlie:interns:/usr/sbin/nologin\n"
        "david:wheel:/bin/zsh\n"
        "eve:contractors:/usr/sbin/nologin"
    )
    with open(hardened_path, "r") as f:
        actual_contents = f.read().strip()
    assert actual_contents == expected_contents, "Running setup_env.sh a second time altered the output file incorrectly (not idempotent)."


def test_setup_env_transforms_dynamic_input_and_is_cron_executable():
    """Exercise the script directly on an unpredictable legacy-user fixture."""
    script_path = "/home/user/setup_env.sh"
    legacy_path = "/home/user/legacy_users.txt"
    hardened_path = "/home/user/hardened_users.txt"

    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable by cron."

    with open(legacy_path, "rb") as f:
        old_legacy = f.read()
    old_hardened = None
    old_hardened_mode = None
    if os.path.exists(hardened_path):
        with open(hardened_path, "rb") as f:
            old_hardened = f.read()
        old_hardened_mode = stat.S_IMODE(os.stat(hardened_path).st_mode)

    token = secrets.token_hex(8)
    rows = [
        ("admin_" + token, "wheel", "/bin/zsh"),
        ("service_" + token, "ops_" + token, "/bin/bash"),
        ("guest_" + token, "visitors", "/bin/sh"),
        ("rootlike_" + token, "wheel", "/usr/bin/fish"),
    ]
    legacy = "\n".join(":".join(row) for row in rows) + "\n"
    expected = "\n".join(
        f"{username}:{group}:{shell if group == 'wheel' else '/usr/sbin/nologin'}"
        for username, group, shell in rows
    )

    cron_env = {
        "HOME": "/root",
        "LOGNAME": "root",
        "USER": "root",
        "SHELL": "/bin/sh",
        "PATH": "/usr/bin:/bin",
    }

    try:
        os.chmod(hardened_path, 0o644) if os.path.exists(hardened_path) else None
        with open(legacy_path, "w") as f:
            f.write(legacy)

        first = subprocess.run([script_path], env=cron_env, capture_output=True, text=True, timeout=10)
        assert first.returncode == 0, f"Direct cron-style execution failed: {first.stderr}"
        with open(hardened_path, "r") as f:
            first_output = f.read().strip()
        assert first_output == expected, "setup_env.sh did not derive hardened users from the dynamic input."
        assert stat.S_IMODE(os.stat(hardened_path).st_mode) == 0o444

        first_bytes = open(hardened_path, "rb").read()
        second = subprocess.run([script_path], env=cron_env, capture_output=True, text=True, timeout=10)
        assert second.returncode == 0, f"Second direct execution failed: {second.stderr}"
        second_bytes = open(hardened_path, "rb").read()
        assert second_bytes == first_bytes, "Repeated execution did not produce the exact same file."
        assert stat.S_IMODE(os.stat(hardened_path).st_mode) == 0o444
    finally:
        with open(legacy_path, "wb") as f:
            f.write(old_legacy)
        if old_hardened is None:
            if os.path.exists(hardened_path):
                os.chmod(hardened_path, 0o644)
                os.unlink(hardened_path)
        else:
            if os.path.exists(hardened_path):
                os.chmod(hardened_path, 0o644)
            with open(hardened_path, "wb") as f:
                f.write(old_hardened)
            os.chmod(hardened_path, old_hardened_mode)


def test_start_vm_script():
    """Retain textual checks, then execute the sole command against a QEMU stub."""
    script_path = "/home/user/start_vm.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    perms = stat.S_IMODE(os.stat(script_path).st_mode)
    assert perms == 0o755, f"Expected permissions 0755 for {script_path}, got {oct(perms)}"

    with open(script_path, "r") as f:
        content = f.read()

    assert "qemu-system-x86_64" in content, "qemu-system-x86_64 command not found in start_vm.sh"
    assert re.search(r"-m\s+512M?", content), "-m 512 or -m 512M not found in start_vm.sh"
    assert re.search(r"-hda\s+/home/user/disk\.qcow2", content), "-hda /home/user/disk.qcow2 not found in start_vm.sh"
    assert "-nographic" in content, "-nographic not found in start_vm.sh"
    assert re.search(r"-vnc\s+127\.0\.0\.1:2,password=on", content), "-vnc 127.0.0.1:2,password=on not found in start_vm.sh"

    syntax = subprocess.run(["bash", "-n", script_path], capture_output=True, text=True)
    assert syntax.returncode == 0, f"start_vm.sh is not valid Bash: {syntax.stderr}"

    real_qemu = shutil.which("qemu-system-x86_64")
    assert real_qemu, "qemu-system-x86_64 is unavailable in the test environment"
    backup_qemu = real_qemu + f".verifier-backup-{os.getpid()}"

    with tempfile.TemporaryDirectory() as td:
        capture = os.path.join(td, "args")
        trace_path = os.path.join(td, "trace")
        path_stub = os.path.join(td, "qemu-system-x86_64")
        stub = "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$QEMU_CAPTURE\"\n"
        with open(path_stub, "w") as f:
            f.write(stub)
        os.chmod(path_stub, 0o755)

        os.rename(real_qemu, backup_qemu)
        try:
            with open(real_qemu, "w") as f:
                f.write(stub)
            os.chmod(real_qemu, 0o755)

            env = os.environ.copy()
            env["PATH"] = td + ":/usr/bin:/bin"
            env["QEMU_CAPTURE"] = capture
            env["PS4"] = "+ "
            with open(trace_path, "w+") as trace_file:
                env["BASH_XTRACEFD"] = str(trace_file.fileno())
                result = subprocess.run(
                    ["bash", "-x", script_path],
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=10,
                    pass_fds=(trace_file.fileno(),),
                )
                trace_file.seek(0)
                trace_lines = [line.strip() for line in trace_file if line.strip()]
        finally:
            if os.path.exists(real_qemu):
                os.unlink(real_qemu)
            os.rename(backup_qemu, real_qemu)

        assert result.returncode == 0, f"Executing start_vm.sh against a QEMU stub failed: {result.stderr}"
        assert os.path.isfile(capture), "start_vm.sh did not actually execute qemu-system-x86_64."
        assert len(trace_lines) == 1, f"start_vm.sh must contain one command; executed trace was: {trace_lines}"

        traced = trace_lines[0]
        if traced.startswith("+"):
            traced = traced[1:].strip()
        words = shlex.split(traced)
        assert words and os.path.basename(words[0]) == "qemu-system-x86_64", f"The sole command was not QEMU: {trace_lines[0]}"

        with open(capture, "r") as f:
            args = f.read().splitlines()

        def option_value(name):
            assert name in args, f"Missing QEMU option {name}; actual arguments: {args}"
            index = args.index(name)
            assert index + 1 < len(args), f"QEMU option {name} has no value"
            return args[index + 1]

        assert option_value("-m") in ("512", "512M")
        assert option_value("-hda") == "/home/user/disk.qcow2"
        assert "-nographic" in args
        assert option_value("-vnc") == "127.0.0.1:2,password=on"


def test_cron_job_and_preservation():
    """Retain the original cron assertion and require an active exact entry."""
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab"
    crontab_output = result.stdout

    expected_pattern = r"15\s+3\s+\*\s+\*\s+\*\s+/home/user/setup_env\.sh"
    assert re.search(expected_pattern, crontab_output), "Cron job for /home/user/setup_env.sh at 3:15 AM not found in crontab."

    active = []
    for line in crontab_output.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#") and not re.match(r"^[A-Za-z_][A-Za-z0-9_]*\s*=", stripped):
            active.append(stripped)
    parsed = [re.split(r"\s+", line, maxsplit=5) for line in active]
    assert any(
        len(fields) == 6
        and fields[:5] == ["15", "3", "*", "*", "*"]
        and fields[5] == "/home/user/setup_env.sh"
        for fields in parsed
    ), "The required schedule must be an active cron entry with the exact command."

    sentinel = f"7 1 * * * /bin/true # verifier-preserve-{secrets.token_hex(8)}"
    augmented = crontab_output.rstrip("\n") + "\n" + sentinel + "\n"
    installed = subprocess.run(["crontab", "-"], input=augmented, capture_output=True, text=True)
    assert installed.returncode == 0, f"Could not install preservation fixture: {installed.stderr}"
    try:
        cron_env = {
            "HOME": "/root",
            "LOGNAME": "root",
            "USER": "root",
            "SHELL": "/bin/sh",
            "PATH": "/usr/bin:/bin",
        }
        run = subprocess.run(["/home/user/setup_env.sh"], env=cron_env, capture_output=True, text=True, timeout=10)
        assert run.returncode == 0, f"The scheduled command is not executable in a cron-like environment: {run.stderr}"
        after = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
        assert after.returncode == 0
        assert sentinel in after.stdout, "A pre-existing cron entry was removed."
        assert re.search(expected_pattern, after.stdout), "The required cron entry disappeared."
    finally:
        subprocess.run(["crontab", "-"], input=crontab_output, capture_output=True, text=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
