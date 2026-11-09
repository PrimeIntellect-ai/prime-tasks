#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

REPORT_PATH = '/home/user/forensics_report.txt'
EXPECTED_PIN = '7492'


def test_forensics_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} is missing. Ensure you created it in the correct location."


def test_forensics_report_content():
    with open(REPORT_PATH, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"The report file should contain exactly 3 lines, but found {len(lines)}."

    expected_line1 = "sysstat"
    expected_line2 = "A9f8B1c03dE"
    expected_line3 = "7492"

    assert lines[0] == expected_line1, f"Line 1 is incorrect. Expected the tampered binary name '{expected_line1}', but got '{lines[0]}'."
    assert lines[1] == expected_line2, f"Line 2 is incorrect. Expected the session_id '{expected_line2}', but got '{lines[1]}'."
    assert lines[2] == expected_line3, f"Line 3 is incorrect. Expected the cracked PIN '{expected_line3}', but got '{lines[2]}'."


def discover_go_sources():
    by_directory = {}
    for root in ('/home/user', '/root', '/tmp'):
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in ('.cache', 'node_modules')]
            if '/go/pkg/mod/' in directory + '/':
                dirs[:] = []
                continue
            paths = []
            for name in files:
                path = os.path.join(directory, name)
                if name.endswith('.go') and os.path.isfile(path) and not os.path.islink(path):
                    paths.append(path)
            if paths:
                by_directory[directory] = sorted(paths)
    return by_directory


def source_text(paths):
    chunks = []
    for path in paths:
        try:
            with open(path, 'r', encoding='utf-8') as f:
                chunks.append(f.read())
        except (OSError, UnicodeError):
            return ''
    return '\n'.join(chunks)


def looks_like_bruteforcer(paths):
    source = source_text(paths)
    return ('crypto/md5' in source and
            re.search(r'\bfor\b', source) is not None and
            re.search(r'\bfunc\s+main\s*\(', source) is not None)


def test_go_bruteforce_program_exists_and_runs():
    attempts = []
    for directory, paths in discover_go_sources().items():
        attempts.append((directory, tuple(paths)))

        main_files = []
        helper_files = []
        for path in paths:
            text = source_text([path])
            if re.search(r'\bfunc\s+main\s*\(', text):
                main_files.append(path)
            else:
                helper_files.append(path)

        for main_file in main_files:
            attempts.append((directory, (main_file,)))
            if helper_files:
                attempts.append((directory, tuple([main_file] + helper_files)))

    seen = set()
    qualifying = 0
    diagnostics = []
    env = os.environ.copy()
    env['GO111MODULE'] = 'off'

    for directory, paths in attempts:
        key = tuple(paths)
        if key in seen or not looks_like_bruteforcer(paths):
            continue
        seen.add(key)
        qualifying += 1

        for cwd in dict.fromkeys((directory, '/home/user')):
            try:
                result = subprocess.run(
                    ['go', 'run', *paths],
                    cwd=cwd,
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                diagnostics.append(f"{paths}: {exc}")
                continue

            output = result.stdout + '\n' + result.stderr
            if result.returncode == 0 and re.search(r'(?<!\d)' + re.escape(EXPECTED_PIN) + r'(?!\d)', output):
                return
            diagnostics.append(f"{paths}: exit={result.returncode}, output={output[-300:]!r}")

    assert qualifying > 0, "No Go program containing an MD5 brute-force loop and a main function was found."
    assert False, "A Go brute-force program was found, but running it did not successfully produce the cracked PIN. " + '; '.join(diagnostics[-3:])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
