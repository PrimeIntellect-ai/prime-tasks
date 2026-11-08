#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

UNPACKED_LOGS_DIR = '/home/user/unpacked_logs'
RESULTS_FILE = '/home/user/results.txt'
DEDUP_C = '/home/user/dedup.c'
DEDUP_BIN = '/home/user/dedup'


def test_results_file_contents():
    """Verify that results.txt contains the correct sorted list of filenames."""
    assert os.path.isfile(RESULTS_FILE), f"{RESULTS_FILE} does not exist."
    with open(RESULTS_FILE, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected = ['f1.log', 'f2.log', 'f3.log', 'f4.log', 'f5.log']
    assert lines == expected, f"Contents of {RESULTS_FILE} do not match expected output. Got: {lines}"


def test_symlinks_deleted():
    """Verify that symlinks have been deleted from the unpacked_logs directory."""
    sym1 = os.path.join(UNPACKED_LOGS_DIR, 'sym1.log')
    sym2 = os.path.join(UNPACKED_LOGS_DIR, 'sym2.log')
    assert not os.path.exists(sym1) and not os.path.islink(sym1), "sym1.log was not deleted."
    assert not os.path.exists(sym2) and not os.path.islink(sym2), "sym2.log was not deleted."


def test_hardlinks_created_correctly():
    """Verify that duplicate files have been hardlinked correctly."""
    f1 = os.path.join(UNPACKED_LOGS_DIR, 'f1.log')
    f2 = os.path.join(UNPACKED_LOGS_DIR, 'f2.log')
    f3 = os.path.join(UNPACKED_LOGS_DIR, 'f3.log')
    f4 = os.path.join(UNPACKED_LOGS_DIR, 'f4.log')
    f5 = os.path.join(UNPACKED_LOGS_DIR, 'f5.log')

    for f in [f1, f2, f3, f4, f5]:
        assert os.path.isfile(f), f"File {f} is missing."

    stat1 = os.stat(f1)
    stat2 = os.stat(f2)
    stat3 = os.stat(f3)
    stat4 = os.stat(f4)
    stat5 = os.stat(f5)

    assert stat1.st_ino == stat2.st_ino, "f1.log and f2.log should be hardlinked (same inode)."
    assert stat3.st_ino == stat5.st_ino, "f3.log and f5.log should be hardlinked (same inode)."
    assert stat4.st_ino != stat1.st_ino and stat4.st_ino != stat3.st_ino, "f4.log should not be hardlinked to the others."

    inodes = {stat1.st_ino, stat2.st_ino, stat3.st_ino, stat4.st_ino, stat5.st_ino}
    assert len(inodes) == 3, f"Expected exactly 3 unique inodes among the log files, found {len(inodes)}."


def test_file_contents_preserved():
    """Verify that the contents of the files are correct and were not altered."""
    f1 = os.path.join(UNPACKED_LOGS_DIR, 'f1.log')
    f3 = os.path.join(UNPACKED_LOGS_DIR, 'f3.log')
    f4 = os.path.join(UNPACKED_LOGS_DIR, 'f4.log')

    with open(f1, 'r') as f:
        assert f.read().strip() == "LOG_DATA_A_123", "Content of f1.log/f2.log is incorrect."
    with open(f3, 'r') as f:
        assert f.read().strip() == "LOG_DATA_B_456", "Content of f3.log/f5.log is incorrect."
    with open(f4, 'r') as f:
        assert f.read().strip() == "LOG_DATA_C_789", "Content of f4.log is incorrect."


def test_dedup_program_exists():
    """Verify that the dedup C source and executable exist."""
    assert os.path.isfile(DEDUP_C), f"{DEDUP_C} source file is missing."
    assert os.path.isfile(DEDUP_BIN), f"{DEDUP_BIN} executable is missing."
    assert os.access(DEDUP_BIN, os.X_OK), f"{DEDUP_BIN} is not executable."


def test_no_extra_files():
    """Verify that no corrupted files or extra unexpected files were extracted."""
    expected_files = {'f1.log', 'f2.log', 'f3.log', 'f4.log', 'f5.log'}
    actual_files = set(os.listdir(UNPACKED_LOGS_DIR))
    assert actual_files == expected_files, f"Unexpected files found in {UNPACKED_LOGS_DIR}: {actual_files - expected_files}"


def exercise_dedup(executable):
    """Run a dedup executable against unpredictable files and derive expectations from their contents."""
    with tempfile.TemporaryDirectory(prefix='dedup_verify_', dir='/home/user') as test_dir:
        token = secrets.token_hex(8)
        contents = [
            secrets.token_bytes(73),
            secrets.token_bytes(129),
            b'',
        ]
        groups = [
            [f'{token}_m.bin', f'{token}_a.bin', f'{token}_z.bin'],
            [f'{token}_q.bin', f'{token}_b.bin'],
            [f'{token}_empty2.bin', f'{token}_empty1.bin'],
        ]
        unique_name = f'{token}_unique.bin'
        expected_contents = {}

        for group, data in zip(groups, contents):
            for name in group:
                expected_contents[name] = data
                with open(os.path.join(test_dir, name), 'wb') as f:
                    f.write(data)

        unique_data = secrets.token_bytes(211)
        expected_contents[unique_name] = unique_data
        with open(os.path.join(test_dir, unique_name), 'wb') as f:
            f.write(unique_data)

        canonical_inodes = {
            min(group): os.stat(os.path.join(test_dir, min(group))).st_ino
            for group in groups
        }

        symlink_names = [f'{token}_link.bin', f'{token}_dangling.bin']
        os.symlink(groups[0][0], os.path.join(test_dir, symlink_names[0]))
        os.symlink('missing-target', os.path.join(test_dir, symlink_names[1]))

        result = subprocess.run(
            [executable, test_dir],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"{executable} failed on a test directory with exit code {result.returncode}: "
            f"{result.stderr}"
        )

        for name in symlink_names:
            path = os.path.join(test_dir, name)
            assert not os.path.lexists(path), f"Symbolic link {name} was not deleted."

        assert set(os.listdir(test_dir)) == set(expected_contents), (
            "The utility deleted, renamed, or created regular files unexpectedly."
        )

        for name, expected_data in expected_contents.items():
            path = os.path.join(test_dir, name)
            assert os.path.isfile(path) and not os.path.islink(path), f"{name} is not a regular file."
            with open(path, 'rb') as f:
                assert f.read() == expected_data, f"Contents of {name} were altered."

        group_inodes = []
        for group in groups:
            inode_set = {os.stat(os.path.join(test_dir, name)).st_ino for name in group}
            assert len(inode_set) == 1, f"Duplicate files in {group} were not hard-linked together."
            canonical = min(group)
            inode = next(iter(inode_set))
            assert inode == canonical_inodes[canonical], (
                f"The alphabetically first file {canonical} was not kept as the hard-link source."
            )
            group_inodes.append(inode)

        unique_inode = os.stat(os.path.join(test_dir, unique_name)).st_ino
        assert len(set(group_inodes + [unique_inode])) == len(group_inodes) + 1, (
            "Files with different contents were incorrectly hard-linked together."
        )


def test_submitted_executable_behavior():
    exercise_dedup(DEDUP_BIN)


def test_source_compiles_cleanly_and_behaves():
    with tempfile.TemporaryDirectory(prefix='dedup_build_', dir='/home/user') as build_dir:
        compiled = os.path.join(build_dir, 'dedup_from_source')
        result = subprocess.run(
            ['gcc', '-Wall', '-Wextra', DEDUP_C, '-o', compiled],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"dedup.c did not compile: {result.stderr}"
        assert not result.stderr.strip(), f"dedup.c produced compiler warnings: {result.stderr}"
        exercise_dedup(compiled)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
