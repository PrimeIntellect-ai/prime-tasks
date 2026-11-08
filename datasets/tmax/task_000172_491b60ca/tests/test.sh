#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import stat
import subprocess
from collections import Counter
from pathlib import Path

HOME = Path('/home/user')


def run(path, *args, cwd=HOME, env=None, timeout=30):
    return subprocess.run(
        [str(path), *map(str, args)], cwd=str(cwd), env=env,
        text=True, capture_output=True, timeout=timeout, check=True
    )


def test_etl_script_exists_and_executable():
    path = "/home/user/etl.sh"
    assert os.path.isfile(path), f"File {path} is missing."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."


def test_etl_script_behavior():
    raw = HOME / 'raw_data.csv'
    train = HOME / 'clean_train.tsv'
    test = HOME / 'clean_test.tsv'
    original_raw = raw.read_bytes()
    token = secrets.token_hex(6)
    rows = [
        ['id', 'split', 'text'],
        [f'tr_{token}_1', 'train', f'alpha_{token}'],
        [f'blank_{token}', 'train', '   '],
        [f'te_{token}_1', 'test', f'beta_{token}'],
        [f'ig_{token}', 'ignore', f'ignored_{token}'],
        [f'tr_{token}_2', 'train', f'gamma_{token}'],
        [f'te_{token}_2', 'test', f'delta_{token}'],
    ]
    try:
        with raw.open('w', newline='') as f:
            csv.writer(f, lineterminator='\n').writerows(rows)
        train.unlink(missing_ok=True)
        test.unlink(missing_ok=True)
        run(HOME / 'etl.sh')

        assert train.is_file(), 'etl.sh did not create clean_train.tsv'
        assert test.is_file(), 'etl.sh did not create clean_test.tsv'
        assert train.read_text().splitlines() == [
            f'tr_{token}_1\talpha_{token}',
            f'tr_{token}_2\tgamma_{token}',
        ]
        assert test.read_text().splitlines() == [
            f'te_{token}_1\tbeta_{token}',
            f'te_{token}_2\tdelta_{token}',
        ]
    finally:
        raw.write_bytes(original_raw)
        train.unlink(missing_ok=True)
        test.unlink(missing_ok=True)
        run(HOME / 'etl.sh')


def test_clean_data_created():
    train_path = "/home/user/clean_train.tsv"
    test_path = "/home/user/clean_test.tsv"

    assert os.path.isfile(train_path), f"File {train_path} is missing."
    assert os.path.isfile(test_path), f"File {test_path} is missing."

    with open(train_path, 'r') as f:
        train_lines = [line.strip() for line in f if line.strip()]

    with open(test_path, 'r') as f:
        test_lines = [line.strip() for line in f if line.strip()]

    assert len(train_lines) == 3, f"Expected 3 lines in {train_path}, found {len(train_lines)}."
    assert len(test_lines) == 3, f"Expected 3 lines in {test_path}, found {len(test_lines)}."

    expected_train_ids = {"1", "5", "9"}
    actual_train_ids = {line.split('\t')[0] for line in train_lines}
    assert actual_train_ids == expected_train_ids, f"Expected train IDs {expected_train_ids}, got {actual_train_ids}."

    expected_test_ids = {"3", "6", "8"}
    actual_test_ids = {line.split('\t')[0] for line in test_lines}
    assert actual_test_ids == expected_test_ids, f"Expected test IDs {expected_test_ids}, got {actual_test_ids}."

    assert train_lines == ['1\tapple', '5\tdog', '9\tgiraffe']
    assert test_lines == ['3\tbanana', '6\telephant', '8\tfrog']


def test_embedding_outputs_are_correct():
    for tsv_name, csv_name in [
        ('clean_train.tsv', 'train_embed.csv'),
        ('clean_test.tsv', 'test_embed.csv'),
    ]:
        tsv_path = HOME / tsv_name
        csv_path = HOME / csv_name
        assert csv_path.is_file(), f'File {csv_path} is missing.'
        expected = []
        for line in tsv_path.read_text().splitlines():
            ident, text = line.split('\t', 1)
            expected.append(','.join([ident] + [str(float(len(text) + i)) for i in range(10)]))
        assert csv_path.read_text().splitlines() == expected, f'{csv_path} is not the embedding of {tsv_path}'


def test_reduce_script_exists_and_executable():
    path = "/home/user/reduce.sh"
    assert os.path.isfile(path), f"File {path} is missing."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."


def test_reduce_script_behavior(tmp_path):
    token = secrets.token_hex(5)
    source = tmp_path / 'input.csv'
    rows = [
        [f'a_{token}'] + [f'{i}.125' for i in range(10)],
        [f'b_{token}'] + [f'-{i}.75' for i in range(10)],
    ]
    source.write_text('\n'.join(','.join(r) for r in rows) + '\n')
    for k in (2, 6, 8):
        result = run(HOME / 'reduce.sh', source, k)
        expected = '\n'.join(','.join(r[:k + 1]) for r in rows) + '\n'
        assert result.stdout == expected, f'reduce.sh produced incorrect output for K={k}'


def test_tune_script_exists_and_executable():
    path = "/home/user/tune.sh"
    assert os.path.isfile(path), f"File {path} is missing."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."


def test_tune_script_behavior(tmp_path):
    tune = HOME / 'tune.sh'
    reduce_path = HOME / 'reduce.sh'
    evaluate_path = HOME / 'evaluate.py'
    train_path = HOME / 'train_embed.csv'
    test_path = HOME / 'test_embed.csv'
    best_path = HOME / 'best_params.txt'

    saved = {
        p: (p.read_bytes(), stat.S_IMODE(p.stat().st_mode))
        for p in (reduce_path, evaluate_path, train_path, test_path)
    }
    saved_reduce = tmp_path / 'agent_reduce.sh'
    saved_reduce.write_bytes(saved[reduce_path][0])
    saved_reduce.chmod(saved[reduce_path][1])

    token = secrets.token_hex(5)
    train_rows = [[f'tr{i}_{token}'] + [str(i * 100 + j + 0.25) for j in range(10)] for i in range(4)]
    test_rows = [[f'te{i}_{token}'] + [str(i * 200 + j + 0.75) for j in range(10)] for i in range(3)]
    train_path.write_text('\n'.join(','.join(r) for r in train_rows) + '\n')
    test_path.write_text('\n'.join(','.join(r) for r in test_rows) + '\n')

    reduce_log = tmp_path / 'reduce_calls.log'
    eval_log = tmp_path / 'evaluate_calls.log'
    reduce_path.write_text(
        '#!/bin/bash\n'
        'printf "%s\\n" "$2" >> "$REDUCE_LOG"\n'
        f'exec {saved_reduce} "$@"\n'
    )
    reduce_path.chmod(0o755)

    ks = [2, 4, 6, 8]
    ts = ['0.1', '0.5', '0.9']
    target_k = secrets.choice(ks)
    target_t = secrets.choice(ts)
    evaluator = f'''import sys
K = int(sys.argv[3])
T = format(float(sys.argv[4]), '.1f')
train_expected = {train_rows!r}
test_expected = {test_rows!r}
def check(path, expected):
    with open(path) as f:
        actual = [line.rstrip('\\n').split(',') for line in f]
    wanted = [row[:K+1] for row in expected]
    if actual != wanted:
        raise SystemExit('reduced input is incorrect')
check(sys.argv[1], train_expected)
check(sys.argv[2], test_expected)
with open({str(eval_log)!r}, 'a') as f:
    f.write(f"{{K}},{{T}}\\n")
score = 87.35 - abs(K - {target_k}) * 1.7 - abs(float(T) - {float(target_t)}) * 3.1
print(f"{{score:.2f}}")
'''
    evaluate_path.write_text(evaluator)
    evaluate_path.chmod(0o755)

    env = os.environ.copy()
    env['REDUCE_LOG'] = str(reduce_log)
    try:
        best_path.unlink(missing_ok=True)
        run(tune, env=env, timeout=60)
        assert best_path.is_file(), 'tune.sh did not create best_params.txt'

        eval_calls = eval_log.read_text().splitlines() if eval_log.exists() else []
        expected_calls = {f'{k},{t}' for k in ks for t in ts}
        assert len(eval_calls) == 12, f'Expected 12 evaluate.py calls, got {len(eval_calls)}'
        assert set(eval_calls) == expected_calls, 'tune.sh did not evaluate the complete K/T grid'

        reduce_calls = reduce_log.read_text().splitlines() if reduce_log.exists() else []
        counts = Counter(reduce_calls)
        assert len(reduce_calls) >= 24, 'tune.sh did not use reduce.sh for both files in every grid combination'
        for k in ks:
            assert counts[str(k)] >= 6, f'tune.sh did not use reduce.sh for every combination with K={k}'

        lines = best_path.read_text().splitlines()
        assert len(lines) == 1, 'best_params.txt must contain exactly one line'
        match = re.fullmatch(r'K=([^,]+),T=([^,]+),Score=(.+)', lines[0])
        assert match, 'best_params.txt has the wrong format'
        assert int(match.group(1)) == target_k
        assert float(match.group(2)) == float(target_t)
        assert abs(float(match.group(3)) - 87.35) < 1e-9
    finally:
        for path, (data, mode) in saved.items():
            path.write_bytes(data)
            path.chmod(mode)
        best_path.unlink(missing_ok=True)
        run(tune, timeout=60)


def test_best_params_output():
    path = "/home/user/best_params.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did tune.sh run and create it?"

    with open(path, 'r') as f:
        content = f.read().strip()

    expected = "K=6,T=0.5,Score=60.00"
    assert expected in content or content == expected.replace("60.00", "60.0"), \
        f"Contents of {path} do not match the expected best parameters. Got: '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
