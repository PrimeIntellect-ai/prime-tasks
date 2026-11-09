#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang jq
pip3 install pytest

mkdir -p /home/user/polyglot-eval/go_src
mkdir -p /home/user/polyglot-eval/src
mkdir -p /home/user/polyglot-eval/tests

cat << 'EOF' > /home/user/polyglot-eval/ci_config.json
{
  "go_bench_cmd": "cd go_src && go test -bench=.",
  "py_test_cmd": "PYTHONPATH=src python3 -m unittest discover -s tests"
}
EOF

cat << 'EOF' > /home/user/polyglot-eval/go_src/eval.go
package eval
func Evaluate(expr string) int {
    // Dummy implementation
    return 42
}
EOF

cat << 'EOF' > /home/user/polyglot-eval/go_src/eval_test.go
package eval
import "testing"
func BenchmarkEvaluate(b *testing.B) {
    for i := 0; i < b.N; i++ {
        Evaluate("2 + 2")
    }
}
EOF

cd /home/user/polyglot-eval/go_src && go mod init polyglot-eval

cat << 'EOF' > /home/user/polyglot-eval/src/config.py
settings = {
    "strict_mode": True
}
EOF

cat << 'EOF' > /home/user/polyglot-eval/src/parser.py
from config import settings

def parse(data):
    if settings["strict_mode"]:
        if "error" in data:
            raise ValueError("Strict mode error")
    return True
EOF

cat << 'EOF' > /home/user/polyglot-eval/tests/test_a_parser.py
import unittest
from parser import parse

class TestParser(unittest.TestCase):
    def test_parse_strict(self):
        # This will fail if test_b_config runs first and mutates settings without resetting
        with self.assertRaises(ValueError):
            parse({"error": "bad data"})
EOF

cat << 'EOF' > /home/user/polyglot-eval/tests/test_b_config.py
import unittest
import config

class TestConfig(unittest.TestCase):
    def test_disable_strict_mode(self):
        config.settings["strict_mode"] = False
        self.assertFalse(config.settings["strict_mode"])
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
