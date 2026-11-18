#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

PIPELINE = Path('/home/user/pipeline.sh')
OUTPUT = Path('/home/user/best_primers.txt')
GENOME = Path('/app/genome.fasta')
NOTEBOOK = Path('/app/simulate_pcr.ipynb')


def calc_tm(seq):
    return 2 * (seq.count('A') + seq.count('T')) + 4 * (seq.count('G') + seq.count('C'))


def calculate_score(fwd, rev):
    if len(fwd) != 20 or len(rev) != 20:
        return 0.0
    if calc_tm(fwd) != 60 or calc_tm(rev) != 60:
        return 0.0
    score = 0.5
    if fwd[-1] in 'GC':
        score += 0.2
    if rev[-1] in 'GC':
        score += 0.2
    return min(1.0, score)


def reverse_complement(seq):
    return seq.translate(str.maketrans('ACGT', 'TGCA'))[::-1]


def extract_gene(path, gene):
    sequences = {}
    current = None
    with open(path) as handle:
        for raw in handle:
            line = raw.strip()
            if not line:
                continue
            if line.startswith('>'):
                current = line[1:].split()[0]
                sequences[current] = []
            elif current is not None:
                sequences[current].append(line.upper())
    key = 'gene_' + gene
    assert key in sequences, f'{key} was not found in {path}'
    return ''.join(sequences[key])


def candidates(sequence):
    windows = [sequence[i:i+20] for i in range(len(sequence) - 19)]
    fwd = {w for w in windows if len(w) == 20 and calc_tm(w) == 60}
    rev = {reverse_complement(w) for w in windows if len(w) == 20 and calc_tm(w) == 60}
    return fwd, rev


def read_pair(path):
    assert path.exists(), f'Output file not found: {path}'
    content = path.read_text().strip()
    assert ',' in content, f'Output file {path} does not contain comma-separated primers. Content: {content!r}'
    parts = content.split(',')
    assert len(parts) == 2, f'Output file {path} must contain exactly two comma-separated strings.'
    return parts[0].strip(), parts[1].strip()


def assert_best_pair(path, sequence, enforce_threshold):
    fwd, rev = read_pair(path)

    # Preserve the original efficiency assertion.
    score = calculate_score(fwd, rev)
    if enforce_threshold:
        threshold = 0.85
        assert score >= threshold, (
            f'Efficiency score for primers ({fwd}, {rev}) is {score}, '
            f'which is below the required threshold of {threshold}.'
        )

    valid_fwd, valid_rev = candidates(sequence)
    assert valid_fwd and valid_rev, 'The test gene has no valid primer candidates'
    assert fwd in valid_fwd, 'Forward primer is not a Tm-60 20-mer occurring in YFG1'
    assert rev in valid_rev, 'Reverse primer is not the reverse complement of a Tm-60 20-mer from YFG1'

    maximum = max(calculate_score(a, b) for a in valid_fwd for b in valid_rev)
    assert score == maximum, f'Submitted pair scores {score}, but the maximum valid score is {maximum}'
    return fwd, rev, valid_fwd, valid_rev


def main():
    assert PIPELINE.is_file(), f'Missing Bash pipeline: {PIPELINE}'
    script = PIPELINE.read_text(errors='replace')
    assert 'simulate_pcr.ipynb' in script, 'pipeline.sh does not reference the provided PCR notebook'

    # Check the submitted result against the real YFG1 sequence first.
    real_sequence = extract_gene(GENOME, 'YFG1')
    assert_best_pair(OUTPUT, real_sequence, True)

    # Exercise the pipeline on a small equivalent genome so exhaustive notebook
    # orchestration can be checked without requiring thousands of notebook starts.
    fixture_sequence = 'GAAAAAAAAAAGGGGGGGGGC'
    fixture_fwd, fixture_rev = candidates(fixture_sequence)
    assert len(fixture_fwd) == 2 and len(fixture_rev) == 2

    genome_backup = GENOME.read_bytes()
    notebook_backup = NOTEBOOK.read_bytes()
    work = Path(tempfile.mkdtemp(prefix='pipeline-verifier-'))
    log = work / 'calls.jsonl'
    bindir = work / 'bin'
    bindir.mkdir()

    real_jupyter = shutil.which('jupyter')
    real_papermill = shutil.which('papermill')
    assert real_jupyter and real_papermill, 'Required notebook tools are unavailable'

    wrapper = bindir / 'tool_wrapper.py'
    wrapper.write_text(r'''#!/usr/bin/env python3
import json, os, pathlib, sys

tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
texts = []
for arg in args:
    try:
        p = pathlib.Path(arg)
        if p.is_file() and p.suffix == '.ipynb':
            texts.append(p.read_text(errors='replace'))
    except Exception:
        pass
with open(os.environ['VERIFY_CALL_LOG'], 'a') as out:
    out.write(json.dumps({'tool': tool, 'args': args, 'notebooks': texts}) + '\n')
real = os.environ['REAL_JUPYTER'] if tool == 'jupyter' else os.environ['REAL_PAPERMILL']
os.execv(real, [real] + args)
''')
    wrapper.chmod(0o755)
    (bindir / 'jupyter').symlink_to(wrapper)
    (bindir / 'papermill').symlink_to(wrapper)

    try:
        GENOME.write_text('>gene_YFG1\n' + fixture_sequence + '\n>gene_OTHER\nATGCATGCATGCATGCATGC\n')
        if OUTPUT.exists():
            OUTPUT.unlink()

        env = os.environ.copy()
        env['PATH'] = str(bindir) + os.pathsep + env.get('PATH', '')
        env['VERIFY_CALL_LOG'] = str(log)
        env['REAL_JUPYTER'] = real_jupyter
        env['REAL_PAPERMILL'] = real_papermill

        result = subprocess.run(
            ['bash', str(PIPELINE)],
            cwd='/home/user', env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180
        )
        assert result.returncode == 0, f'pipeline.sh failed when executed:\n{result.stdout[-4000:]}'
        assert_best_pair(OUTPUT, fixture_sequence, False)

        assert log.exists(), 'pipeline.sh did not invoke jupyter or papermill'
        events = [json.loads(line) for line in log.read_text().splitlines() if line.strip()]
        execution_events = []
        for event in events:
            args = event['args']
            if event['tool'] == 'papermill' or (event['tool'] == 'jupyter' and '--execute' in args):
                execution_events.append(event)

        assert execution_events, 'No headless notebook execution was observed'

        missing = []
        for fwd in fixture_fwd:
            for rev in fixture_rev:
                found = False
                for event in execution_events:
                    blob = ' '.join(event['args']) + '\n' + '\n'.join(event['notebooks'])
                    if fwd in blob and rev in blob and re.search(r'(?<!\d)50(?!\d)', blob):
                        found = True
                        break
                if not found:
                    missing.append((fwd, rev))
        assert not missing, (
            'The pipeline did not execute the notebook with both primer sequences '
            f'and 50 iterations for every valid pair. Missing: {missing}'
        )
    finally:
        GENOME.write_bytes(genome_backup)
        NOTEBOOK.write_bytes(notebook_backup)
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
