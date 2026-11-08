#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import secrets
import stat
import subprocess
from collections import Counter

import pandas as pd
from sklearn.linear_model import LogisticRegression

HOME = '/home/user'
DATASET = f'{HOME}/dataset.tsv'
PREP = f'{HOME}/prep.sh'
TRAIN = f'{HOME}/train.py'
TRACK = f'{HOME}/track.sh'
FEATURES = f'{HOME}/features.csv'
EXPERIMENTS = f'{HOME}/experiments.jsonl'
FLOAT_RE = re.compile(r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?')


def test_scripts_exist_and_executable():
    assert os.path.exists(PREP), f'Missing {PREP}'
    assert os.path.exists(TRAIN), f'Missing {TRAIN}'
    assert os.path.exists(TRACK), f'Missing {TRACK}'
    assert os.stat(PREP).st_mode & stat.S_IXUSR, f'{PREP} is not executable'
    assert os.stat(TRACK).st_mode & stat.S_IXUSR, f'{TRACK} is not executable'


def test_experiments_jsonl_format():
    assert os.path.exists(EXPERIMENTS), f'Missing {EXPERIMENTS}. Did track.sh run successfully?'
    with open(EXPERIMENTS) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 3, f'Expected exactly 3 lines in {EXPERIMENTS}, found {len(lines)}'

    found_n_words = []
    for idx, line in enumerate(lines):
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            assert False, f'Line {idx + 1} is not valid JSON: {line}'
        assert 'n_words' in data, f"Missing 'n_words' key in line {idx + 1}: {line}"
        assert 'accuracy' in data, f"Missing 'accuracy' key in line {idx + 1}: {line}"
        assert isinstance(data['n_words'], int), f"'n_words' must be an integer, got {type(data['n_words'])}"
        assert isinstance(data['accuracy'], (float, int)), f"'accuracy' must be a float, got {type(data['accuracy'])}"
        assert 0.0 <= data['accuracy'] <= 1.0, f"'accuracy' must be between 0 and 1, got {data['accuracy']}"
        found_n_words.append(data['n_words'])
    assert sorted(found_n_words) == [3, 5, 10], f'Expected n_words to be [3, 5, 10], got {sorted(found_n_words)}'


def make_challenge_dataset():
    rng = secrets.SystemRandom()
    words = ['w' + secrets.token_hex(5) for _ in range(15)]
    rows = []
    for i in range(40):
        label = i % 2
        count = rng.randint(4, 11)
        tokens = [rng.choice(words) for _ in range(count)]
        # Add label-correlated occurrences while retaining random frequencies and duplicates.
        tokens.extend([words[label], words[label], words[2 + (i % 5)]])
        rendered = []
        for j, token in enumerate(tokens):
            rendered.append(token.upper() if (i + j) % 2 else token)
        rows.append((label, '@@!! '.join(rendered) + ('???' if i % 2 else '...')))
    with open(DATASET, 'w', newline='') as f:
        writer = csv.writer(f, delimiter='\t', lineterminator='\n')
        writer.writerow(['label', 'text'])
        writer.writerows(rows)


def derive_expected(n):
    records = []
    counts = Counter()
    with open(DATASET, newline='') as f:
        reader = csv.DictReader(f, delimiter='\t')
        assert reader.fieldnames == ['label', 'text']
        for row in reader:
            cleaned = re.sub(r'[^a-z0-9]', ' ', row['text'].lower())
            tokens = [token for token in cleaned.split(' ') if token]
            counts.update(tokens)
            records.append((int(row['label']), set(tokens)))
    top = [word for word, _ in sorted(counts.items(), key=lambda item: (-item[1], item[0]))[:n]]
    table = [top + ['label']]
    for label, present in records:
        table.append([str(int(word in present)) for word in top] + [str(label)])
    return top, table


def read_features():
    assert os.path.isfile(FEATURES), f'Missing {FEATURES}'
    with open(FEATURES, newline='') as f:
        return list(csv.reader(f))


def run_checked(command, **kwargs):
    return subprocess.run(command, check=True, text=True, capture_output=True, timeout=60, **kwargs)


def expected_accuracy(table):
    header = table[0]
    body = table[1:]
    x = pd.DataFrame([[int(value) for value in row[:-1]] for row in body], columns=header[:-1])
    y = [int(row[-1]) for row in body]
    model = LogisticRegression(random_state=42)
    model.fit(x, y)
    return float(model.score(x, y))


def install_sklearn_hook(hook_dir, log_path):
    os.makedirs(hook_dir)
    source = r'''import json
import os
import sklearn.linear_model
_real = sklearn.linear_model.LogisticRegression

def _checked_logistic_regression(*args, **kwargs):
    with open(os.environ['LR_CALL_LOG'], 'a') as f:
        f.write(json.dumps({'nargs': len(args), 'kwargs': kwargs}, default=repr) + '\n')
    if args or set(kwargs) != {'random_state'} or kwargs.get('random_state') != 42:
        raise AssertionError('LogisticRegression must use random_state=42 and all other defaults')
    return _real(*args, **kwargs)

sklearn.linear_model.LogisticRegression = _checked_logistic_regression
'''
    with open(os.path.join(hook_dir, 'sitecustomize.py'), 'w') as f:
        f.write(source)
    open(log_path, 'w').close()


def parse_accuracy(stdout):
    value_text = stdout.strip()
    assert FLOAT_RE.fullmatch(value_text), f'train.py must print only one float, got {stdout!r}'
    value = float(value_text)
    assert math.isfinite(value) and 0.0 <= value <= 1.0, f'Invalid accuracy {value}'
    return value


def test_pipeline_behavior_on_unseen_data():
    original_dataset = open(DATASET, 'rb').read()
    hook_dir = '/tmp/verifier_sklearn_hook_' + secrets.token_hex(6)
    lr_log = '/tmp/verifier_lr_' + secrets.token_hex(6) + '.jsonl'
    install_sklearn_hook(hook_dir, lr_log)
    env = os.environ.copy()
    env['PYTHONPATH'] = hook_dir
    env['LR_CALL_LOG'] = lr_log

    moved_prep = None
    moved_train = None
    try:
        make_challenge_dataset()

        expected = {}
        for n in (3, 5, 10):
            _, table = derive_expected(n)
            expected[n] = (table, expected_accuracy(table))
            result = run_checked([PREP, str(n)], cwd=HOME)
            assert result.stdout == '', f'prep.sh produced unexpected stdout: {result.stdout!r}'
            assert read_features() == table, f'features.csv is incorrect for N={n}'

        # Execute train.py and verify both its model construction and independently derived result.
        open(lr_log, 'w').close()
        result = run_checked(['python3', TRAIN], cwd=HOME, env=env)
        actual = parse_accuracy(result.stdout)
        assert abs(actual - expected[10][1]) <= 1e-12, \
            f'train.py accuracy {actual} does not match expected {expected[10][1]}'
        with open(lr_log) as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert len(calls) == 1, 'train.py must instantiate LogisticRegression exactly once'

        # Wrap the submitted prep/train artifacts so track.sh calls can be observed while
        # still executing the submitted implementations.
        suffix = secrets.token_hex(8)
        moved_prep = f'/tmp/submitted_prep_{suffix}.sh'
        moved_train = f'/tmp/submitted_train_{suffix}.py'
        prep_calls = f'/tmp/prep_calls_{suffix}'
        train_calls = f'/tmp/train_calls_{suffix}'
        os.replace(PREP, moved_prep)
        os.replace(TRAIN, moved_train)

        with open(PREP, 'w') as f:
            f.write(f'''#!/bin/bash\nprintf '%s\\n' "$*" >> "$PREP_CALL_LOG"\nexec {moved_prep} "$@"\n''')
        os.chmod(PREP, 0o755)
        with open(TRAIN, 'w') as f:
            f.write('''import json, os, runpy, sys\nwith open(os.environ["TRAIN_CALL_LOG"], "a") as log:\n    log.write(json.dumps(sys.argv[1:]) + "\\n")\nrunpy.run_path(os.environ["ORIGINAL_TRAIN"], run_name="__main__")\n''')

        for path in (prep_calls, train_calls, lr_log):
            open(path, 'w').close()
        if os.path.exists(EXPERIMENTS):
            os.remove(EXPERIMENTS)
        track_env = env.copy()
        track_env.update({
            'PREP_CALL_LOG': prep_calls,
            'TRAIN_CALL_LOG': train_calls,
            'ORIGINAL_TRAIN': moved_train,
        })
        run_checked([TRACK], cwd=HOME, env=track_env)

        with open(prep_calls) as f:
            observed_prep = [line.strip() for line in f if line.strip()]
        assert observed_prep == ['3', '5', '10'], \
            f'track.sh must invoke prep.sh with 3, 5, and 10 in order; got {observed_prep}'
        with open(train_calls) as f:
            observed_train = [json.loads(line) for line in f if line.strip()]
        assert observed_train == [[], [], []], \
            f'track.sh must invoke train.py once without arguments per experiment; got {observed_train}'
        with open(lr_log) as f:
            track_lr_calls = [json.loads(line) for line in f if line.strip()]
        assert len(track_lr_calls) == 3, 'Each tracked experiment must train the required model'

        with open(EXPERIMENTS) as f:
            lines = [line.rstrip('\n') for line in f if line.strip()]
        assert len(lines) == 3, f'Expected exactly 3 experiment lines, got {len(lines)}'
        parsed = []
        for index, (line, n) in enumerate(zip(lines, (3, 5, 10)), 1):
            pattern = re.compile(r'^\{"n_words": ' + str(n) + r', "accuracy": (' + FLOAT_RE.pattern + r')\}$')
            match = pattern.fullmatch(line)
            assert match, f'Experiment line {index} has incorrect exact format: {line!r}'
            data = json.loads(line)
            assert list(data.keys()) == ['n_words', 'accuracy']
            assert isinstance(data['n_words'], int) and data['n_words'] == n
            assert isinstance(data['accuracy'], (float, int)) and not isinstance(data['accuracy'], bool)
            assert 0.0 <= data['accuracy'] <= 1.0
            assert abs(float(data['accuracy']) - expected[n][1]) <= 1e-12, \
                f'Incorrect tracked accuracy for N={n}'
            parsed.append(data)
        assert read_features() == expected[10][0], 'track.sh did not leave features.csv from prep.sh 10'
    finally:
        with open(DATASET, 'wb') as f:
            f.write(original_dataset)
        if moved_prep is not None and os.path.exists(moved_prep):
            if os.path.exists(PREP):
                os.remove(PREP)
            os.replace(moved_prep, PREP)
        if moved_train is not None and os.path.exists(moved_train):
            if os.path.exists(TRAIN):
                os.remove(TRAIN)
            os.replace(moved_train, TRAIN)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
