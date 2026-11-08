#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import socket
import stat
import subprocess
import time


def test_init_mount_script():
    script_path = "/home/user/init_mount.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    # Start from an absent mount directory so a no-op script cannot pass using
    # state created independently of the script.
    mount_path = "/home/user/mock_mount"
    if os.path.lexists(mount_path):
        if os.path.islink(mount_path) or not os.path.isdir(mount_path):
            os.unlink(mount_path)
        else:
            shutil.rmtree(mount_path)

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Run 1 of {script_path} failed with exit code {result.returncode}. stderr: {result.stderr}"

    data_file = "/home/user/mock_mount/data.bin"
    assert os.path.isdir(mount_path), f"Directory {mount_path} does not exist."
    assert os.path.isfile(data_file), f"Data file {data_file} does not exist."
    assert os.path.getsize(data_file) == 4096, f"Data file {data_file} is not exactly 4096 bytes."
    with open(data_file, "rb") as f:
        data = f.read()
    assert data == b"\0" * 4096, f"Data file {data_file} is not filled with zero bytes."

    before = os.stat(data_file)
    before_hash = hashlib.sha256(data).digest()
    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Run 2 of {script_path} failed with exit code {result.returncode}. stderr: {result.stderr}"

    after = os.stat(data_file)
    with open(data_file, "rb") as f:
        after_data = f.read()
    assert os.path.getsize(data_file) == 4096, f"Data file {data_file} is not exactly 4096 bytes after the second run."
    assert hashlib.sha256(after_data).digest() == before_hash, "The second run changed data.bin contents."
    assert after.st_ino == before.st_ino, "The second run replaced an already-correct data.bin."
    assert after.st_mtime_ns == before.st_mtime_ns, "The second run modified an already-correct data.bin."


def test_custom_fstab():
    fstab_path = "/home/user/custom_fstab"
    assert os.path.exists(fstab_path), f"File {fstab_path} does not exist."

    with open(fstab_path, "r") as f:
        content = f.read().strip()

    expected_content = "/dev/loop0 /home/user/mock_mount ext4 defaults 0 0"
    assert content == expected_content, f"Content of {fstab_path} is incorrect. Expected '{expected_content}', got '{content}'."


def test_systemd_service():
    service_path = "/home/user/capacity-exporter.service"
    assert os.path.exists(service_path), f"Service file {service_path} does not exist."

    with open(service_path, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert "ExecStart=/home/user/capacity_monitor/target/release/capacity_monitor" in content, "ExecStart directive is missing or incorrect."
    assert "WantedBy=default.target" in content, "WantedBy directive is missing or incorrect."
    assert "network-online.target" in content and "mount-prep.service" in content, "After directive does not contain required targets."
    lines = content.split('\n')
    after_lines = [line for line in lines if line.strip().startswith("After=")]
    assert after_lines, "No After= directive found."
    combined_after = " ".join(after_lines)
    assert "network-online.target" in combined_after, "network-online.target missing from After="
    assert "mount-prep.service" in combined_after, "mount-prep.service missing from After="

    # Validate that each directive is in the section required by systemd.
    sections = {}
    current = None
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1].strip()
            sections.setdefault(current, [])
        elif current is not None:
            sections[current].append(line)

    assert "Unit" in sections, "[Unit] section is missing."
    assert "Service" in sections, "[Service] section is missing."
    assert "Install" in sections, "[Install] section is missing."
    assert "ExecStart=/home/user/capacity_monitor/target/release/capacity_monitor" in sections["Service"], "ExecStart must be in [Service]."
    assert "WantedBy=default.target" in sections["Install"], "WantedBy must be in [Install]."
    unit_after = [line.split("=", 1)[1].split() for line in sections["Unit"] if line.startswith("After=")]
    unit_targets = {target for values in unit_after for target in values}
    assert "network-online.target" in unit_targets, "network-online.target must appear in an After= directive in [Unit]."
    assert "mount-prep.service" in unit_targets, "mount-prep.service must appear in an After= directive in [Unit]."


def receive_metric():
    with socket.create_connection(("127.0.0.1", 9090), timeout=2) as sock:
        sock.settimeout(2)
        chunks = []
        while True:
            chunk = sock.recv(1024)
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks).decode("utf-8")


def direct_file_total(path):
    return sum(entry.stat(follow_symlinks=False).st_size for entry in os.scandir(path) if entry.is_file(follow_symlinks=False))


def test_rust_exporter():
    cargo_dir = "/home/user/capacity_monitor"
    assert os.path.exists(os.path.join(cargo_dir, "Cargo.toml")), "Cargo.toml does not exist in the expected directory."

    build_result = subprocess.run(["cargo", "build", "--release"], cwd=cargo_dir, capture_output=True, text=True)
    assert build_result.returncode == 0, f"Cargo build failed. stderr: {build_result.stderr}"

    binary_path = os.path.join(cargo_dir, "target/release/capacity_monitor")
    assert os.path.exists(binary_path), f"Compiled binary not found at {binary_path}."
    assert os.path.isfile(binary_path), f"Compiled artifact at {binary_path} is not a regular file."
    assert os.access(binary_path, os.X_OK), f"Compiled binary at {binary_path} is not executable."

    process = subprocess.Popen([binary_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(0.5)
        assert process.poll() is None, "Exporter exited before serving requests (possibly because it failed to bind port 9090)."

        # Preserve the original fixed-state assertion.
        data = receive_metric()
        assert data == "BYTES:4096\n", f"Expected 'BYTES:4096\\n', got '{data}'"

        mount_path = "/home/user/mock_mount"
        first_name = "probe_" + secrets.token_hex(8) + ".bin"
        second_name = "probe_" + secrets.token_hex(8) + ".bin"
        nested_dir = os.path.join(mount_path, "nested_" + secrets.token_hex(8))
        first_size = secrets.randbelow(1500) + 101
        second_size = secrets.randbelow(1700) + 2001

        with open(os.path.join(mount_path, first_name), "wb") as f:
            f.write(os.urandom(first_size))
        os.mkdir(nested_dir)
        with open(os.path.join(nested_dir, "ignored.bin"), "wb") as f:
            f.write(os.urandom(3000 + secrets.randbelow(1000)))

        expected = direct_file_total(mount_path)
        data = receive_metric()
        assert data == f"BYTES:{expected}\n", f"Exporter did not calculate the first dynamic directory state: got '{data}', expected 'BYTES:{expected}\\n'."

        # Change existing sizes and add another direct file. The same process
        # must recalculate the value for a further sequential connection.
        new_data_size = secrets.randbelow(700) + 17
        with open(os.path.join(mount_path, "data.bin"), "wb") as f:
            f.write(os.urandom(new_data_size))
        with open(os.path.join(mount_path, first_name), "ab") as f:
            f.write(os.urandom(53 + secrets.randbelow(400)))
        with open(os.path.join(mount_path, second_name), "wb") as f:
            f.write(os.urandom(second_size))

        expected = direct_file_total(mount_path)
        data = receive_metric()
        assert data == f"BYTES:{expected}\n", f"Exporter did not recalculate the changed directory state: got '{data}', expected 'BYTES:{expected}\\n'."
        assert process.poll() is None, "Exporter did not remain running for multiple sequential requests."
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
