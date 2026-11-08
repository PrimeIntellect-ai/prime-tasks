#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import uuid
import pytest

PROCESS_ENTRY = "/app/vendored/bash-log-utils-1.4.0/process_entry.sh"
SANITIZER = "/home/user/sanitize.sh"


def run_with_timeout(command, **kwargs):
    try:
        return subprocess.run(command, timeout=5, **kwargs)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {command}")


def test_vendored_package_fixed():
    assert os.path.isfile(PROCESS_ENTRY), f"Missing vendored process_entry.sh at {PROCESS_ENTRY}"

    # Retain the original standard-input assertion.
    result = run_with_timeout(
        [PROCESS_ENTRY, "standard log entry"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"process_entry.sh failed with exit code {result.returncode}. Stderr: {result.stderr}"
    )

    # Exercise the former recursive branch with long argv and stdin inputs.
    long_line = "X" * 8192
    result = run_with_timeout(
        [PROCESS_ENTRY, long_line],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"process_entry.sh failed on a long argument with exit code {result.returncode}. "
        f"Stderr: {result.stderr}"
    )

    result = run_with_timeout(
        [PROCESS_ENTRY],
        input=long_line + "\n",
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"process_entry.sh failed on long stdin with exit code {result.returncode}. "
        f"Stderr: {result.stderr}"
    )


def test_recovered_logs():
    recovered_log_path = "/home/user/crash_evidence.log"
    assert os.path.isfile(recovered_log_path), f"Missing recovered log at {recovered_log_path}"

    inode_table_path = "/tmp/fs_recovery_img/inode_table.txt"
    blocks_dir = "/tmp/fs_recovery_img/blocks"

    # Parse the named inode entry and concatenate its listed block pointers.
    expected_content = []
    found_inode = False
    with open(inode_table_path, "r") as inode_file:
        for raw_line in inode_file:
            filename, separator, pointers = raw_line.partition(":")
            if not separator or filename.strip() != "crash_evidence.log":
                continue
            found_inode = True
            for block_name in pointers.split():
                block_path = os.path.join(blocks_dir, block_name)
                assert os.path.isfile(block_path), f"Missing referenced recovery block: {block_name}"
                with open(block_path, "r") as block_file:
                    expected_content.append(block_file.read())

    assert found_inode, "inode_table.txt has no crash_evidence.log entry"
    expected_text = "".join(expected_content)

    with open(recovered_log_path, "r") as recovered_file:
        actual_text = recovered_file.read()

    assert actual_text == expected_text, (
        "Recovered crash_evidence.log content does not match the reconstructed blocks."
    )


def test_sanitizer_filter():
    assert os.path.isfile(SANITIZER), f"Missing sanitize.sh at {SANITIZER}"
    assert os.access(SANITIZER, os.X_OK), "sanitize.sh is not executable"

    clean_corpus_dir = "/app/corpora/clean"
    evil_corpus_dir = "/app/corpora/evil"

    clean_files = [
        name for name in os.listdir(clean_corpus_dir)
        if os.path.isfile(os.path.join(clean_corpus_dir, name))
    ]
    evil_files = [
        name for name in os.listdir(evil_corpus_dir)
        if os.path.isfile(os.path.join(evil_corpus_dir, name))
    ]

    clean_modified = []
    evil_bypassed = []

    # Retain the original clean-corpus checks.
    for filename in clean_files:
        filepath = os.path.join(clean_corpus_dir, filename)
        with open(filepath, "r") as corpus_file:
            original_content = corpus_file.read()

        try:
            result = subprocess.run(
                [SANITIZER],
                input=original_content,
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode != 0 or result.stdout != original_content:
                clean_modified.append(filename)
        except subprocess.TimeoutExpired:
            clean_modified.append(filename)

    # Retain the original evil-corpus checks and require the mandated zero exit.
    for filename in evil_files:
        filepath = os.path.join(evil_corpus_dir, filename)
        with open(filepath, "r") as corpus_file:
            evil_content = corpus_file.read()

        try:
            result = subprocess.run(
                [SANITIZER],
                input=evil_content,
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode != 0 or result.stdout.strip() != "":
                evil_bypassed.append(filename)
        except subprocess.TimeoutExpired:
            evil_bypassed.append(filename)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
            f"{', '.join(evil_bypassed[:5])}"
        )
    if clean_modified:
        error_msgs.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified: "
            f"{', '.join(clean_modified[:5])}"
        )
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))

    # Exercise long and mixed generated inputs rather than only the fixed corpus.
    marker = uuid.uuid4().hex
    long_clean = f"generated-clean-{marker}-" + ("Z" * 8192)
    hex_payload = "a1" * 26  # 52 consecutive hexadecimal characters
    mixed_input = (
        long_clean + "\n"
        + f"drop-{marker}-0xNaN\n"
        + f"keep-{marker}\n"
        + f"drop-{marker}-infinity_loop_ptr\n"
        + f"drop-{marker}-{hex_payload}\n"
    )
    expected_output = long_clean + "\n" + f"keep-{marker}\n"
    result = run_with_timeout(
        [SANITIZER],
        input=mixed_input,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"sanitize.sh exited with {result.returncode}: {result.stderr}"
    assert result.stdout == expected_output, "sanitize.sh mishandled generated long or mixed input"


def test_sanitizer_invokes_process_entry():
    assert os.path.isfile(SANITIZER), f"Missing sanitize.sh at {SANITIZER}"
    assert os.path.isfile(PROCESS_ENTRY), f"Missing vendored process_entry.sh at {PROCESS_ENTRY}"

    backup_fd, backup_path = tempfile.mkstemp(prefix="process_entry_backup_", dir="/tmp")
    os.close(backup_fd)
    record_path = f"/tmp/process_entry_called_{uuid.uuid4().hex}"
    shutil.copy2(PROCESS_ENTRY, backup_path)

    try:
        with open(PROCESS_ENTRY, "w") as wrapper:
            wrapper.write(
                "#!/bin/bash\n"
                f"printf 'called\\n' >> {record_path!r}\n"
                "exit 0\n"
            )
        os.chmod(PROCESS_ENTRY, 0o755)

        probe = f"instrumented clean log {uuid.uuid4().hex}\n"
        result = run_with_timeout(
            [SANITIZER],
            input=probe,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"sanitize.sh exited with {result.returncode}: {result.stderr}"
        assert result.stdout == probe, "sanitize.sh modified a clean probe line"
        assert os.path.isfile(record_path) and os.path.getsize(record_path) > 0, (
            "sanitize.sh did not invoke the vendored process_entry.sh"
        )
    finally:
        shutil.copy2(backup_path, PROCESS_ENTRY)
        os.unlink(backup_path)
        if os.path.exists(record_path):
            os.unlink(record_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
