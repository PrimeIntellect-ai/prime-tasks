#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import secrets
import sqlite3
import subprocess
import sys

PROJECT = '/home/user/ml_project'
SCRIPT = os.path.join(PROJECT, 'train_model.py')
DATABASE = os.path.join(PROJECT, 'data.db')
DIAGNOSTICS = '/home/user/diagnostics.log'
TRACE_FILE = '/tmp/train_model_sql_trace.jsonl'

# Replace the database with fresh verifier-generated inputs so a fabricated
# diagnostics.log cannot satisfy the behavioral checks.
rng = secrets.SystemRandom()
clean_data = []
for _ in range(7):
    x = rng.uniform(0.5, 1.8)
    clean_data.append((x, 1.75 * x + 0.3))

all_data = list(clean_data)
all_data.insert(2, (rng.uniform(4.0, 8.0), -999.0))
all_data.insert(6, (rng.uniform(9.0, 14.0), -999.0))

if os.path.exists(DATABASE):
    os.remove(DATABASE)
conn = sqlite3.connect(DATABASE)
conn.execute('CREATE TABLE training_data (feature REAL, target REAL)')
conn.executemany('INSERT INTO training_data VALUES (?, ?)', all_data)
conn.commit()
conn.close()


def expected_loss(rows):
    w, b = 0.0, 0.0
    lr = 0.01
    for _ in range(100):
        total_loss = 0.0
        for x, y in rows:
            pred = w * x + b
            error = pred - y
            total_loss += error ** 2
            w -= lr * error * x
            b -= lr * error
        total_loss /= len(rows)
    return total_loss


EXPECTED_LOSS = expected_loss(clean_data)


def test_db_secret_file():
    path = '/home/user/db_secret.txt'
    assert os.path.isfile(path), f"File {path} does not exist. You need to create it."
    with open(path, 'r') as f:
        content = f.read().strip()
    assert content == 'auth_token_xyz987', "The file db_secret.txt does not contain the correct recovered password."


def test_train_model_sql_query():
    path = '/home/user/ml_project/train_model.py'
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, 'r') as f:
        content = f.read()

    # Preserve the original assertion.
    content_upper = content.upper()
    assert 'WHERE' in content_upper and '999' in content, "The SQL query in train_model.py does not appear to filter out the corrupted rows (target = -999.0)."


def test_train_model_learning_rate():
    path = '/home/user/ml_project/train_model.py'
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, 'r') as f:
        content = f.read()

    # Preserve the original assertion.
    assert '0.01' in content, "The learning rate in train_model.py does not appear to be updated to 0.01."

    # Also require an actual lr assignment in train(), rather than a comment.
    tree = ast.parse(content, filename=path)
    train_functions = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == 'train']
    assert train_functions, "train_model.py does not define train()."
    lr_assignments = []
    for node in ast.walk(train_functions[0]):
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'lr' for t in node.targets):
            lr_assignments.append(node.value)
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.target.id == 'lr':
            lr_assignments.append(node.value)
    assert any(isinstance(v, ast.Constant) and isinstance(v.value, (int, float)) and float(v.value) == 0.01 for v in lr_assignments), \
        "train() does not assign the learning rate to 0.01."


def test_run_training_pipeline():
    # Trace the SQL that the submitted program actually executes.
    hook_dir = '/tmp/verifier_sitecustomize'
    os.makedirs(hook_dir, exist_ok=True)
    with open(os.path.join(hook_dir, 'sitecustomize.py'), 'w') as f:
        f.write(r'''import json
import os
import sqlite3
_original_connect = sqlite3.connect

def _connect(*args, **kwargs):
    connection = _original_connect(*args, **kwargs)
    trace_path = os.environ.get('VERIFIER_SQL_TRACE')
    if trace_path:
        def record(statement):
            with open(trace_path, 'a') as out:
                out.write(json.dumps(statement) + '\n')
        connection.set_trace_callback(record)
    return connection

sqlite3.connect = _connect
''')

    for path in (DIAGNOSTICS, TRACE_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    with open('/home/user/db_secret.txt', 'r') as f:
        password = f.read().strip()
    env = os.environ.copy()
    env['DB_PASSWORD'] = password
    env['VERIFIER_SQL_TRACE'] = TRACE_FILE
    env['PYTHONPATH'] = hook_dir + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')

    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd=PROJECT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"train_model.py failed when executed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(TRACE_FILE), "The executed program did not issue a traceable database query."

    with open(TRACE_FILE) as f:
        statements = [json.loads(line) for line in f if line.strip()]
    selects = [s for s in statements if s.lstrip().upper().startswith('SELECT') and 'TRAINING_DATA' in s.upper()]
    assert selects, "train_model.py did not execute a SELECT query against training_data."

    # Execute the actual traced SQL against an independent copy and require it
    # to return all valid rows while excluding both corrupted rows.
    query_filters_correctly = False
    for statement in selects:
        check = sqlite3.connect(':memory:')
        try:
            check.execute('CREATE TABLE training_data (feature REAL, target REAL)')
            check.executemany('INSERT INTO training_data VALUES (?, ?)', all_data)
            rows = check.execute(statement).fetchall()
            if rows == clean_data:
                query_filters_correctly = True
                break
        except sqlite3.Error:
            pass
        finally:
            check.close()
    assert query_filters_correctly, "The SQL query actually executed by train_model.py does not exclude target = -999.0 rows correctly."


def test_diagnostics_log():
    path = '/home/user/diagnostics.log'
    assert os.path.isfile(path), f"File {path} does not exist. Did you run the script successfully?"
    with open(path, 'r') as f:
        content = f.read().strip()

    assert content.startswith('Loss:'), "diagnostics.log does not contain the expected 'Loss: ' prefix."

    try:
        loss_str = content.split('Loss:')[1].strip()
        loss_val = float(loss_str)
    except (IndexError, ValueError):
        assert False, "Could not parse a valid numerical loss value from diagnostics.log."

    assert loss_val < 1.0, f"The loss value ({loss_val}) is too high. The model did not converge properly."
    assert math.isfinite(loss_val), "The reported loss is not finite."

    # The supplied implementation writes four decimal places. Compare against
    # an independently calculated result for the fresh verifier data.
    expected_reported = float(f'{EXPECTED_LOSS:.4f}')
    assert abs(loss_val - expected_reported) <= 0.00005, \
        f"diagnostics.log reports {loss_val}, but executing the required gradient descent should produce {expected_reported}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
