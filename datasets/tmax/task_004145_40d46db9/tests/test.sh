#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import select
import shlex
import signal
import subprocess
import tempfile
import time
import uuid


def _perm_bits(perms):
    return {c for c in perms if c != "-"}


def test_directory_setup_and_acls():
    """Verify the directory and all relevant default ACL restrictions."""
    dir_path = "/home/user/secure_zone"
    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."

    result = subprocess.run(["getfacl", dir_path], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run getfacl."
    assert "default:mask::r-x" in result.stdout, f"Default mask is not r-x for {dir_path}."

    mask_match = re.search(r"^default:mask::([rwx-]{3})$", result.stdout, re.MULTILINE)
    other_match = re.search(r"^default:other::([rwx-]{3})$", result.stdout, re.MULTILINE)
    group_matches = re.findall(r"^default:group:[^:]*:([rwx-]{3})(?:\s+#effective:([rwx-]{3}))?$", result.stdout, re.MULTILINE)

    assert mask_match, "Default ACL mask entry is missing."
    assert other_match, "Default ACL other entry is missing."
    assert group_matches, "Default ACL group entry is missing."

    mask = _perm_bits(mask_match.group(1))
    assert mask == {"r", "x"}, "Default ACL mask must grant read and execute, but not write."
    assert _perm_bits(other_match.group(1)) == {"r", "x"}, "Default other permissions must be exactly r-x."

    for raw_perms, reported_effective in group_matches:
        effective = _perm_bits(reported_effective) if reported_effective else (_perm_bits(raw_perms) & mask)
        assert effective == {"r", "x"}, "Every default group entry must have effective permissions r-x."


def _running_installed_monitors(prog_path, log_path):
    matches = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        exe = f"/proc/{name}/exe"
        stdout_fd = f"/proc/{name}/fd/1"
        try:
            if os.path.samefile(exe, prog_path) and os.path.samefile(stdout_fd, log_path):
                matches.append(int(name))
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return matches


def _inotify_masks(pid):
    masks = []
    fd_dir = f"/proc/{pid}/fd"
    try:
        fds = os.listdir(fd_dir)
    except FileNotFoundError:
        return masks
    for fd in fds:
        path = os.path.join(fd_dir, fd)
        try:
            if os.readlink(path) != "anon_inode:inotify":
                continue
            with open(f"/proc/{pid}/fdinfo/{fd}", "r") as info:
                for line in info:
                    match = re.search(r"\binotify\s+wd:[^\n]*\bmask:([0-9a-fA-F]+)\b", line)
                    if match:
                        masks.append(int(match.group(1), 16))
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return masks


def test_c_program_presence_and_execution():
    """Verify the installed ELF is running and that the submitted C source uses an IN_CREATE watch."""
    source_path = "/home/user/fs_monitor.c"
    prog_path = "/home/user/fs_monitor"
    log_path = "/home/user/events.log"
    dir_path = "/home/user/secure_zone"

    assert os.path.isfile(source_path), f"C source {source_path} does not exist."
    assert os.path.isfile(prog_path), f"Compiled program {prog_path} does not exist."
    assert os.access(prog_path, os.X_OK), f"Program {prog_path} is not executable."
    with open(prog_path, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", f"Program {prog_path} is not an ELF executable."

    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Is the monitor running?"
    running = _running_installed_monitors(prog_path, log_path)
    assert running, "No running instance of /home/user/fs_monitor has stdout redirected to events.log."

    # Preserve the original live-monitor test, but require the alert to be a complete line.
    unique_filename = f"test_alert_{uuid.uuid4().hex}.txt"
    test_file_path = os.path.join(dir_path, unique_filename)
    start_offset = os.path.getsize(log_path)
    try:
        with open(test_file_path, "w") as f:
            f.write("test")
        time.sleep(1.5)
        with open(log_path, "r") as f:
            f.seek(start_offset)
            new_log_content = f.read()
        expected_log = f"ALERT: New file {unique_filename} detected"
        assert expected_log in new_log_content, f"Expected log '{expected_log}' not found in {log_path}."
        assert expected_log in new_log_content.splitlines(), "The monitor alert was not emitted in the exact required line format."
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)

    # Compile and directly exercise the submitted source, rather than trusting another process.
    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt = os.path.join(temp_dir, "fs_monitor_from_source")
        build = subprocess.run(["gcc", source_path, "-o", rebuilt], capture_output=True, text=True)
        assert build.returncode == 0, f"fs_monitor.c does not compile with gcc: {build.stderr}"

        proc = subprocess.Popen([rebuilt], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        source_test_name = f"source_test_{uuid.uuid4().hex}.txt"
        source_test_path = os.path.join(dir_path, source_test_name)
        try:
            masks = []
            deadline = time.time() + 3
            while time.time() < deadline and proc.poll() is None:
                masks = _inotify_masks(proc.pid)
                if masks:
                    break
                time.sleep(0.05)
            assert proc.poll() is None, "The monitor compiled from fs_monitor.c exited before monitoring."
            assert masks, "The monitor compiled from fs_monitor.c did not create an inotify watch."
            assert 0x100 in masks, "The inotify watch is not configured specifically with the IN_CREATE mask."

            with open(source_test_path, "w") as f:
                f.write("source test")

            expected = f"ALERT: New file {source_test_name} detected"
            lines = []
            deadline = time.time() + 2
            while time.time() < deadline:
                ready, _, _ = select.select([proc.stdout], [], [], 0.2)
                if ready:
                    line = proc.stdout.readline()
                    if line:
                        lines.append(line.rstrip("\n"))
                        if lines[-1] == expected:
                            break
            assert expected in lines, "The executable built from fs_monitor.c did not emit the exact required alert."
        finally:
            if os.path.exists(source_test_path):
                os.remove(source_test_path)
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2)


def test_log_parsing_pipeline():
    """Verify the shell/text-processing pipeline outputs filenames and nothing else."""
    script_path = "/home/user/process_alerts.sh"
    output_path = "/home/user/processed_files.txt"
    log_path = "/home/user/events.log"

    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    with open(script_path, "r") as f:
        script_content = f.read()
    assert re.match(r"^#!.*(?:sh|bash)\b", script_content), "process_alerts.sh is not a shell script."
    assert re.search(r"\b(?:grep|awk|sed)\b", script_content), "The parsing script does not use grep, awk, or sed."

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script {script_path} failed to execute."
    assert os.path.isfile(output_path), f"Output file {output_path} was not created."

    dummy_file = f"dummy_{uuid.uuid4().hex}.txt"
    spaced_file = f"report {uuid.uuid4().hex}.txt"
    with open(log_path, "w") as f:
        f.write("unrelated log text\n")
        f.write(f"ALERT: New file {dummy_file} detected\n")
        f.write(f"ALERT: New file {spaced_file} detected\n")
        f.write("prefix ALERT: New file wrong.txt detected\n")
        f.write("ALERT: New file also-wrong.txt detected trailing text\n")

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script {script_path} failed to execute."
    with open(output_path, "r") as f:
        processed_content = f.read()

    assert dummy_file in processed_content, f"Filename {dummy_file} was not extracted to {output_path}."
    assert processed_content.splitlines() == [dummy_file, spaced_file], \
        "processed_files.txt must contain only the filenames from valid alert lines, one per line."


def test_ssh_tunnel_configuration():
    """Verify start_tunnel.sh contains one semantically exact SSH command."""
    script_path = "/home/user/start_tunnel.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    # Retain the original token assertions.
    assert re.search(r"ssh\s+", content), "No ssh command found in the script."
    assert re.search(r"-L\s+8888:127\.0\.0\.1:9999", content), "Port forwarding is not correctly configured."
    assert "-N" in content.split(), "Missing -N flag for no command execution."
    assert "-f" in content.split(), "Missing -f flag to run in background."
    assert "monitor-server" in content, "Missing monitor-server alias in the ssh command."

    valid_command = False
    for line in content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        try:
            words = shlex.split(stripped, comments=True)
        except ValueError:
            continue
        if not words or words[0] != "ssh":
            continue
        remaining = words[1:]
        required = ["-f", "-N", "-L", "8888:127.0.0.1:9999", "monitor-server"]
        if len(remaining) == len(required) and sorted(remaining) == sorted(required):
            l_index = remaining.index("-L")
            if l_index + 1 < len(remaining) and remaining[l_index + 1] == "8888:127.0.0.1:9999" and remaining[-1] == "monitor-server":
                valid_command = True
                break
    assert valid_command, "No exact 'ssh -f -N -L 8888:127.0.0.1:9999 monitor-server' command was found."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
