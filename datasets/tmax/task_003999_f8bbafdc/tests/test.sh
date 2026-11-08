#!/bin/bash
set -u
mkdir -p /logs/verifier

ORACLE=/app/math_oracle
HIDDEN_DIR=/root/.verifier_oracle
HIDDEN_ORACLE="$HIDDEN_DIR/math_oracle"

restore_oracle() {
    if [ -e "$HIDDEN_ORACLE" ]; then
        mv "$HIDDEN_ORACLE" "$ORACLE" 2>/dev/null || true
    fi
}
trap restore_oracle EXIT

if [ ! -f "$ORACLE" ] || [ ! -x "$ORACLE" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

ORACLE_SHA=$(sha256sum "$ORACLE" | awk '{print $1}')
mkdir -p "$HIDDEN_DIR"
chmod 700 "$HIDDEN_DIR"
mv "$ORACLE" "$HIDDEN_ORACLE"
chmod 700 "$HIDDEN_ORACLE"

cat << 'REF_EOF' > /tmp/verifier_reference.cpp
#include <iostream>
#include <string>
#include <cctype>
#include <cstdlib>

class Parser {
    const char* p;
    double parseFactor() {
        while (isspace((unsigned char)*p)) p++;
        int sign = 1;
        if (*p == '-') { sign = -1; p++; }
        else if (*p == '+') { p++; }
        while (isspace((unsigned char)*p)) p++;
        double val = 0;
        if (*p == '(') {
            p++;
            val = parseExpr();
            while (isspace((unsigned char)*p)) p++;
            if (*p == ')') p++;
        } else {
            char* end;
            val = std::strtod(p, &end);
            p = end;
        }
        return sign * val;
    }
    double parseTerm() {
        double val = parseFactor();
        while (true) {
            while (isspace((unsigned char)*p)) p++;
            if (*p == '*') { p++; val *= parseFactor(); }
            else if (*p == '/') { p++; val /= parseFactor(); }
            else break;
        }
        return val;
    }
public:
    double parseExpr() {
        double val = parseTerm();
        while (true) {
            while (isspace((unsigned char)*p)) p++;
            if (*p == '+') { p++; val += parseTerm(); }
            else if (*p == '-') { p++; val -= parseTerm(); }
            else break;
        }
        return val;
    }
    double parse(const char* str) { p = str; return parseExpr(); }
};

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    Parser parser;
    std::cout << parser.parse(argv[1]) << std::endl;
    return 0;
}
REF_EOF

if ! g++ -O2 /tmp/verifier_reference.cpp -o /tmp/verifier_reference; then
    rm -f /tmp/verifier_reference.cpp /tmp/verifier_reference
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
rm -f /tmp/verifier_reference.cpp
chmod 700 /tmp/verifier_reference

export ORACLE_SHA
cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import math
import os
import random
import stat
import subprocess
import pytest

AGENT_BIN = "/home/user/final_evaluator"
SOURCE = "/home/user/src/math_evaluator.cpp"
HEADER = "/home/user/src/expr_parser.h"
REBUILT_BIN = "/tmp/rebuilt_evaluator"
REFERENCE_BIN = "/tmp/verifier_reference"

def generate_expr(depth=0):
    if depth > 3 or random.random() < 0.3:
        return str(random.randint(-100, 100))
    op = random.choice(['+', '-', '*', '/'])
    left = generate_expr(depth + 1)
    right = generate_expr(depth + 1)
    if op == '/' and right == '0':
        right = '1'
    fmt = random.choice(["{} {} {}", "({} {} {})", "{}{}{}", "({}{}{})"])
    return fmt.format(left, op, right)

def drop_to_user():
    import pwd
    pw = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(pw.pw_gid)
    os.setuid(pw.pw_uid)

def run_unprivileged(path, expr):
    return subprocess.check_output(
        [path, expr],
        stderr=subprocess.DEVNULL,
        timeout=1,
        preexec_fn=drop_to_user,
        env={"PATH": "/usr/bin:/bin", "HOME": "/home/user"},
    ).decode().strip()

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

random.seed(42)
EXPRESSIONS = [generate_expr() for _ in range(1000)]
EXPECTED = []
for expr in EXPRESSIONS:
    EXPECTED.append(subprocess.check_output(
        [REFERENCE_BIN, expr], stderr=subprocess.DEVNULL, timeout=1
    ).decode().strip())
os.unlink(REFERENCE_BIN)

def test_final_evaluator_exists_and_executable():
    st = os.lstat(AGENT_BIN)
    assert stat.S_ISREG(st.st_mode), f"{AGENT_BIN} must be a regular file, not a symlink or wrapper path"
    assert os.access(AGENT_BIN, os.X_OK), f"{AGENT_BIN} is not executable"
    assert sha256(AGENT_BIN) != os.environ["ORACLE_SHA"], "Final evaluator is a byte-identical copy of the oracle"

def test_recovered_header_and_source_build():
    assert os.path.isfile(HEADER), f"Recovered header missing: {HEADER}"
    assert os.path.isfile(SOURCE), f"Evaluator source missing: {SOURCE}"
    result = subprocess.run(
        ["g++", "-O2", "-std=c++17", SOURCE, "-o", REBUILT_BIN],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, "Submitted source does not compile:\n" + result.stderr
    assert os.path.isfile(REBUILT_BIN) and os.access(REBUILT_BIN, os.X_OK)

def accuracy(path):
    correct = 0
    for expr, ref_out in zip(EXPRESSIONS, EXPECTED):
        try:
            agent_out = run_unprivileged(path, expr)
            if math.isclose(float(ref_out), float(agent_out), rel_tol=1e-6, abs_tol=1e-6):
                correct += 1
        except Exception:
            pass
    return correct / len(EXPRESSIONS)

def test_evaluator_accuracy():
    score = accuracy(AGENT_BIN)
    assert score >= 0.99, f"Accuracy {score} is below the threshold of 0.99"

def test_rebuilt_source_accuracy():
    score = accuracy(REBUILT_BIN)
    assert score >= 0.99, f"Rebuilt source accuracy {score} is below the threshold of 0.99"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
