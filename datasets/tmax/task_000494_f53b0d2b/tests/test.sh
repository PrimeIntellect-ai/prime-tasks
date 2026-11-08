#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import uuid

HOME = "/home/user"
SOURCE = os.path.join(HOME, "nfs_monitor.cpp")
SCRIPT = os.path.join(HOME, "check_mounts.sh")
FSTAB = os.path.join(HOME, "custom_fstab")
OUTBOX = os.path.join(HOME, "outbox")
BINARY = os.path.join(HOME, "nfs_monitor")


def expected_alert(hostname):
    return (
        "To: netops@domain.local\n"
        "From: monitor@domain.local\n"
        f"Subject: Unreachable NFS Host: {hostname}\n"
        "\n"
        f"Error: {hostname} failed DNS resolution.\n"
    )


def reset_outbox():
    if os.path.lexists(OUTBOX):
        if os.path.isdir(OUTBOX) and not os.path.islink(OUTBOX):
            shutil.rmtree(OUTBOX)
        else:
            os.unlink(OUTBOX)
    os.mkdir(OUTBOX)


def assert_only_alert(hostname):
    txt_files = sorted(f for f in os.listdir(OUTBOX) if f.endswith(".txt"))
    expected_name = f"alert_{hostname}.txt"
    assert txt_files == [expected_name], f"Expected only {expected_name}, found {txt_files}"
    with open(os.path.join(OUTBOX, expected_name), "r") as f:
        content = f.read()
    assert content == expected_alert(hostname), f"Incorrect payload for {hostname}: {content!r}"


def test_final_state_and_behavior():
    # Preserve the original final-state assertions.
    assert os.path.isfile(SOURCE), "/home/user/nfs_monitor.cpp does not exist."
    assert os.path.isfile(SCRIPT), "/home/user/check_mounts.sh does not exist."
    with open(SCRIPT, "r") as f:
        script_content = f.read()
    assert "set -e" in script_content, f"{SCRIPT} does not contain 'set -e'."
    assert "g++" in script_content, f"{SCRIPT} does not contain 'g++'."

    with open(SOURCE, "r") as f:
        source_content = f.read()
    assert "getaddrinfo" in source_content, "The C++ source does not use getaddrinfo."

    assert os.path.isdir(OUTBOX), "/home/user/outbox/ directory does not exist."
    expected_files = [
        "alert_broken-server.invalid.txt",
        "alert_unreachable-node.localdomain.invalid.txt",
    ]
    txt_files = [f for f in os.listdir(OUTBOX) if f.endswith(".txt")]
    assert len(txt_files) == 2, f"Expected exactly 2 .txt files in outbox, found {len(txt_files)}: {txt_files}"
    for expected_file in expected_files:
        assert expected_file in txt_files, f"Expected file {expected_file} not found in outbox."
        hostname = expected_file.replace("alert_", "").replace(".txt", "")
        with open(os.path.join(OUTBOX, expected_file), "r") as f:
            content = f.read()
        assert content.strip() == expected_alert(hostname).strip(), f"Content of {expected_file} does not match expected output."

    # Compile the submitted source independently and exercise it with an
    # unpredictable hostname, proving the source itself implements the monitor.
    direct_host = f"audit-{uuid.uuid4().hex}.invalid"
    with tempfile.TemporaryDirectory() as td:
        direct_binary = os.path.join(td, "monitor")
        direct_fstab = os.path.join(td, "fstab")
        compile_result = subprocess.run(
            ["/usr/bin/g++", SOURCE, "-o", direct_binary],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"C++ source failed to compile: {compile_result.stderr}"
        with open(direct_fstab, "w") as f:
            f.write("# dynamically generated test\n\n")
            f.write("localhost:/ok /mnt/ok nfs defaults 0 0\n")
            f.write(f"{direct_host}:/bad /mnt/bad nfs defaults 0 0\n")
        reset_outbox()
        run_result = subprocess.run(
            [direct_binary, direct_fstab],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run_result.returncode == 0, f"Compiled monitor failed: {run_result.stderr}"
        assert_only_alert(direct_host)

    # The wrapper must explicitly fail with status 1 when custom_fstab is absent.
    saved_fstab = None
    if os.path.exists(FSTAB):
        with open(FSTAB, "rb") as f:
            saved_fstab = f.read()
        os.unlink(FSTAB)
    missing_result = subprocess.run(
        ["/bin/bash", SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert missing_result.returncode == 1, (
        f"Wrapper returned {missing_result.returncode}, not 1, when custom_fstab was absent"
    )

    # Execute the wrapper on another unpredictable input after removing any
    # prebuilt binary, proving that it creates and runs a compiled monitor.
    wrapper_host = f"wrapper-{uuid.uuid4().hex}.invalid"
    with open(FSTAB, "w") as f:
        f.write("# wrapper behavior test\n")
        f.write("127.0.0.1:/ok /mnt/ok nfs defaults 0 0\n")
        f.write(f"{wrapper_host}:/bad /mnt/bad nfs ro 0 0\n")
    reset_outbox()
    if os.path.lexists(BINARY):
        if os.path.isdir(BINARY) and not os.path.islink(BINARY):
            shutil.rmtree(BINARY)
        else:
            os.unlink(BINARY)
    wrapper_result = subprocess.run(
        ["/bin/bash", SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
    )
    assert wrapper_result.returncode == 0, f"Wrapper failed: {wrapper_result.stderr}"
    assert os.path.isfile(BINARY), "Wrapper did not create /home/user/nfs_monitor."
    assert os.access(BINARY, os.X_OK), "Compiled nfs_monitor is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Wrapper output is not a compiled ELF binary."
    assert_only_alert(wrapper_host)

    if saved_fstab is not None:
        with open(FSTAB, "wb") as f:
            f.write(saved_fstab)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
