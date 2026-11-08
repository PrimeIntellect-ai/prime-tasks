#!/bin/bash
set -u
mkdir -p /logs/verifier

cp /home/user/targets.txt /tmp/original_targets.txt
restore_targets() {
    cp /tmp/original_targets.txt /home/user/targets.txt 2>/dev/null || true
}
trap restore_targets EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/primer_analysis')
RESULTS = Path('/home/user/results.txt')
TARGETS = Path('/home/user/targets.txt')
MASK32 = (1 << 32) - 1
MASK64 = (1 << 64) - 1


def compute_alignment_scores(primer, targets):
    scores = []
    k = len(primer)
    for t in targets:
        max_score = 0
        for i in range(len(t) - k + 1):
            sub = t[i:i+k]
            score = sum(1 for a, b in zip(primer, sub) if a == b)
            if score > max_score:
                max_score = score
        scores.append(max_score)
    return scores


def rotl32(value, amount):
    return ((value << amount) | (value >> (32 - amount))) & MASK32


def quarter_round(x, a, b, c, d):
    x[a] = (x[a] + x[b]) & MASK32
    x[d] = rotl32(x[d] ^ x[a], 16)
    x[c] = (x[c] + x[d]) & MASK32
    x[b] = rotl32(x[b] ^ x[c], 12)
    x[a] = (x[a] + x[b]) & MASK32
    x[d] = rotl32(x[d] ^ x[a], 8)
    x[c] = (x[c] + x[d]) & MASK32
    x[b] = rotl32(x[b] ^ x[c], 7)


def seed_from_u64(seed):
    # rand_core::SeedableRng::seed_from_u64 expansion used by ChaCha8Rng.
    state = seed & MASK64
    out = bytearray()
    for _ in range(8):
        state = (state * 6364136223846793005 + 11634580027462260723) & MASK64
        xorshifted = (((state >> 18) ^ state) >> 27) & MASK32
        rot = state >> 59
        value = ((xorshifted >> rot) | (xorshifted << ((-rot) & 31))) & MASK32
        out.extend(value.to_bytes(4, 'little'))
    return bytes(out)


class ChaCha8:
    def __init__(self, seed):
        key = seed_from_u64(seed)
        self.key_words = [int.from_bytes(key[i:i+4], 'little') for i in range(0, 32, 4)]
        self.counter = 0
        self.words = []
        self.position = 0

    def _refill(self):
        constants = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574]
        initial = constants + self.key_words + [
            self.counter & MASK32,
            (self.counter >> 32) & MASK32,
            0,
            0,
        ]
        x = initial[:]
        for _ in range(4):
            quarter_round(x, 0, 4, 8, 12)
            quarter_round(x, 1, 5, 9, 13)
            quarter_round(x, 2, 6, 10, 14)
            quarter_round(x, 3, 7, 11, 15)
            quarter_round(x, 0, 5, 10, 15)
            quarter_round(x, 1, 6, 11, 12)
            quarter_round(x, 2, 7, 8, 13)
            quarter_round(x, 3, 4, 9, 14)
        self.words = [(x[i] + initial[i]) & MASK32 for i in range(16)]
        self.position = 0
        self.counter = (self.counter + 1) & MASK64

    def next_u32(self):
        if self.position == len(self.words):
            self._refill()
        value = self.words[self.position]
        self.position += 1
        return value

    def next_u64(self):
        return self.next_u32() | (self.next_u32() << 32)

    def gen_index_500(self):
        # rand 0.8's 64-bit UniformInt multiply-high method. Rejection is
        # included even though its probability for this range is negligible.
        threshold = ((1 << 64) - 500) % 500
        while True:
            product = self.next_u64() * 500
            low = product & MASK64
            if low >= threshold:
                return product >> 64


def welford_sample_variance(values):
    count = 0
    mean = 0.0
    m2 = 0.0
    for value in values:
        count += 1
        delta = value - mean
        mean += delta / count
        delta2 = value - mean
        m2 += delta * delta2
    return m2 / (count - 1)


def make_variant(original):
    variant = []
    alphabet = 'ACGT'
    for i, target in enumerate(original):
        digest = hashlib.sha256((str(i) + ':' + target).encode()).digest()
        seq = ''.join(alphabet[digest[j % len(digest)] & 3] for j in range(50))
        primer = 'ATGCGTGA' if digest[0] & 1 else 'TCGATCCA'
        offset = digest[1] % 43
        seq = seq[:offset] + primer + seq[offset + 8:]
        variant.append(seq)
    return variant


def expected_for_datasets(datasets):
    score_sets = []
    for targets in datasets:
        assert len(targets) == 500
        score_sets.append((
            compute_alignment_scores('ATGCGTGA', targets),
            compute_alignment_scores('TCGATCCA', targets),
        ))

    rng = ChaCha8(42)
    sums_a = [[] for _ in datasets]
    sums_b = [[] for _ in datasets]

    # The first flat 10,000*500-index array is for A.
    for _ in range(10000):
        totals = [0] * len(datasets)
        for _ in range(500):
            index = rng.gen_index_500()
            for d, (scores_a, _) in enumerate(score_sets):
                totals[d] += scores_a[index]
        for d, total in enumerate(totals):
            sums_a[d].append(total)

    # The next flat 10,000*500-index array from the same RNG is for B.
    for _ in range(10000):
        totals = [0] * len(datasets)
        for _ in range(500):
            index = rng.gen_index_500()
            for d, (_, scores_b) in enumerate(score_sets):
                totals[d] += scores_b[index]
        for d, total in enumerate(totals):
            sums_b[d].append(total)

    results = []
    for d in range(len(datasets)):
        means_a = [value / 500.0 for value in sums_a[d]]
        means_b = [value / 500.0 for value in sums_b[d]]
        sorted_a = sorted(means_a)
        sorted_b = sorted(means_b)
        results.append({
            'CI_A_LOWER': sorted_a[250],
            'CI_A_UPPER': sorted_a[9750],
            'CI_B_LOWER': sorted_b[250],
            'CI_B_UPPER': sorted_b[9750],
            'VAR_A': welford_sample_variance(means_a),
            'VAR_B': welford_sample_variance(means_b),
            'P_VALUE': sum(a <= b for a, b in zip(means_a, means_b)) / 10000.0,
        })
    return results


def parse_results():
    assert RESULTS.is_file(), f'Results file not found: {RESULTS}'
    content = RESULTS.read_text()
    keys = [
        'CI_A_LOWER', 'CI_A_UPPER', 'CI_B_LOWER', 'CI_B_UPPER',
        'VAR_A', 'VAR_B', 'P_VALUE'
    ]
    pattern = ''.join(rf'{key}=([0-9]+\.[0-9]{{4}})\n' for key in keys)
    match = re.fullmatch(pattern, content)
    assert match is not None, 'results.txt must contain exactly the seven ordered metrics, each with four decimal places'
    return dict(zip(keys, map(float, match.groups())))


def run_submission(targets):
    TARGETS.write_text(''.join(target + '\n' for target in targets))
    if RESULTS.exists():
        RESULTS.unlink()
    proc = subprocess.run(
        ['/usr/bin/cargo', 'run', '--release', '--offline', '--quiet'],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=240,
    )
    assert proc.returncode == 0, 'Rust program failed:\n' + proc.stdout[-4000:]
    return parse_results()


def assert_metrics(actual, expected):
    # Preserve the original sanity assertions.
    assert actual['CI_A_LOWER'] <= actual['CI_A_UPPER'], 'CI_A_LOWER > CI_A_UPPER'
    assert actual['CI_B_LOWER'] <= actual['CI_B_UPPER'], 'CI_B_LOWER > CI_B_UPPER'
    assert actual['VAR_A'] >= 0, 'VAR_A is negative'
    assert actual['VAR_B'] >= 0, 'VAR_B is negative'
    assert 0 <= actual['P_VALUE'] <= 1, 'P_VALUE is out of bounds [0, 1]'

    for key, expected_value in expected.items():
        rounded = float(f'{expected_value:.4f}')
        assert actual[key] == rounded, f'{key}: expected {rounded:.4f}, got {actual[key]:.4f}'


def test_project_source_and_exact_behavior():
    assert PROJECT.is_dir(), 'Cargo project directory is missing'
    manifest_path = PROJECT / 'Cargo.toml'
    main_path = PROJECT / 'src' / 'main.rs'
    assert manifest_path.is_file(), 'Cargo.toml is missing'
    assert main_path.is_file(), 'src/main.rs is missing'

    manifest = manifest_path.read_text()
    source = '\n'.join(
        path.read_text(errors='replace')
        for path in (PROJECT / 'src').rglob('*.rs')
    )
    assert re.search(r'(?m)^\s*rayon\s*=', manifest), 'rayon must be a Cargo dependency'
    assert 'rayon::prelude' in source, 'rayon prelude is not imported'
    assert re.search(r'\.(?:into_par_iter|par_iter)\s*\(', source), 'bootstrap computation is not parallelized with rayon'
    assert 'ChaCha8Rng' in source and re.search(r'seed_from_u64\s*\(\s*42', source), 'required seeded ChaCha8Rng is missing'
    assert re.search(r'gen_range\s*\(\s*0\s*\.\.\s*500\s*\)', source), 'required 0..500 index generation is missing'
    assert re.search(r'(?i)delta', source) and re.search(r'(?i)m2', source), 'Welford delta/M2 update is missing'

    original = [line.strip() for line in Path('/tmp/original_targets.txt').read_text().splitlines() if line.strip()]
    assert len(original) == 500
    variant = make_variant(original)
    expected_variant, expected_original = expected_for_datasets([variant, original])

    variant_actual = run_submission(variant)
    assert_metrics(variant_actual, expected_variant)

    original_actual = run_submission(original)
    assert_metrics(original_actual, expected_original)

    # Preserve the original checks that the raw score means lie near the CIs.
    scores_a = compute_alignment_scores('ATGCGTGA', original)
    scores_b = compute_alignment_scores('TCGATCCA', original)
    mean_a = sum(scores_a) / len(scores_a)
    mean_b = sum(scores_b) / len(scores_b)
    assert original_actual['CI_A_LOWER'] - 0.2 <= mean_a <= original_actual['CI_A_UPPER'] + 0.2
    assert original_actual['CI_B_LOWER'] - 0.2 <= mean_b <= original_actual['CI_B_UPPER'] + 0.2
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

restore_targets
trap - EXIT
