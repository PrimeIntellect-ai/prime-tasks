#!/bin/bash
set -e
mkdir -p /logs/verifier
# Ensure every failure path still produces a score.
echo "0" > /logs/verifier/reward.txt

# Restore the immutable input from the task setup so a modified CSV cannot
# redefine the expected result.
cat << 'CSV_EOF' > /home/user/equations.csv
id,expression
1,2x + 3 = 7
2,y = m*x + c
3,a^2 + b^2 = c^2
4,f(x) = 100 / (x - 5)
5,loss = (y - pred)^2
CSV_EOF

# The requested C++ artifact must exist, compile, and actually generate output.
test -f /home/user/tokenizer.cpp
test -s /home/user/tokenizer.cpp
g++ -std=c++17 /home/user/tokenizer.cpp -o /tmp/tokenizer_under_test
rm -f /home/user/tokenized_dataset.tsv
(cd /home/user && timeout 10 /tmp/tokenizer_under_test)
test -f /home/user/tokenized_dataset.tsv

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv


def tokenize(expression):
    tokens = []
    i = 0
    while i < len(expression):
        char = expression[i]
        if char.isspace():
            i += 1
            continue
        if char in "+-*/=^()":
            tokens.append(char)
            i += 1
        elif char.isalnum():
            start = i
            while i < len(expression) and expression[i].isalnum():
                i += 1
            tokens.append(expression[start:i])
        else:
            tokens.append(char)
            i += 1
    return tokens


def test_tokenized_dataset():
    input_csv = "/home/user/equations.csv"
    output_tsv = "/home/user/tokenized_dataset.tsv"

    assert os.path.isfile(input_csv), f"Input file {input_csv} is missing."
    assert os.path.isfile(output_tsv), f"Output file {output_tsv} is missing."

    expected_rows = []
    total_equations = 0
    total_tokens = 0

    with open(input_csv, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            if not row or len(row) < 2:
                continue
            eq_id = row[0]
            expression = ",".join(row[1:])
            tokens = tokenize(expression)
            expected_rows.append(f"{eq_id}\t{' '.join(tokens)}\t{len(tokens)}")
            total_equations += 1
            total_tokens += len(tokens)

    with open(output_tsv, "r", encoding="utf-8") as f:
        actual_lines = [line.strip("\r\n") for line in f if line.strip("\r\n")]

    assert len(actual_lines) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows in TSV, got {len(actual_lines)}."
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_rows)):
        assert actual == expected, \
            f"Row {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"


def test_experiment_log():
    input_csv = "/home/user/equations.csv"
    log_file = "/home/user/experiment_log.txt"

    assert os.path.isfile(input_csv), f"Input file {input_csv} is missing."
    assert os.path.isfile(log_file), f"Log file {log_file} is missing."

    total_equations = 0
    total_tokens = 0
    with open(input_csv, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            if not row or len(row) < 2:
                continue
            expression = ",".join(row[1:])
            total_equations += 1
            total_tokens += len(tokenize(expression))

    expected_log_line = f"Run_Tokens: {total_equations},{total_tokens}"
    with open(log_file, "r", encoding="utf-8") as f:
        lines = [line.strip("\r\n") for line in f if line.strip("\r\n")]

    assert len(lines) > 0, f"Log file {log_file} is empty."
    actual_last_line = lines[-1]
    assert actual_last_line == expected_log_line, \
        f"Last line of log file mismatch.\nExpected: {expected_log_line}\nActual:   {actual_last_line}"
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

# Exercise the compiled program on fresh, unpredictable valid input so a
# submission that merely hard-codes the setup artifacts cannot pass.
python3 << 'PY_EOF'
import csv
import json
import secrets
import string

letters = string.ascii_letters

def word(n):
    return ''.join(secrets.choice(letters) for _ in range(n))

def number():
    return str(secrets.randbelow(9000) + 1000)

expressions = [
    f"{word(4)}{number()} + {number()} = ({word(3)} - {number()})^2",
    f"{word(2)}({word(5)}) = {number()} / ({word(3)} + {number()})",
    f"({word(3)}+{number()})*({word(4)}-{number()})",
    f"{word(6)} = {word(3)}*{word(4)} + {number()}",
    f"{number()}^{word(2)} / ({number()} - {word(5)})",
    f"(({word(3)})) = {number()}",
]
rows = [[str(100 + i), expression] for i, expression in enumerate(expressions)]
with open('/home/user/equations.csv', 'w', encoding='utf-8', newline='') as f:
    writer = csv.writer(f, lineterminator='\n')
    writer.writerow(['id', 'expression'])
    writer.writerows(rows)
with open('/tmp/dynamic_rows.json', 'w', encoding='utf-8') as f:
    json.dump(rows, f)
PY_EOF

rm -f /home/user/tokenized_dataset.tsv
(cd /home/user && timeout 10 /tmp/tokenizer_under_test)

python3 << 'PY_EOF'
import json
import os

operators = "+-*/=^()"

def tokenize(expression):
    tokens = []
    i = 0
    while i < len(expression):
        char = expression[i]
        if char.isspace():
            i += 1
        elif char in operators:
            tokens.append(char)
            i += 1
        elif ('a' <= char <= 'z') or ('A' <= char <= 'Z') or ('0' <= char <= '9'):
            start = i
            while i < len(expression) and (
                ('a' <= expression[i] <= 'z') or
                ('A' <= expression[i] <= 'Z') or
                ('0' <= expression[i] <= '9')
            ):
                i += 1
            tokens.append(expression[start:i])
        else:
            raise AssertionError(f"Unexpected generated character: {char!r}")
    return tokens

assert os.path.isfile('/home/user/tokenized_dataset.tsv'), \
    'Compiled tokenizer did not generate tokenized_dataset.tsv for fresh input.'
with open('/tmp/dynamic_rows.json', encoding='utf-8') as f:
    rows = json.load(f)
expected = []
for eq_id, expression in rows:
    tokens = tokenize(expression)
    expected.append(f"{eq_id}\t{' '.join(tokens)}\t{len(tokens)}")
with open('/home/user/tokenized_dataset.tsv', encoding='utf-8') as f:
    actual = [line.rstrip('\r\n') for line in f]
assert actual == expected, \
    f"Compiled tokenizer failed fresh-input test.\nExpected: {expected!r}\nActual: {actual!r}"
PY_EOF

echo "1" > /logs/verifier/reward.txt
