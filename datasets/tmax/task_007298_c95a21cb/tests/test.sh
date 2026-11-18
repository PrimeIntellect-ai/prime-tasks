#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess
from pathlib import Path

REPO = Path('/home/user/suspicious_crypto')
BAD_HASH_FILE = Path('/home/user/bad_commit_hash.txt')
FLAG_FILE = Path('/home/user/decrypted_flag.txt')


def git(*args, text=True):
    return subprocess.run(
        ['git', *args], cwd=REPO, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=text
    ).stdout


def show_file(commit, path):
    proc = subprocess.run(
        ['git', 'show', f'{commit}:{path}'], cwd=REPO,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    return proc.stdout if proc.returncode == 0 else None


def has_malicious_trap(data):
    if data is None:
        return False
    text = data.decode('utf-8', errors='replace')
    return bool(re.search(r'state\s*==\s*370', text) and
                re.search(r'state\s*=\s*370\s*;', text))


def find_original_commits():
    commits = git('rev-list', '--all').splitlines()
    assert commits, 'Repository has no reachable commits.'

    bad_candidates = []
    baseline_candidates = []
    for commit in commits:
        parents = git('show', '-s', '--format=%P', commit).strip().split()
        current_crypto = show_file(commit, 'crypto_utils.c')
        parent_crypto = show_file(parents[0], 'crypto_utils.c') if parents else None
        if has_malicious_trap(current_crypto) and not has_malicious_trap(parent_crypto):
            bad_candidates.append(commit)

        subject = git('show', '-s', '--format=%s', commit).strip()
        header = show_file(commit, 'crypto_utils.h') or b''
        parent_header = show_file(parents[0], 'crypto_utils.h') if parents else b''
        if (subject == 'Add global key configuration' and
                b'int global_key = 42' in header and
                b'int global_key = 42' not in (parent_header or b'')):
            baseline_candidates.append(commit)

    assert len(bad_candidates) == 1, 'Could not uniquely identify the original regression commit.'
    assert len(baseline_candidates) == 1, 'Could not uniquely identify the original repository tip.'
    return bad_candidates[0], baseline_candidates[0]


def run_analyzer(value):
    try:
        proc = subprocess.run(
            [str(REPO / 'crypto_analyzer'), str(value)], cwd=REPO,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=2
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f'crypto_analyzer did not terminate for payload {value}') from exc
    assert proc.returncode == 0, (
        f'crypto_analyzer failed for payload {value}: '
        f'{proc.stderr.decode(errors="replace")}'
    )
    assert proc.stdout == b'Result: 1\n', (
        f'Unexpected output for payload {value}: {proc.stdout!r}'
    )
    return proc.stdout


def terminates_like_original(value):
    state = value & 0xffffffff
    seen = set()
    for _ in range(10000):
        if state == 1:
            return True
        if state in seen:
            return False
        seen.add(state)
        if state % 2 == 0:
            state //= 2
        else:
            state = (3 * state + 1) & 0xffffffff
    return False


def main():
    assert REPO.is_dir(), f'Missing repository: {REPO}'
    expected_bad, original_tip = find_original_commits()

    # Preserve the original exact bad-commit assertion, deriving the answer from history.
    assert BAD_HASH_FILE.is_file(), f'Missing {BAD_HASH_FILE}'
    actual_bad = BAD_HASH_FILE.read_text().strip()
    assert re.fullmatch(r'[0-9a-f]{40}', actual_bad), 'Bad commit hash must be a full 40-character hash.'
    assert actual_bad == expected_bad, f'Expected bad commit {expected_bad}, got {actual_bad}.'

    # The worktree must still be based on the supplied latest revision.
    ancestry = subprocess.run(
        ['git', 'merge-base', '--is-ancestor', original_tip, 'HEAD'], cwd=REPO
    )
    assert ancestry.returncode == 0, 'HEAD is not based on the supplied latest repository revision.'

    # Files unrelated to the requested source fixes must remain intact.
    assert (REPO / 'Makefile').read_bytes() == show_file(original_tip, 'Makefile'), 'Makefile was replaced.'
    assert (REPO / 'main.c').read_bytes() == show_file(original_tip, 'main.c'), 'main.c was unexpectedly replaced.'

    source = (REPO / 'crypto_utils.c').read_text(errors='replace')
    assert 'analyze_payload' in source, 'Payload analysis implementation is missing.'
    assert not re.search(r'state\s*==\s*370', source), 'The malicious 370 condition remains in the source.'
    assert not re.search(r'state\s*=\s*370\s*;', source), 'The malicious self-assignment remains in the source.'

    # Rebuild from source, ensuring no stale or substituted artifact is accepted.
    subprocess.run(['make', 'clean'], cwd=REPO, check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    subprocess.run(['make'], cwd=REPO, check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)

    analyzer = REPO / 'crypto_analyzer'
    assert analyzer.exists(), 'make did not produce crypto_analyzer.'
    mode = analyzer.stat().st_mode
    assert stat.S_ISREG(mode) and os.access(analyzer, os.X_OK), 'crypto_analyzer is not an executable regular file.'
    assert analyzer.read_bytes()[:4] == b'\x7fELF', 'crypto_analyzer is not the compiled ELF executable.'

    payloads = [1, 2, 3, 27, 123, 370, 371, 9999, 65535]
    rng = random.SystemRandom()
    while len(payloads) < 21:
        candidate = rng.randrange(1, 100001)
        if candidate not in payloads and terminates_like_original(candidate):
            payloads.append(candidate)
    for payload in payloads:
        run_analyzer(payload)

    # Preserve the original flag assertion and additionally compare it to a fresh execution.
    assert FLAG_FILE.is_file(), f'Missing {FLAG_FILE}'
    actual_content = FLAG_FILE.read_text().strip()
    assert actual_content == 'Result: 1', (
        f"Expected decrypted flag file to contain 'Result: 1', got {actual_content!r}."
    )
    fresh_output = run_analyzer(9999)
    assert FLAG_FILE.read_bytes() == fresh_output, 'decrypted_flag.txt is not the exact stdout of ./crypto_analyzer 9999.'


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
