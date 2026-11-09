#!/bin/bash
set -e
mkdir -p /logs/verifier

# Supply only Bash and the standard utilities permitted by the task through PATH.
ALLOWED_BIN=/tmp/etl-allowed-bin
rm -rf "$ALLOWED_BIN"
mkdir -p "$ALLOWED_BIN"
for cmd in bash sh awk gawk sed grep egrep fgrep bc cat sort cut paste join comm tr head tail wc uniq printf expr seq basename dirname readlink realpath test '[' true false cp mv rm mkdir rmdir touch mktemp chmod chown chgrp ln link unlink stat dd od tee split cksum md5sum sha1sum sha224sum sha256sum sha384sum sha512sum date sleep timeout env printenv pwd ls find xargs; do
    path=$(command -v "$cmd" 2>/dev/null || true)
    if [ -n "$path" ]; then
        ln -sf "$path" "$ALLOWED_BIN/$cmd"
    fi
done

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import pwd
import secrets
import stat
import subprocess

SCRIPT = '/home/user/etl_pipeline.sh'
EVENTS = '/home/user/events.csv'
INDICES = '/home/user/bootstrap_indices.txt'
OUTPUTS = [
    '/home/user/phase1_aggregates.csv',
    '/home/user/phase2_ci.txt',
    '/home/user/phase3_accuracy.txt',
]
ALLOWED_BIN = '/tmp/etl-allowed-bin'


def get_events_data():
    events = []
    with open(EVENTS, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            events.append({
                'id': int(row['id']),
                'category': row['category'],
                'value': int(row['value']),
                'label': int(row['label'])
            })
    return events


def get_bootstrap_indices():
    indices_list = []
    with open(INDICES, 'r') as f:
        for line in f:
            indices = [int(x) for x in line.strip().split(',')]
            indices_list.append(indices)
    return indices_list


def compute_phase1_truth(events):
    sums = {}
    counts = {}
    for ev in events:
        c = ev['category']
        sums[c] = sums.get(c, 0) + ev['value']
        counts[c] = counts.get(c, 0) + 1

    results = []
    for c in sorted(sums.keys()):
        avg = sums[c] / counts[c]
        results.append(f"{c},{avg:.2f}")

    return "category,average_value\n" + "\n".join(results) + "\n"


def compute_phase2_truth(events, indices_list):
    means = []
    for indices in indices_list:
        total = sum(events[idx - 1]['value'] for idx in indices)
        mean_val = total / len(indices)
        means.append(round(mean_val, 2))

    means.sort()
    p5 = means[4]
    p95 = means[94]
    return f"{p5:.2f},{p95:.2f}"


def compute_phase3_truth(events):
    folds = {i: [] for i in range(5)}
    for i, ev in enumerate(events):
        fold_idx = i % 5
        folds[fold_idx].append(ev)

    correct = 0
    total = len(events)

    for val_fold_idx in range(5):
        train_data = []
        val_data = folds[val_fold_idx]
        for i in range(5):
            if i != val_fold_idx:
                train_data.extend(folds[i])

        count_0 = sum(1 for ev in train_data if ev['label'] == 0)
        count_1 = sum(1 for ev in train_data if ev['label'] == 1)
        total_train = len(train_data)

        p_label_0 = count_0 / total_train if total_train > 0 else 0
        p_label_1 = count_1 / total_train if total_train > 0 else 0

        cat_counts_0 = {}
        cat_counts_1 = {}
        for ev in train_data:
            c = ev['category']
            if ev['label'] == 0:
                cat_counts_0[c] = cat_counts_0.get(c, 0) + 1
            else:
                cat_counts_1[c] = cat_counts_1.get(c, 0) + 1

        for ev in val_data:
            c = ev['category']
            p_cat_given_0 = (cat_counts_0.get(c, 0) / count_0) if count_0 > 0 else 0
            p_cat_given_1 = (cat_counts_1.get(c, 0) / count_1) if count_1 > 0 else 0

            score_0 = p_label_0 * p_cat_given_0
            score_1 = p_label_1 * p_cat_given_1
            pred = 1 if score_1 >= score_0 else 0
            if pred == ev['label']:
                correct += 1

    accuracy = correct / total
    return f"{accuracy:.4f}"


def run_pipeline():
    assert os.path.lexists(SCRIPT), f"File {SCRIPT} is missing."
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} must be a regular Bash script."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."

    syntax = subprocess.run(
        ['/bin/bash', '-n', SCRIPT],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert syntax.returncode == 0, f"Invalid Bash script:\n{syntax.stderr}"

    for path in OUTPUTS:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = {
        'PATH': ALLOWED_BIN,
        'HOME': '/home/user',
        'LANG': 'C',
        'LC_ALL': 'C',
    }
    user = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    result = subprocess.run(
        ['/bin/bash', SCRIPT],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
        preexec_fn=demote,
    )
    assert result.returncode == 0, (
        f"Pipeline exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_current_outputs():
    events = get_events_data()
    indices = get_bootstrap_indices()
    expected = [
        compute_phase1_truth(events),
        compute_phase2_truth(events, indices),
        compute_phase3_truth(events),
    ]
    for path, wanted in zip(OUTPUTS, expected):
        assert os.path.exists(path), f"File {path} is missing."
        with open(path, 'r') as f:
            actual = f.read()
        assert actual.strip() == wanted.strip(), (
            f"Contents of {path} do not match expected.\n"
            f"Expected: {wanted.strip()}\nActual: {actual.strip()}"
        )


def test_00_pipeline_exists_and_runs():
    run_pipeline()


def test_phase1_aggregates():
    file_path = '/home/user/phase1_aggregates.csv'
    assert os.path.exists(file_path), f"File {file_path} is missing."

    events = get_events_data()
    expected_content = compute_phase1_truth(events)

    with open(file_path, 'r') as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), \
        f"Contents of {file_path} do not match expected.\nExpected:\n{expected_content.strip()}\nActual:\n{actual_content.strip()}"


def test_phase2_ci():
    file_path = '/home/user/phase2_ci.txt'
    assert os.path.exists(file_path), f"File {file_path} is missing."

    events = get_events_data()
    indices_list = get_bootstrap_indices()
    expected_content = compute_phase2_truth(events, indices_list)

    with open(file_path, 'r') as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), \
        f"Contents of {file_path} do not match expected.\nExpected: {expected_content.strip()}\nActual: {actual_content.strip()}"


def test_phase3_accuracy():
    file_path = '/home/user/phase3_accuracy.txt'
    assert os.path.exists(file_path), f"File {file_path} is missing."

    events = get_events_data()
    expected_content = compute_phase3_truth(events)

    with open(file_path, 'r') as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), \
        f"Contents of {file_path} do not match expected.\nExpected: {expected_content.strip()}\nActual: {actual_content.strip()}"


def test_pipeline_recomputes_from_changed_inputs():
    original_events = open(EVENTS, 'rb').read()
    original_indices = open(INDICES, 'rb').read()
    seed = secrets.randbelow(10**9) + 1
    cats = ['A', 'B', 'C']
    cat_values = {
        'A': 13 + seed % 19,
        'B': 47 + seed % 23,
        'C': 78 + seed % 17,
    }

    try:
        with open(EVENTS, 'w') as f:
            f.write('id,category,value,label\n')
            for i in range(1, 1001):
                cat = cats[(i + seed) % 3]
                value = cat_values[cat]
                label = 1 if ((i * 17 + seed + cats.index(cat) * 11) % 13) < (3 + cats.index(cat) * 3) else 0
                f.write(f'{i},{cat},{value},{label}\n')

        with open(INDICES, 'w') as f:
            for sample in range(100):
                idx = ((seed * 37 + sample * 97) % 1000) + 1
                f.write(','.join([str(idx)] * 1000) + '\n')

        os.chmod(EVENTS, 0o644)
        os.chmod(INDICES, 0o644)
        run_pipeline()
        assert_current_outputs()
    finally:
        with open(EVENTS, 'wb') as f:
            f.write(original_events)
        with open(INDICES, 'wb') as f:
            f.write(original_indices)
        os.chmod(EVENTS, 0o644)
        os.chmod(INDICES, 0o644)
        run_pipeline()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
