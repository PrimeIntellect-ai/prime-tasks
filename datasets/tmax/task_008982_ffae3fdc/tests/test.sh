#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_ci_tool.py
import os
import secrets
import subprocess
import tarfile
from pathlib import Path

SCRIPT = Path('/home/user/ci_tool.sh')
PROJECT = Path('/home/user/project')
SRC = PROJECT / 'src' / 'main.rs'
X86_LOG = PROJECT / 'build_x86.log'
ARM_LOG = PROJECT / 'build_arm.log'
REPORT = PROJECT / 'ci_report.log'
ARCHIVE = PROJECT / 'src_archive.tar.gz'


def write_inputs(source, x86_log, arm_log):
    (PROJECT / 'src').mkdir(parents=True, exist_ok=True)
    SRC.write_text(source)
    X86_LOG.write_text(x86_log)
    ARM_LOG.write_text(arm_log)
    REPORT.unlink(missing_ok=True)
    ARCHIVE.unlink(missing_ok=True)


def run_tool():
    result = subprocess.run(
        [str(SCRIPT)], cwd=str(PROJECT), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, (
        f'ci_tool.sh exited with {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def assert_archive_contains_current_source():
    assert ARCHIVE.is_file(), f'The tarball {ARCHIVE} does not exist.'
    assert tarfile.is_tarfile(ARCHIVE), f'The file {ARCHIVE} is not a valid tar archive.'
    expected = SRC.read_bytes()
    with tarfile.open(ARCHIVE, 'r:gz') as tar:
        names = tar.getnames()
        assert any(name.endswith('main.rs') for name in names), 'The tarball does not contain main.rs.'
        matching = [m for m in tar.getmembers() if m.isfile() and m.name.endswith('main.rs')]
        assert matching, 'The tarball does not contain a regular main.rs file.'
        assert any(tar.extractfile(m).read() == expected for m in matching), (
            'The archived main.rs is not the current generated source.'
        )


def rust_error_log(move_line):
    first_line = move_line - 1
    borrow_line = move_line + 1
    return f'''error[E0382]: borrow of moved value: `s1`
 --> src/main.rs:{borrow_line}:28
  |
{first_line} |     let s1 = String::from("hello");
  |         -- move occurs because `s1` has type `String`, which does not implement the `Copy` trait
{move_line} |     let s2 = s1;
  |              -- value moved here
{borrow_line} |     println!("{{}}, world!", s1);
  |                            ^^ value borrowed here after move
'''


def test_ci_tool_end_to_end_and_dynamic_behavior():
    # Preserve the original executable assertion.
    assert SCRIPT.is_file(), f'The script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'The script {SCRIPT} is not executable.'

    # Execute against the task's original inputs and preserve all original final-state checks.
    baseline_source = '''fn main() {
    let s1 = String::from("hello");
    let s2 = s1;
    println!("{}, world!", s1);
}
'''
    baseline_log = rust_error_log(3)
    write_inputs(baseline_source, baseline_log, baseline_log)
    run_tool()

    assert SRC.is_file(), f'The file {SRC} does not exist.'
    lines = SRC.read_text().splitlines(keepends=True)
    assert len(lines) >= 3, 'main.rs does not have enough lines.'
    assert 'let s2 = s1.clone();' in lines[2], 'Line 3 of main.rs was not correctly patched with .clone();'

    assert REPORT.is_file(), f'The report file {REPORT} does not exist.'
    content = REPORT.read_text().strip()
    expected_lines = [
        '[x86] Status: FAILED_BUT_FIXED',
        '[arm] Status: FAILED_BUT_FIXED',
        'Patched line: 3',
    ]
    for expected_line in expected_lines:
        assert expected_line in content, f"Expected '{expected_line}' in ci_report.log, but it was missing or incorrect."
    assert content.splitlines() == expected_lines, 'ci_report.log does not have the exact required format.'
    assert_archive_contains_current_source()

    # Vary the move line and which architecture failed, so the line and statuses
    # must be derived from the current logs rather than hardcoded.
    padding_count = secrets.randbelow(5) + 1
    padding = ''.join(f'    // padding {i}\n' for i in range(padding_count))
    move_line = 3 + padding_count
    dynamic_source = (
        'fn main() {\n' + padding +
        '    let s1 = String::from("hello");\n'
        '    let s2 = s1;\n'
        '    println!("{}, world!", s1);\n'
        '}\n'
    )
    error_log = rust_error_log(move_line)
    success_log = 'Finished release [optimized] target(s) in 0.01s\n'
    failed_arch = secrets.choice(('x86', 'arm'))
    if failed_arch == 'x86':
        x86_log, arm_log = error_log, success_log
        expected_report = [
            '[x86] Status: FAILED_BUT_FIXED',
            '[arm] Status: SUCCESS',
            f'Patched line: {move_line}',
        ]
    else:
        x86_log, arm_log = success_log, error_log
        expected_report = [
            '[x86] Status: SUCCESS',
            '[arm] Status: FAILED_BUT_FIXED',
            f'Patched line: {move_line}',
        ]

    write_inputs(dynamic_source, x86_log, arm_log)
    run_tool()
    dynamic_lines = SRC.read_text().splitlines()
    assert dynamic_lines[move_line - 1].strip() == 'let s2 = s1.clone();', (
        f'The dynamically reported move on line {move_line} was not patched.'
    )
    assert REPORT.read_text().strip().splitlines() == expected_report
    assert_archive_contains_current_source()

    # With no E0382 in either log, source must remain unchanged and NONE must be reported.
    clean_source = '''fn main() {
    println!("clean build");
}
'''
    write_inputs(clean_source, success_log, success_log)
    run_tool()
    assert SRC.read_text() == clean_source, 'main.rs was modified even though neither log contained E0382.'
    assert REPORT.read_text().strip().splitlines() == [
        '[x86] Status: SUCCESS',
        '[arm] Status: SUCCESS',
        'Patched line: NONE',
    ]
    assert_archive_contains_current_source()
TEST_EOF

if python3 -m pytest /tmp/test_ci_tool.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
