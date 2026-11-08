#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
from pathlib import Path

HOME = Path('/home/user')
PIPELINE = HOME / 'pipeline.sh'
ARTIFACTS = ['joined.csv', 'imputed.csv', 'shuffled.csv', 'train.csv', 'test.csv', 'metric.txt']

ORIGINAL_FEATURES = b'''1,10\n2,\n3,80\n4,20\n5,\n6,90\n7,40\n8,\n9,60\n10,100\n'''
ORIGINAL_TARGETS = b'''1,0\n2,1\n3,1\n4,0\n5,1\n6,1\n7,0\n8,0\n9,1\n10,1\n'''
ORIGINAL_SEED = bytes(range(1, 33))


def assert_original_inputs():
    assert (HOME / 'features.csv').read_bytes() == ORIGINAL_FEATURES, '/home/user/features.csv was altered'
    assert (HOME / 'targets.csv').read_bytes() == ORIGINAL_TARGETS, '/home/user/targets.csv was altered'
    assert (HOME / 'seed.dat').read_bytes() == ORIGINAL_SEED, '/home/user/seed.dat was altered'


def check_pipeline_artifact():
    assert PIPELINE.is_file(), 'Missing /home/user/pipeline.sh'
    mode = PIPELINE.stat().st_mode
    assert stat.S_ISREG(mode), '/home/user/pipeline.sh is not a regular file'
    assert mode & 0o111, '/home/user/pipeline.sh is not executable'
    first_line = PIPELINE.read_bytes().splitlines()[0] if PIPELINE.stat().st_size else b''
    assert first_line.startswith(b'#!') and b'bash' in first_line, '/home/user/pipeline.sh must be an executable bash script'


def run_pipeline():
    for name in ARTIFACTS:
        try:
            (HOME / name).unlink()
        except FileNotFoundError:
            pass
    subprocess.run([str(PIPELINE)], cwd=str(HOME), check=True, timeout=20)


def get_expected_metric():
    script = """
    join -t, -1 1 -2 1 <(sort -t, -k1,1 /home/user/features.csv) <(sort -t, -k1,1 /home/user/targets.csv) > /tmp/joined_truth.csv
    total=$(wc -l < /tmp/joined_truth.csv)
    train_n=$((total * 80 / 100))
    shuf --random-source=/home/user/seed.dat /tmp/joined_truth.csv > /tmp/shuffled_truth.csv
    head -n "$train_n" /tmp/shuffled_truth.csv > /tmp/train_truth.csv
    tail -n +$((train_n + 1)) /tmp/shuffled_truth.csv > /tmp/test_truth.csv

    mean_truth=$(awk -F, '$2 != "" {sum+=$2; count++} END {print sum/count}' /tmp/train_truth.csv)

    awk -F, -v m="$mean_truth" 'BEGIN{OFS=","} {if($2=="") $2=m; print $0}' /tmp/test_truth.csv > /tmp/test_imputed_truth.csv
    awk -F, '$2 > 50 {sum+=$3; count++} END {if(count>0) print sum/count; else print 0}' /tmp/test_imputed_truth.csv
    """
    result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, check=True)
    return result.stdout.strip()


def shuffled_rows():
    joined = subprocess.run(
        ['bash', '-c', 'join -t, -1 1 -2 1 <(sort -t, -k1,1 /home/user/features.csv) <(sort -t, -k1,1 /home/user/targets.csv)'],
        capture_output=True, text=True, check=True
    ).stdout
    result = subprocess.run(
        ['shuf', '--random-source=/home/user/seed.dat'],
        input=joined, capture_output=True, text=True, check=True
    )
    return joined, [line for line in result.stdout.splitlines() if line]


def parse_rows(path):
    assert path.is_file(), f'Missing output file: {path}'
    rows = []
    for line in path.read_text().splitlines():
        fields = line.split(',')
        assert len(fields) == 3, f'Invalid CSV row in {path}: {line!r}'
        rows.append(fields)
    return rows


def assert_imputed_split(path, expected_raw_rows, training_mean):
    actual = parse_rows(path)
    assert len(actual) == len(expected_raw_rows), f'Wrong row count in {path}'
    for got, raw in zip(actual, expected_raw_rows):
        exp = raw.split(',')
        assert got[0] == exp[0] and got[2] == exp[2], f'Wrong split or row order in {path}'
        assert got[1] != '', f'Missing feature was not imputed in {path}'
        expected_value = training_mean if exp[1] == '' else float(exp[1])
        assert abs(float(got[1]) - expected_value) < 1e-9, f'Wrong imputation value in {path}'


def test_metric_is_correct():
    assert_original_inputs()
    check_pipeline_artifact()
    run_pipeline()

    metric_path = "/home/user/metric.txt"
    assert os.path.isfile(metric_path), f"Missing file: {metric_path}. Did you run the modified pipeline.sh script?"

    with open(metric_path, "r") as f:
        actual_metric = f.read().strip()

    expected_metric = get_expected_metric()

    assert actual_metric == expected_metric, (
        f"Metric mismatch. Expected '{expected_metric}', but got '{actual_metric}'. "
        "Ensure that the mean is calculated ONLY from the training set, and used to impute missing values in both sets."
    )
    assert_original_inputs()


def test_pipeline_splits_before_statistics_and_imputes_both_sets():
    backups = {
        'features.csv': (HOME / 'features.csv').read_bytes(),
        'targets.csv': (HOME / 'targets.csv').read_bytes(),
        'seed.dat': (HOME / 'seed.dat').read_bytes(),
    }
    try:
        # Determine the deterministic 80/20 membership, then construct a case
        # where a global mean changes the metric but the training-only mean does not.
        (HOME / 'features.csv').write_text(''.join(f'{i},1\n' for i in range(1, 11)))
        (HOME / 'targets.csv').write_text(''.join(f'{i},0\n' for i in range(1, 11)))
        _, probe_order = shuffled_rows()
        ordered_ids = [int(row.split(',')[0]) for row in probe_order]
        train_ids, test_ids = ordered_ids[:8], ordered_ids[8:]

        features = {i: '' for i in range(1, 11)}
        targets = {i: 0 for i in range(1, 11)}
        features[train_ids[0]] = '40'
        features[test_ids[0]] = '100'
        targets[test_ids[1]] = 1
        (HOME / 'features.csv').write_text(''.join(f'{i},{features[i]}\n' for i in range(1, 11)))
        (HOME / 'targets.csv').write_text(''.join(f'{i},{targets[i]}\n' for i in range(1, 11)))

        expected_joined, expected_shuffled = shuffled_rows()
        expected_train_raw = expected_shuffled[:8]
        expected_test_raw = expected_shuffled[8:]
        observed_train = [float(r.split(',')[1]) for r in expected_train_raw if r.split(',')[1] != '']
        training_mean = sum(observed_train) / len(observed_train)
        assert training_mean == 40.0

        run_pipeline()

        assert (HOME / 'joined.csv').read_text() == expected_joined, 'The required join operation changed'
        assert (HOME / 'shuffled.csv').read_text().splitlines() == expected_shuffled, 'Data must be shuffled before imputation'
        assert_imputed_split(HOME / 'train.csv', expected_train_raw, training_mean)
        assert_imputed_split(HOME / 'test.csv', expected_test_raw, training_mean)

        expected_metric = '0'
        actual_metric = (HOME / 'metric.txt').read_text().strip()
        assert actual_metric == expected_metric, (
            f'Synthetic leakage case failed: expected metric {expected_metric}, got {actual_metric}'
        )
    finally:
        for name, data in backups.items():
            (HOME / name).write_bytes(data)
        # Leave the requested metric in its correct state for the original data.
        run_pipeline()
        assert_original_inputs()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
