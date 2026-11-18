#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
from pathlib import Path

SOURCE = Path('/home/user/processor.rs')
DATASET = Path('/home/user/dataset.txt')
SUMMARY = Path('/home/user/summary.txt')
BINARY = Path('/tmp/processor_under_test')


def expected_summary(documents):
    token_sets = [set(line.lower().split()) for line in documents]
    query = token_sets[0]
    scored = []
    for index, tokens in enumerate(token_sets[1:], start=1):
        union = query | tokens
        similarity = len(query & tokens) / len(union) if union else 0.0
        scored.append((index, similarity))

    mean = sum(similarity for _, similarity in scored) / len(scored)
    top_three = [index for index, _ in sorted(scored, key=lambda item: (-item[1], item[0]))[:3]]
    return [
        f'Mean Similarity: {mean:.4f}',
        f'Top 3: [{", ".join(map(str, top_three))}]',
    ]


def run_processor(documents):
    DATASET.write_text('\n'.join(documents) + '\n', encoding='utf-8')
    if SUMMARY.exists() or SUMMARY.is_symlink():
        SUMMARY.unlink()

    subprocess.run([str(BINARY)], cwd='/home/user', check=True, timeout=10)
    assert os.path.isfile(SUMMARY), f'Output file is missing at {SUMMARY}'
    assert not SUMMARY.is_symlink(), f'{SUMMARY} must be a regular file'
    assert stat.S_ISREG(SUMMARY.stat().st_mode), f'{SUMMARY} must be a regular file'
    return SUMMARY.read_text(encoding='utf-8').strip().splitlines()


def random_case():
    rng = secrets.SystemRandom()
    query_tokens = [secrets.token_hex(8) for _ in range(6)]
    documents = ['  '.join(query_tokens + [query_tokens[0].upper()])]

    for _ in range(7):
        selected = [token for token in query_tokens if rng.randrange(2)]
        outsiders = [secrets.token_hex(8) + (',' if rng.randrange(2) else '')
                     for _ in range(rng.randrange(1, 4))]
        words = selected + outsiders
        rng.shuffle(words)
        if words and rng.randrange(2):
            words.append(words[0].upper())
        documents.append(('\t' if rng.randrange(2) else '   ').join(words))
    return documents


def main():
    # Preserve the original existence assertion and additionally require a real source file.
    assert os.path.isfile(SOURCE), f'Rust source file is missing at {SOURCE}'
    assert not SOURCE.is_symlink(), f'{SOURCE} must be a regular Rust source file'
    assert stat.S_ISREG(SOURCE.stat().st_mode), f'{SOURCE} must be a regular Rust source file'

    subprocess.run(
        ['rustc', str(SOURCE), '-o', str(BINARY)],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert BINARY.is_file(), 'rustc did not produce an executable'

    original_dataset = DATASET.read_bytes()
    previous_summary = SUMMARY.read_bytes() if SUMMARY.is_file() else None

    try:
        original_documents = original_dataset.decode('utf-8').splitlines()
        original_lines = run_processor(original_documents)

        # Preserve the original verifier's assertions for the supplied dataset.
        assert len(original_lines) >= 2, f'Expected at least 2 lines in {SUMMARY}, found {len(original_lines)}'
        mean_line = original_lines[0].strip()
        top3_line = original_lines[1].strip()
        assert mean_line == 'Mean Similarity: 0.3705', f'Incorrect Mean Similarity line. Got: {mean_line}'
        assert top3_line == 'Top 3: [1, 4, 2]', f'Incorrect Top 3 line. Got: {top3_line}'
        assert original_lines == ['Mean Similarity: 0.3705', 'Top 3: [1, 4, 2]'], 'summary.txt must have exactly the required two lines'

        fixed_case = [
            'Alpha alpha BETA, gamma delta',
            'alpha BETA, gamma extra!',
            'ALPHA beta, gamma extra?',
            'alpha delta',
            'unrelated punctuation, only',
            'alpha BETA, gamma delta newcomer',
        ]
        assert run_processor(fixed_case) == expected_summary(fixed_case)

        # Runtime-generated inputs prevent a prewritten summary from passing.
        for _ in range(3):
            documents = random_case()
            actual = run_processor(documents)
            expected = expected_summary(documents)
            assert actual == expected, f'Incorrect output: expected {expected}, got {actual}'
    finally:
        DATASET.write_bytes(original_dataset)
        try:
            if BINARY.is_file():
                if SUMMARY.exists() or SUMMARY.is_symlink():
                    SUMMARY.unlink()
                subprocess.run([str(BINARY)], cwd='/home/user', check=True, timeout=10)
            elif previous_summary is not None:
                SUMMARY.write_bytes(previous_summary)
        except Exception:
            if previous_summary is not None:
                SUMMARY.write_bytes(previous_summary)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
