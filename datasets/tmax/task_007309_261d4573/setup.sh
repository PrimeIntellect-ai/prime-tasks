#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/parser.py
class RPNParser:
    stack = []

    def parse_and_evaluate(self, expression):
        for token in expression.split():
            if token.isdigit():
                self.stack.append(int(token))
            else:
                b = self.stack.pop()
                a = self.stack.pop()
                if token == '+':
                    self.stack.append(a + b)
                elif token == '*':
                    self.stack.append(a * b)
        return self.stack.pop()
EOF

    cat << 'EOF' > /home/user/test_parser.py
import unittest
from unittest.mock import patch, mock_open
from parser import RPNParser

class TestRPNParser(unittest.TestCase):
    def test_multiple_instances(self):
        p1 = RPNParser()
        self.assertEqual(p1.parse_and_evaluate("3 4 +"), 7)
        p2 = RPNParser()
        self.assertEqual(p2.parse_and_evaluate("5 6 *"), 30)

    def test_file_read(self):
        pass # TODO: implement this test
EOF

    chmod -R 777 /home/user
