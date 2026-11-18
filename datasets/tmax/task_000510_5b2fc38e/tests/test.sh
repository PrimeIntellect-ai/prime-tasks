#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import itertools
import re
import pytest


def get_expected_bypasses():
    # Generate all case permutations of "admin"
    perms = [''.join(p) for p in itertools.product(*zip('admin', 'ADMIN'))]
    # "admin" is already in the original config, so it should be blocked and not bypassed
    perms.remove('admin')
    return sorted(perms)


def test_bypasses_log():
    log_path = '/home/user/bypasses.log'
    assert os.path.exists(log_path), f"File not found: {log_path}"

    with open(log_path, 'r') as f:
        actual_lines = f.read().splitlines()

    expected_bypasses = get_expected_bypasses()
    assert actual_lines == expected_bypasses, (
        f"{log_path} does not contain the correct sorted bypassing permutations. "
        f"Expected {len(expected_bypasses)} items, got {len(actual_lines)}."
    )


def test_config_txt_orig():
    orig_path = '/home/user/config.txt.orig'
    assert os.path.exists(orig_path), f"Backup file not found: {orig_path}"

    with open(orig_path, 'r') as f:
        actual_lines = f.read().splitlines()

    expected_original = ['root', 'admin', 'superuser']
    assert actual_lines == expected_original, (
        f"{orig_path} does not contain the expected original configuration."
    )


def test_config_txt_updated():
    config_path = '/home/user/config.txt'
    assert os.path.exists(config_path), f"File not found: {config_path}"

    with open(config_path, 'r') as f:
        actual_lines = f.read().splitlines()

    expected_original = ['root', 'admin', 'superuser']
    assert actual_lines[:3] == expected_original, (
        f"The first 3 lines of {config_path} must remain the original configuration."
    )

    added_lines = actual_lines[3:]
    expected_bypasses = get_expected_bypasses()

    # The instructions say "Append all discovered bypassing permutations to /home/user/config.txt"
    # Verify that exactly the expected bypasses were added.
    assert sorted(added_lines) == sorted(expected_bypasses), (
        f"{config_path} does not have the correct bypassing permutations appended."
    )


def apply_unified_diff(patch_content, original_content):
    """Strictly parse and apply a single-file unified diff."""
    lines = patch_content.splitlines(keepends=True)
    assert len(lines) >= 3, "Patch is incomplete."
    assert lines[0].startswith('--- '), "Patch must begin with a unified-diff old-file header."
    assert lines[1].startswith('+++ '), "Patch must contain a unified-diff new-file header."

    source = original_content.splitlines(keepends=True)
    output = []
    source_pos = 0
    index = 2
    hunk_count = 0
    hunk_re = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?: .*)?$')

    while index < len(lines):
        header = lines[index].rstrip('\r\n')
        match = hunk_re.fullmatch(header)
        assert match is not None, f"Invalid unified-diff hunk header: {header!r}"
        hunk_count += 1
        index += 1

        old_start = int(match.group(1))
        old_count = int(match.group(2) or '1')
        new_start = int(match.group(3))
        new_count = int(match.group(4) or '1')
        old_target = old_start if old_count == 0 else old_start - 1
        new_target = new_start if new_count == 0 else new_start - 1

        assert source_pos <= old_target <= len(source), "Patch hunk has an invalid or overlapping old-file range."
        output.extend(source[source_pos:old_target])
        source_pos = old_target
        assert len(output) == new_target, "Patch hunk has an inconsistent new-file range."

        entries = []
        while index < len(lines) and not lines[index].startswith('@@ '):
            line = lines[index]
            assert line and line[0] in ' +-', f"Invalid unified-diff hunk line: {line!r}"
            marker = line[0]
            payload = line[1:]
            index += 1

            if index < len(lines) and lines[index].rstrip('\r\n') == '\\ No newline at end of file':
                if payload.endswith('\n'):
                    payload = payload[:-1]
                    if payload.endswith('\r'):
                        payload = payload[:-1]
                index += 1
            entries.append((marker, payload))

        consumed_old = 0
        produced_new = 0
        for marker, payload in entries:
            if marker in ' -':
                assert source_pos < len(source), "Patch consumes beyond the end of the original file."
                assert source[source_pos] == payload, "Patch context or removed text does not match the original file."
                source_pos += 1
                consumed_old += 1
            if marker in ' +':
                output.append(payload)
                produced_new += 1

        assert consumed_old == old_count, "Patch hunk old-line count is incorrect."
        assert produced_new == new_count, "Patch hunk new-line count is incorrect."

    assert hunk_count > 0, "Patch contains no unified-diff hunks."
    output.extend(source[source_pos:])
    return ''.join(output)


def test_config_patch():
    patch_path = '/home/user/config.patch'
    assert os.path.exists(patch_path), f"Patch file not found: {patch_path}"

    with open(patch_path, 'r') as f:
        patch_content = f.read()

    # Keep the original unified-diff and filename assertions.
    assert "---" in patch_content and "+++" in patch_content, (
        f"{patch_path} does not appear to be a unified diff."
    )

    assert "/home/user/config.txt.orig" in patch_content or "config.txt.orig" in patch_content, (
        f"{patch_path} does not reference the original file config.txt.orig."
    )

    assert "/home/user/config.txt" in patch_content or "config.txt" in patch_content, (
        f"{patch_path} does not reference the modified file config.txt."
    )

    expected_bypasses = get_expected_bypasses()
    patch_lines = patch_content.splitlines()
    added_in_patch = [
        line[1:] for line in patch_lines
        if line.startswith('+') and not line.startswith('+++')
    ]

    for p in expected_bypasses:
        assert p in added_in_patch, f"Patch is missing the addition of bypass: {p}"

    # Ensure this is a structurally valid unified diff that really transforms
    # the required backup into the submitted updated configuration.
    with open('/home/user/config.txt.orig', 'r') as f:
        original_content = f.read()
    with open('/home/user/config.txt', 'r') as f:
        updated_content = f.read()

    applied_content = apply_unified_diff(patch_content, original_content)
    assert applied_content == updated_content, (
        f"{patch_path} does not apply to config.txt.orig to produce config.txt."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
