#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import builtins
import io
import os
import runpy
import shutil
import sys
import tarfile
import uuid


def test_original_final_state_and_extractor_behavior():
    # Preserve the original final-state assertions.
    file1 = '/home/user/docs/new_feature.md'
    file2 = '/home/user/docs/subdir/nested.md'

    assert os.path.isfile(file1), f"Expected file {file1} to be extracted."
    with open(file1, 'r') as f:
        assert f.read() == "valid 1\n", f"Content of {file1} is incorrect."

    assert os.path.isfile(file2), f"Expected file {file2} to be extracted."
    with open(file2, 'r') as f:
        assert f.read() == "valid 2\n", f"Content of {file2} is incorrect."

    malicious1 = '/home/user/docs_backup/overwrite.md'
    malicious2 = '/etc/passwd_fake'
    assert not os.path.exists(malicious1), f"Malicious file {malicious1} should not have been extracted."
    assert not os.path.exists(malicious2), f"Malicious file {malicious2} should not have been extracted."

    log_file = '/home/user/extraction_log.txt'
    assert os.path.isfile(log_file), f"Log file {log_file} is missing."
    expected_lines = [
        "EXTRACTED: /home/user/docs/new_feature.md\n",
        "EXTRACTED: /home/user/docs/subdir/nested.md\n",
        "REJECTED: ../docs_backup/overwrite.md\n",
        "REJECTED: /etc/passwd_fake\n"
    ]
    with open(log_file, 'r') as f:
        actual_lines = f.readlines()
    assert actual_lines == expected_lines, \
        f"Log file content does not match expected sorted output. Got: {actual_lines}"

    script = '/home/user/extract_docs.py'
    assert os.path.isfile(script), f"Required extractor script {script} is missing."

    # Replace the known archive with a fresh, unpredictable case so a fabricated
    # final state or hard-coded extractor cannot pass.
    token = uuid.uuid4().hex
    top_name = f'generated_{token}.md'
    nested_name = f'level_{token}/nested.md'
    traversal_name = f'../escape_{token}.txt'
    prefix_name = f'../docs_evil_{token}/pwn.txt'
    absolute_name = f'/tmp/absolute_{token}.txt'
    directory_name = f'ignored_directory_{token}'

    top_content = os.urandom(37)
    nested_content = os.urandom(53)
    archive = '/home/user/incoming/update.tar.gz'

    def add_file(tar, name, content):
        info = tarfile.TarInfo(name)
        info.size = len(content)
        tar.addfile(info, io.BytesIO(content))

    with tarfile.open(archive, 'w:gz') as tar:
        add_file(tar, top_name, top_content)
        add_file(tar, nested_name, nested_content)
        add_file(tar, traversal_name, b'traversal')
        add_file(tar, prefix_name, b'prefix-confusion')
        add_file(tar, absolute_name, b'absolute')
        directory = tarfile.TarInfo(directory_name)
        directory.type = tarfile.DIRTYPE
        tar.addfile(directory)

    docs = '/home/user/docs'
    shutil.rmtree(docs)
    os.makedirs(docs)
    os.unlink(log_file)

    escaped_path = f'/home/user/escape_{token}.txt'
    prefix_path = f'/home/user/docs_evil_{token}/pwn.txt'
    absolute_path = f'/tmp/absolute_{token}.txt'
    for path in (escaped_path, prefix_path, absolute_path):
        if os.path.isdir(path):
            shutil.rmtree(path)
        elif os.path.exists(path):
            os.unlink(path)

    top_target = os.path.join(docs, top_name)
    nested_target = os.path.join(docs, nested_name)
    final_targets = {os.path.abspath(top_target), os.path.abspath(nested_target)}
    rename_events = []
    direct_target_writes = []
    recording = {'enabled': False}

    def normalized_path(value):
        if isinstance(value, int):
            return None
        try:
            return os.path.abspath(os.fsdecode(value))
        except (TypeError, ValueError):
            return None

    def audit(event, args):
        if not recording['enabled']:
            return
        if event == 'os.rename' and len(args) >= 2:
            src = normalized_path(args[0])
            dst = normalized_path(args[1])
            if src is not None and dst is not None:
                rename_events.append((src, dst, os.path.exists(src)))
        elif event == 'open' and len(args) >= 3:
            path = normalized_path(args[0])
            mode = args[1]
            flags = args[2]
            writable = False
            if isinstance(mode, str):
                writable = any(char in mode for char in 'wax+')
            if isinstance(flags, int):
                writable = writable or bool(flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC))
            if writable and path in final_targets:
                direct_target_writes.append(path)

    sys.addaudithook(audit)
    old_argv = sys.argv[:]
    try:
        sys.argv = [script]
        recording['enabled'] = True
        try:
            runpy.run_path(script, run_name='__main__')
        except SystemExit as exc:
            assert exc.code in (None, 0), f"Extractor exited unsuccessfully: {exc.code}"
        finally:
            recording['enabled'] = False
    finally:
        sys.argv = old_argv

    assert os.path.isfile(top_target), f"Dynamic valid file {top_target} was not extracted."
    with open(top_target, 'rb') as f:
        assert f.read() == top_content, f"Content of {top_target} is incorrect."
    assert os.path.isfile(nested_target), f"Dynamic valid file {nested_target} was not extracted."
    with open(nested_target, 'rb') as f:
        assert f.read() == nested_content, f"Content of {nested_target} is incorrect."

    assert not os.path.exists(escaped_path), "Parent traversal member was extracted."
    assert not os.path.exists(prefix_path), "Sibling-prefix traversal member was extracted."
    assert not os.path.exists(absolute_path), "Absolute-path member was extracted."
    assert not os.path.exists(os.path.join(docs, directory_name)), \
        "Directory member was extracted directly."

    expected_dynamic_log = sorted([
        f"EXTRACTED: {top_target}",
        f"EXTRACTED: {nested_target}",
        f"REJECTED: {traversal_name}",
        f"REJECTED: {prefix_name}",
        f"REJECTED: {absolute_name}",
    ])
    assert os.path.isfile(log_file), "Extractor did not generate the log file."
    with open(log_file, 'r') as f:
        dynamic_lines = f.read().splitlines()
    assert dynamic_lines == expected_dynamic_log, \
        f"Dynamic log is missing entries, unsorted, or incorrect: {dynamic_lines}"

    assert not direct_target_writes, \
        f"Final targets were opened directly for writing instead of atomically replaced: {direct_target_writes}"
    for target in final_targets:
        matching = [event for event in rename_events if event[1] == target]
        assert matching, f"No atomic rename into final target {target} was observed."
        assert any(
            source_existed and src != target and
            os.path.dirname(src) == os.path.dirname(target)
            for src, _, source_existed in matching
        ), f"Target {target} was not renamed from an existing temporary file in the same directory."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
