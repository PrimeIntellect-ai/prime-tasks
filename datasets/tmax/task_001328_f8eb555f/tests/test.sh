#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess
import textwrap

import pytest

SCRIPT = "/home/user/test_restore.py"
BACKUP = "/home/user/backup"
OUTPUTS = [
    "/home/user/nfs_mounts.log",
    "/home/user/iptables.sh",
    "/home/user/app_restarts.log",
]

ORIGINAL_FSTAB = """/dev/sda1 / ext4 defaults 1 1
10.0.0.5:/shared /mnt/shared_nfs nfs defaults 0 0
tmpfs /run tmpfs rw,nosuid,nodev 0 0
10.0.0.6:/data /opt/app_data nfs ro,hard 0 0
/dev/sdb1 /var/log xfs defaults 0 2
"""

ORIGINAL_FIREWALL = {
    "blocked_ips": ["192.168.1.50", "10.5.5.1", "172.16.0.4"]
}

ORIGINAL_FLAKY = """#!/bin/bash
# File to keep track of run count
COUNTER_FILE="/home/user/backup/.run_count"

if [ ! -f "$COUNTER_FILE" ]; then
    echo "1" > "$COUNTER_FILE"
    exit 3
fi

COUNT=$(cat "$COUNTER_FILE")

if [ "$COUNT" -eq 1 ]; then
    echo "2" > "$COUNTER_FILE"
    exit 12
elif [ "$COUNT" -eq 2 ]; then
    echo "3" > "$COUNTER_FILE"
    exit 7
else
    echo "4" > "$COUNTER_FILE"
    exit 0
fi
"""


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def clean_outputs():
    for path in OUTPUTS:
        if os.path.lexists(path):
            remove_path(path)


def write_file(path, content, mode=0o666):
    if os.path.lexists(path):
        remove_path(path)
    with open(path, "w") as f:
        f.write(content)
    os.chmod(path, mode)


def invoke_candidate():
    return subprocess.run(
        ["runuser", "-u", "user", "--", "python3", SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def install_original_inputs():
    write_file(os.path.join(BACKUP, "fstab.txt"), ORIGINAL_FSTAB)
    write_file(
        os.path.join(BACKUP, "firewall.json"),
        json.dumps(ORIGINAL_FIREWALL, indent=2) + "\n",
    )
    write_file(os.path.join(BACKUP, "flaky_app.sh"), ORIGINAL_FLAKY, 0o755)
    counter = os.path.join(BACKUP, ".run_count")
    if os.path.lexists(counter):
        remove_path(counter)


def install_flaky(counter_path, exits):
    cases = []
    for index, code in enumerate(exits, 1):
        cases.append(f"  {index}) exit {code} ;;")
    cases.append("  *) exit 0 ;;")
    body = "\n".join(cases)
    script = f"""#!/bin/bash
COUNTER_FILE='{counter_path}'
if [ -f "$COUNTER_FILE" ]; then
    COUNT=$(cat "$COUNTER_FILE")
else
    COUNT=0
fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"
case "$COUNT" in
{body}
esac
"""
    write_file(os.path.join(BACKUP, "flaky_app.sh"), script, 0o755)


def assert_success(proc):
    assert proc.returncode == 0, (
        f"test_restore.py exited with {proc.returncode}. "
        f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )


def test_candidate_executes_and_handles_derived_inputs():
    assert os.path.exists(SCRIPT), f"Required script {SCRIPT} does not exist"
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a regular file"
    assert not os.path.islink(SCRIPT), f"{SCRIPT} must be an actual Python file, not a symlink"
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} is not a regular file"

    token = secrets.token_hex(6)
    mounts = [
        f"/srv/{token}_zeta",
        f"/mnt/{token}_alpha",
        f"/opt/{token}_middle",
    ]
    ips = [
        f"10.{secrets.randbelow(200) + 1}.{secrets.randbelow(250) + 1}.{secrets.randbelow(250) + 1}",
        f"172.20.{secrets.randbelow(250) + 1}.{secrets.randbelow(250) + 1}",
        f"192.0.2.{secrets.randbelow(200) + 1}",
    ]
    counter = os.path.join(BACKUP, f".verifier_count_{token}")
    original_proc = None

    try:
        dynamic_fstab = textwrap.dedent(f"""\
            /dev/vda1 / ext4 defaults 0 1
            host-a:/one {mounts[0]} nfs rw 0 0
            /dev/vdb1 /var/lib xfs defaults 0 2
            host-b:/two {mounts[2]} nfs ro,hard 0 0
            host-c:/three {mounts[1]} nfs defaults 0 0
        """)
        write_file(os.path.join(BACKUP, "fstab.txt"), dynamic_fstab)
        write_file(
            os.path.join(BACKUP, "firewall.json"),
            json.dumps({"blocked_ips": ips}) + "\n",
        )

        # First exercise: one crash followed by success. The supervisor must stop
        # after the successful second execution.
        install_flaky(counter, [19, 0])
        clean_outputs()
        if os.path.lexists(counter):
            remove_path(counter)
        proc = invoke_candidate()
        assert_success(proc)

        assert read_nonempty_lines("/home/user/nfs_mounts.log") == sorted(mounts)
        expected_rules = ["#!/bin/bash"] + [
            f"iptables -A INPUT -s {ip} -j DROP" for ip in ips
        ]
        assert read_nonempty_lines("/home/user/iptables.sh") == expected_rules
        assert read_nonempty_lines("/home/user/app_restarts.log") == [
            "Crash detected. Exit code: 19"
        ]
        with open(counter, "r") as f:
            assert f.read().strip() == "2", "Supervisor did not stop after success"

        # Second exercise: four consecutive failures. Four executions are
        # permitted (initial attempt plus three restarts), but no fifth one.
        exits = [21, 22, 23, 24]
        install_flaky(counter, exits)
        clean_outputs()
        if os.path.lexists(counter):
            remove_path(counter)
        proc = invoke_candidate()
        assert_success(proc)
        with open(counter, "r") as f:
            assert f.read().strip() == "4", "Supervisor did not enforce the restart limit"
        assert read_nonempty_lines("/home/user/app_restarts.log") == [
            f"Crash detected. Exit code: {code}" for code in exits
        ]
    finally:
        if os.path.lexists(counter):
            remove_path(counter)
        install_original_inputs()
        clean_outputs()
        original_proc = invoke_candidate() if os.path.isfile(SCRIPT) else None

    assert original_proc is not None
    assert_success(original_proc)


# Original final-state assertions retained below.
def test_nfs_mounts_log():
    log_path = "/home/user/nfs_mounts.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. Did the script generate it?"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_mounts = [
        "/mnt/shared_nfs",
        "/opt/app_data"
    ]

    assert lines == expected_mounts, f"Content of {log_path} does not match the expected NFS mount points. Expected {expected_mounts}, but got {lines}."


def test_iptables_sh():
    script_path = "/home/user/iptables.sh"
    assert os.path.isfile(script_path), f"File {script_path} does not exist. Did the script generate it?"

    with open(script_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "#!/bin/bash",
        "iptables -A INPUT -s 192.168.1.50 -j DROP",
        "iptables -A INPUT -s 10.5.5.1 -j DROP",
        "iptables -A INPUT -s 172.16.0.4 -j DROP"
    ]
    expected_content = "\n".join(expected_lines)

    assert content == expected_content, f"Content of {script_path} does not match the expected iptables commands. Please check the shebang and the rule format."


def test_app_restarts_log():
    log_path = "/home/user/app_restarts.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. Did the script catch the crashes and generate the log?"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Crash detected. Exit code: 3",
        "Crash detected. Exit code: 12",
        "Crash detected. Exit code: 7"
    ]

    assert lines == expected_lines, f"Content of {log_path} does not match the expected crash logs. Expected {expected_lines}, but got {lines}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
