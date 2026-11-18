#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import glob
import json
import os
import random
import shutil
import subprocess
import tempfile
import uuid

VALIDATOR = '/home/user/artifact_validator'


def run_validator(path):
    return subprocess.run([VALIDATOR, path], capture_output=True, text=True, timeout=5)


def expected_valid(obj):
    if not isinstance(obj, dict):
        return False
    if not isinstance(obj.get('experiment_id'), str):
        return False
    metrics = obj.get('metrics')
    tokenization = obj.get('tokenization')
    if not isinstance(metrics, dict) or not isinstance(tokenization, dict):
        return False
    cv = metrics.get('cv_folds')
    threshold = metrics.get('outlier_threshold_z')
    vocab = tokenization.get('vocab_size')
    if type(cv) is not int or cv < 2:
        return False
    if type(threshold) not in (int, float) or not 1.0 <= threshold <= 5.0:
        return False
    if type(vocab) is not int or vocab < 1000:
        return False
    return True


def test_json11_library_built():
    archive = '/app/json11/libjson11.a'
    assert os.path.isfile(archive), 'The static library /app/json11/libjson11.a was not built.'

    build = subprocess.run(
        ['make', '-B', 'libjson11.a'], cwd='/app/json11',
        capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, 'Running make for libjson11.a failed:\n' + build.stdout + build.stderr

    listing = subprocess.run(['ar', 't', archive], capture_output=True, text=True, timeout=5)
    assert listing.returncode == 0, 'libjson11.a is not a valid archive.'
    members = [line.strip() for line in listing.stdout.splitlines() if line.strip()]
    assert members, 'libjson11.a contains no object files.'
    assert any(name.endswith('.o') for name in members), 'libjson11.a contains no object member.'

    symbols = subprocess.run(['nm', '-C', archive], capture_output=True, text=True, timeout=10)
    assert symbols.returncode == 0, 'libjson11.a could not be inspected with nm.'
    assert 'json11::' in symbols.stdout and 'Json::parse' in symbols.stdout, \
        'libjson11.a does not contain the expected json11 implementation.'


def test_artifact_validator_executable():
    assert os.path.isfile(VALIDATOR), f'The validator {VALIDATOR} does not exist.'
    assert os.access(VALIDATOR, os.X_OK), f'The validator {VALIDATOR} is not executable.'
    assert os.path.isfile('/home/user/artifact_validator.cpp'), 'artifact_validator.cpp does not exist.'

    kind = subprocess.run(['file', VALIDATOR], capture_output=True, text=True, timeout=5)
    assert kind.returncode == 0 and 'ELF' in kind.stdout, 'artifact_validator is not a compiled ELF executable.'

    symbols = subprocess.run(['nm', '-C', VALIDATOR], capture_output=True, text=True, timeout=10)
    assert symbols.returncode == 0, 'artifact_validator symbols could not be inspected.'
    assert 'json11::' in symbols.stdout and 'Json::parse' in symbols.stdout, \
        'artifact_validator does not appear to be linked with json11.'


def test_validator_adversarial_corpus():
    clean_dir = '/app/corpora/clean/'
    evil_dir = '/app/corpora/evil/'
    clean_files = glob.glob(os.path.join(clean_dir, '*.json'))
    evil_files = glob.glob(os.path.join(evil_dir, '*.json'))

    assert len(clean_files) > 0, 'No clean files found in corpus.'
    assert len(evil_files) > 0, 'No evil files found in corpus.'

    bypassed_evil = []
    modified_clean = []
    for cf in clean_files:
        if run_validator(cf).returncode != 0:
            modified_clean.append(os.path.basename(cf))
    for ef in evil_files:
        if run_validator(ef).returncode == 0:
            bypassed_evil.append(os.path.basename(ef))

    error_msgs = []
    if bypassed_evil:
        error_msgs.append(f'{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {", ".join(bypassed_evil)}')
    if modified_clean:
        error_msgs.append(f'{len(modified_clean)} of {len(clean_files)} clean modified (rejected): {", ".join(modified_clean)}')
    assert not error_msgs, ' / '.join(error_msgs)


def test_validator_generated_cases():
    rng = random.SystemRandom()
    base = {
        'experiment_id': 'generated-' + uuid.uuid4().hex,
        'metrics': {
            'cv_folds': rng.randint(2, 20),
            'outlier_threshold_z': rng.uniform(1.1, 4.9),
        },
        'tokenization': {'vocab_size': rng.randint(1000, 100000)},
    }

    cases = [base]
    for threshold in (1.0, 5.0):
        item = copy.deepcopy(base)
        item['metrics']['outlier_threshold_z'] = threshold
        cases.append(item)
    for folds in (2, rng.randint(3, 30)):
        item = copy.deepcopy(base)
        item['metrics']['cv_folds'] = folds
        cases.append(item)
    item = copy.deepcopy(base)
    item['tokenization']['vocab_size'] = 1000
    cases.append(item)

    mutations = [
        lambda x: x.pop('experiment_id'),
        lambda x: x.__setitem__('experiment_id', 17),
        lambda x: x.__setitem__('experiment_id', None),
        lambda x: x.pop('metrics'),
        lambda x: x.__setitem__('metrics', []),
        lambda x: x['metrics'].pop('cv_folds'),
        lambda x: x['metrics'].__setitem__('cv_folds', 1),
        lambda x: x['metrics'].__setitem__('cv_folds', 2.5),
        lambda x: x['metrics'].__setitem__('cv_folds', True),
        lambda x: x['metrics'].__setitem__('cv_folds', '5'),
        lambda x: x['metrics'].pop('outlier_threshold_z'),
        lambda x: x['metrics'].__setitem__('outlier_threshold_z', 0.999),
        lambda x: x['metrics'].__setitem__('outlier_threshold_z', 5.001),
        lambda x: x['metrics'].__setitem__('outlier_threshold_z', '3.0'),
        lambda x: x['metrics'].__setitem__('outlier_threshold_z', True),
        lambda x: x['metrics'].__setitem__('outlier_threshold_z', None),
        lambda x: x.pop('tokenization'),
        lambda x: x.__setitem__('tokenization', 'not an object'),
        lambda x: x['tokenization'].pop('vocab_size'),
        lambda x: x['tokenization'].__setitem__('vocab_size', 999),
        lambda x: x['tokenization'].__setitem__('vocab_size', 1000.5),
        lambda x: x['tokenization'].__setitem__('vocab_size', False),
        lambda x: x['tokenization'].__setitem__('vocab_size', '50000'),
    ]
    for mutate in mutations:
        item = copy.deepcopy(base)
        mutate(item)
        cases.append(item)
    cases.extend([[], None, 'string', 42])

    malformed = [
        '{',
        '{"experiment_id":',
        '{"experiment_id":"x",}',
        json.dumps(base) + ' trailing garbage',
        '',
    ]

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix='validator-generated-') as directory:
        for obj in cases:
            path = os.path.join(directory, uuid.uuid4().hex + '.json')
            with open(path, 'w', encoding='utf-8') as handle:
                json.dump(obj, handle, separators=(',', ':'))
            result = run_validator(path)
            wanted = expected_valid(obj)
            assert result.returncode == (0 if wanted else 1), \
                f'Wrong exit code for generated JSON {obj!r}: got {result.returncode}, stderr={result.stderr!r}'
            if not wanted:
                assert result.stderr.strip(), 'Invalid JSON artifact must produce an error on stderr.'

        for raw in malformed:
            path = os.path.join(directory, uuid.uuid4().hex + '.json')
            with open(path, 'w', encoding='utf-8') as handle:
                handle.write(raw)
            result = run_validator(path)
            assert result.returncode == 1, \
                f'Malformed JSON was not rejected: {raw!r}; stderr={result.stderr!r}'
            assert result.stderr.strip(), 'Parse errors must be reported on stderr.'

        missing = os.path.join(directory, uuid.uuid4().hex + '.json')
        result = run_validator(missing)
        assert result.returncode == 1, 'A nonexistent input file must be rejected with exit code 1.'
        assert result.stderr.strip(), 'A nonexistent input file must produce an error on stderr.'


def test_run_validation_script_results():
    script = '/home/user/run_validation.sh'
    accepted_dir = '/home/user/accepted'
    rejected_dir = '/home/user/rejected'
    assert os.path.isfile(script), f'Script {script} does not exist.'

    shutil.rmtree(accepted_dir, ignore_errors=True)
    shutil.rmtree(rejected_dir, ignore_errors=True)
    result = subprocess.run(['bash', script], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, 'run_validation.sh failed:\n' + result.stdout + result.stderr

    assert os.path.isdir(accepted_dir), f'Directory {accepted_dir} does not exist.'
    assert os.path.isdir(rejected_dir), f'Directory {rejected_dir} does not exist.'

    clean_dir = '/app/corpora/clean'
    evil_dir = '/app/corpora/evil'
    expected_clean = set(os.listdir(clean_dir))
    expected_evil = set(os.listdir(evil_dir))
    actual_accepted = set(os.listdir(accepted_dir))
    actual_rejected = set(os.listdir(rejected_dir))

    assert actual_accepted == expected_clean, f'Accepted directory contents mismatch. Expected: {expected_clean}, Found: {actual_accepted}'
    assert actual_rejected == expected_evil, f'Rejected directory contents mismatch. Expected: {expected_evil}, Found: {actual_rejected}'

    for name in expected_clean:
        destination = os.path.join(accepted_dir, name)
        assert os.path.isfile(destination) and not os.path.islink(destination)
        assert open(destination, 'rb').read() == open(os.path.join(clean_dir, name), 'rb').read()
    for name in expected_evil:
        destination = os.path.join(rejected_dir, name)
        assert os.path.isfile(destination) and not os.path.islink(destination)
        assert open(destination, 'rb').read() == open(os.path.join(evil_dir, name), 'rb').read()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
