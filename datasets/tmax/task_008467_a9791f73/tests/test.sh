#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import time


def run_calculator():
    project = "/home/user/finops_calc"
    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=project,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        "The Rust project did not run successfully with cargo run:\n"
        + result.stdout + result.stderr
    )


def expected_cost(fstab_path):
    total = 0
    with open(fstab_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 3:
                if parts[2] == "nfs":
                    total += 120
                elif parts[2] == "cifs":
                    total += 85
    return total


def read_plain_cost(output_path, expected):
    assert os.path.isfile(output_path), (
        f"Missing output file: {output_path}. The Rust program must create this."
    )
    with open(output_path, "r") as f:
        actual_cost_str = f.read().strip()
    assert actual_cost_str.isdigit(), (
        f"Output file {output_path} must contain a plain integer."
    )
    assert int(actual_cost_str) == expected, (
        f"Calculated cost {actual_cost_str} does not match expected cost {expected}."
    )


def test_rust_project_exists():
    """Verify that the Rust project was initialized."""
    cargo_toml = "/home/user/finops_calc/Cargo.toml"
    main_rs = "/home/user/finops_calc/src/main.rs"

    assert os.path.isfile(cargo_toml), f"Missing Rust project file: {cargo_toml}. Did you run 'cargo init'?"
    assert os.path.isfile(main_rs), f"Missing Rust source file: {main_rs}."


def test_network_storage_cost_calculation():
    """Build and run the Rust program, then verify its result."""
    fstab_path = "/home/user/cloud_fstab"
    output_path = "/home/user/network_storage_cost.txt"

    assert os.path.isfile(fstab_path), f"Missing required file: {fstab_path}"
    if os.path.exists(output_path):
        os.remove(output_path)

    run_calculator()
    read_plain_cost(output_path, expected_cost(fstab_path))


def test_network_storage_cost_uses_fstab_contents():
    """Exercise the Rust program on independently chosen fstab contents."""
    fstab_path = "/home/user/cloud_fstab"
    output_path = "/home/user/network_storage_cost.txt"
    with open(fstab_path, "rb") as f:
        original = f.read()

    cases = [
        (
            "# generated test\n"
            "server:/one /mnt/one nfs defaults 0 0\n"
            "//server/a /mnt/a cifs defaults 0 0\n"
            "//server/b /mnt/b cifs ro 0 0\n"
            "/dev/vda1 / ext4 defaults 1 1\n",
            290,
        ),
        (
            "/dev/vda1 / ext4 defaults 1 1\n"
            "server:/a /a nfs ro 0 0\n"
            "server:/b /b nfs rw 0 0\n"
            "server:/c /c nfs defaults 0 0\n"
            "malformed-line\n",
            360,
        ),
    ]

    try:
        for contents, expected in cases:
            with open(fstab_path, "w") as f:
                f.write(contents)
            if os.path.exists(output_path):
                os.remove(output_path)
            run_calculator()
            read_plain_cost(output_path, expected)
    finally:
        with open(fstab_path, "wb") as f:
            f.write(original)
        if os.path.isfile("/home/user/finops_calc/Cargo.toml"):
            try:
                run_calculator()
            except Exception:
                pass


def test_run_billing_vm_script():
    """Verify the VM script text and execute it against a controlled QEMU shim."""
    script_path = "/home/user/run_billing_vm.sh"

    assert os.path.isfile(script_path), f"Missing script file: {script_path}"

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "qemu-system-x86_64" in content, "Script is missing 'qemu-system-x86_64'."
    assert "-m 128" in content, "Script is missing RAM allocation '-m 128'."
    assert "-kernel /home/user/bzImage" in content, "Script is missing kernel configuration '-kernel /home/user/bzImage'."
    assert "-vnc :2" in content, "Script is missing VNC configuration '-vnc :2'."
    assert "-append" in content, "Script is missing '-append' flag."
    assert "TZ=Europe/London" in content, "Script is missing 'TZ=Europe/London' in the append string."
    assert re.search(r"(-daemonize|&)", content), (
        "Script does not appear to run the VM in the background (missing -daemonize or &)."
    )

    qemu_command = shutil.which("qemu-system-x86_64")
    assert qemu_command, "qemu-system-x86_64 is not installed."
    qemu_path = os.path.realpath(qemu_command)
    backup_path = qemu_path + ".verifier-backup"
    capture_path = "/tmp/qemu-verifier-capture.jsonl"

    for path in (backup_path, capture_path):
        if os.path.exists(path):
            os.remove(path)

    os.rename(qemu_path, backup_path)
    records = []
    try:
        with open(qemu_path, "w") as f:
            f.write("""#!/usr/bin/env python3
import json, os, sys, time
record = {"pid": os.getpid(), "args": sys.argv[1:]}
with open(os.environ["QEMU_VERIFIER_CAPTURE"], "a") as out:
    out.write(json.dumps(record) + "\\n")
    out.flush()
if "-daemonize" not in sys.argv[1:]:
    time.sleep(8)
""")
        os.chmod(qemu_path, 0o755)

        env = os.environ.copy()
        env["QEMU_VERIFIER_CAPTURE"] = capture_path
        try:
            result = subprocess.run(
                [script_path],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                env=env,
                timeout=3,
            )
        except subprocess.TimeoutExpired:
            raise AssertionError(
                "The VM script did not return promptly; QEMU must be daemonized or launched with &."
            )

        assert result.returncode == 0, f"The VM script exited with status {result.returncode}."

        deadline = time.time() + 1
        while time.time() < deadline and not os.path.isfile(capture_path):
            time.sleep(0.05)
        assert os.path.isfile(capture_path), (
            "Executing the script did not invoke qemu-system-x86_64."
        )

        with open(capture_path, "r") as f:
            records = [json.loads(line) for line in f if line.strip()]
        assert records, "Executing the script did not record a QEMU invocation."

        def has_pair(args, flag, value):
            return any(
                args[i] == flag and i + 1 < len(args) and args[i + 1] == value
                for i in range(len(args))
            )

        valid = []
        for record in records:
            args = record["args"]
            m_positions = [i for i, arg in enumerate(args) if arg == "-m"]
            ram_exact = (
                len(m_positions) == 1
                and m_positions[0] + 1 < len(args)
                and args[m_positions[0] + 1] == "128"
            )
            append_ok = any(
                args[i] == "-append"
                and i + 1 < len(args)
                and "TZ=Europe/London" in args[i + 1].split()
                for i in range(len(args))
            )
            if (
                ram_exact
                and has_pair(args, "-kernel", "/home/user/bzImage")
                and has_pair(args, "-vnc", ":2")
                and append_ok
            ):
                valid.append(record)

        assert valid, (
            "No executed QEMU command had exactly -m 128, the required kernel and VNC display, "
            "and TZ=Europe/London in its -append parameters."
        )

        background_ok = False
        for record in valid:
            if "-daemonize" in record["args"]:
                background_ok = True
                break
            try:
                os.kill(record["pid"], 0)
                background_ok = True
                break
            except ProcessLookupError:
                pass
        assert background_ok, (
            "The valid QEMU invocation was not daemonized and was not left running in the background."
        )
    finally:
        for record in records:
            try:
                os.kill(record["pid"], signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        if os.path.exists(qemu_path):
            os.remove(qemu_path)
        if os.path.exists(backup_path):
            os.rename(backup_path, qemu_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
