#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_monitor.py
import os
import shutil
import socket
import subprocess
import tempfile
import uuid

HOME = "/home/user"
SOURCE = os.path.join(HOME, "monitor.go")
BINARY = "/tmp/monitor_verifier_bin"
LINKS = os.path.join(HOME, "monitored_links")
SPOOL = os.path.join(HOME, "mail_spool")
LOG = os.path.join(HOME, "monitor.log")
NODES = os.path.join(HOME, "storage_nodes")
QUOTA = 10_485_760


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def fresh_dir(path):
    if os.path.lexists(path):
        remove_path(path)
    os.makedirs(path)


def make_file(path, size):
    with open(path, "wb") as f:
        f.truncate(size)


def run_monitor():
    result = subprocess.run(
        [BINARY], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"monitor program exited with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def clear_outputs():
    fresh_dir(SPOOL)
    if os.path.lexists(LOG):
        remove_path(LOG)


def file_size_sum(path):
    return sum(
        os.path.getsize(os.path.join(path, name))
        for name in os.listdir(path)
        if os.path.isfile(os.path.join(path, name))
    )


def assert_alert(name, expected_size):
    path = os.path.join(SPOOL, f"alert_{name}.txt")
    assert os.path.isfile(path), f"Expected alert file {path} was not created."
    with open(path, "r") as f:
        actual = f.read().strip()
    expected = f"To: admin@local\nSubject: Quota exceeded for {name}\nSize: {expected_size}"
    assert actual == expected, (
        f"Content of {path} is incorrect. Expected:\n{expected}\nGot:\n{actual}"
    )


# Preserve the original existence assertion, then require a real compilable Go artifact.
assert os.path.isfile(SOURCE), "The Go program /home/user/monitor.go does not exist."
build = subprocess.run(
    ["go", "build", "-o", BINARY, SOURCE], cwd=HOME,
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
)
assert build.returncode == 0, f"monitor.go did not compile:\n{build.stdout}\n{build.stderr}"
assert os.path.isfile(BINARY), "Compiling monitor.go did not produce an executable."

# Hold the relay address bound but non-listening, making TCP connection attempts fail
# deterministically with connection refused during both executions.
blocker = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    blocker.bind(("127.0.0.1", 9025))
except OSError as exc:
    raise AssertionError(f"Could not reserve 127.0.0.1:9025 for the connectivity test: {exc}")

try:
    # Recreate and execute against the original fixture, retaining all original checks.
    fresh_dir(NODES)
    for node, size in (("node1", 5 * 1024 * 1024),
                       ("node2", 15 * 1024 * 1024),
                       ("node3", 25 * 1024 * 1024)):
        node_dir = os.path.join(NODES, node)
        os.makedirs(node_dir)
        make_file(os.path.join(node_dir, "data.bin"), size)

    fresh_dir(LINKS)
    os.symlink(os.path.join(NODES, "node1"), os.path.join(LINKS, "app_data"))
    os.symlink(os.path.join(NODES, "node2"), os.path.join(LINKS, "user_data"))
    os.symlink(os.path.join(NODES, "node3"), os.path.join(LINKS, "backup_data"))
    os.symlink(os.path.join(NODES, "nonexistent"), os.path.join(LINKS, "legacy_data"))
    clear_outputs()
    run_monitor()

    assert os.path.isfile(LOG), f"The log file {LOG} was not created."
    with open(LOG, "r") as f:
        original_log = f.read()
    assert "ERROR: Broken link legacy_data" in original_log, (
        "The log file does not contain the expected error for the broken link 'legacy_data'."
    )
    assert "WARN: Email server unreachable" in original_log, (
        "The log file does not contain the expected warning for the unreachable email server."
    )

    assert os.path.isdir(SPOOL), f"The mail spool directory {SPOOL} does not exist."
    node2_size = file_size_sum(os.path.join(NODES, "node2"))
    node3_size = file_size_sum(os.path.join(NODES, "node3"))
    assert_alert("user_data", node2_size)
    assert_alert("backup_data", node3_size)
    assert not os.path.exists(os.path.join(SPOOL, "alert_app_data.txt")), (
        "Alert file for app_data should not exist (under quota)."
    )
    assert not os.path.exists(os.path.join(SPOOL, "alert_legacy_data.txt")), (
        "Alert file for legacy_data should not exist (broken link)."
    )
    original_files = {
        name for name in os.listdir(SPOOL)
        if os.path.isfile(os.path.join(SPOOL, name))
    }
    assert original_files == {"alert_user_data.txt", "alert_backup_data.txt"}, (
        f"Found unexpected files in {SPOOL}: "
        f"{original_files - {'alert_user_data.txt', 'alert_backup_data.txt'}}"
    )

    # Exercise the compiled program again with unpredictable link names and sizes.
    token = uuid.uuid4().hex
    under_name = f"under_{token}"
    over_a_name = f"over_a_{token}"
    over_b_name = f"over_b_{token}"
    broken_name = f"broken_{token}"

    with tempfile.TemporaryDirectory(prefix="monitor_targets_") as targets:
        under_dir = os.path.join(targets, "under")
        over_a_dir = os.path.join(targets, "over_a")
        over_b_dir = os.path.join(targets, "over_b")
        os.makedirs(under_dir)
        os.makedirs(over_a_dir)
        os.makedirs(over_b_dir)

        make_file(os.path.join(under_dir, "part.bin"), QUOTA)
        make_file(os.path.join(over_a_dir, "first.bin"), QUOTA + 1000 + len(token))
        make_file(os.path.join(over_a_dir, "second.bin"), 317)
        make_file(os.path.join(over_b_dir, "payload.bin"), QUOTA + 7000 + len(token))

        expected_a = file_size_sum(over_a_dir)
        expected_b = file_size_sum(over_b_dir)
        expected_under = file_size_sum(under_dir)

        fresh_dir(LINKS)
        os.symlink(under_dir, os.path.join(LINKS, under_name))
        os.symlink(over_a_dir, os.path.join(LINKS, over_a_name))
        os.symlink(over_b_dir, os.path.join(LINKS, over_b_name))
        os.symlink(os.path.join(targets, "does_not_exist"), os.path.join(LINKS, broken_name))
        clear_outputs()
        run_monitor()

        assert file_size_sum(under_dir) == expected_under
        assert file_size_sum(over_a_dir) == expected_a
        assert file_size_sum(over_b_dir) == expected_b

        assert os.path.isfile(LOG), "The randomized run did not create monitor.log."
        with open(LOG, "r") as f:
            dynamic_log = f.read()
        assert f"ERROR: Broken link {broken_name}" in dynamic_log, (
            "The randomized broken symlink was not reported."
        )
        assert dynamic_log.count("WARN: Email server unreachable") == 1, (
            "The unreachable email warning must be written exactly once per run."
        )

        assert_alert(over_a_name, expected_a)
        assert_alert(over_b_name, expected_b)
        assert not os.path.exists(os.path.join(SPOOL, f"alert_{under_name}.txt")), (
            "An alert was generated for a directory that does not exceed the quota."
        )
        assert not os.path.exists(os.path.join(SPOOL, f"alert_{broken_name}.txt")), (
            "An alert was generated for a broken symlink."
        )
        dynamic_files = {
            name for name in os.listdir(SPOOL)
            if os.path.isfile(os.path.join(SPOOL, name))
        }
        expected_files = {f"alert_{over_a_name}.txt", f"alert_{over_b_name}.txt"}
        assert dynamic_files == expected_files, (
            f"Unexpected alert files from randomized run: {dynamic_files ^ expected_files}"
        )
finally:
    blocker.close()
PY_EOF

python3 /tmp/verify_monitor.py
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
