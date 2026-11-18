#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest grpcio grpcio-tools hypothesis

mkdir -p /app
cat << 'EOF' > /app/legacy_evaluator
#!/usr/bin/env python3
import sys, json, re

def evaluate(expr, data):
    def repl(match):
        var = match.group(0)
        # Handle negative numbers properly by wrapping in parentheses
        val = data.get(var, 0)
        return f"({val})" if val < 0 else str(val)

    expr = re.sub(r'[A-Z]', repl, expr)
    return int(eval(expr))

def main():
    try:
        input_str = sys.stdin.read()
        if not input_str.strip():
            return
        req = json.loads(input_str)
        res = evaluate(req['expr'], req.get('data', {}))
        print(json.dumps({"result": res}))
    except Exception as e:
        print(json.dumps({"error": str(e)}))

if __name__ == '__main__':
    main()
EOF
chmod +x /app/legacy_evaluator

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
