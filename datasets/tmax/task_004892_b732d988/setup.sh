#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest pyinstaller

    # Create the Python script for the oracle
    cat << 'EOF' > /tmp/legacy_calc.py
#!/usr/bin/env python3
import sys, json

def eval_expr(expr, ctx):
    tokens = []
    i = 0
    while i < len(expr):
        if expr[i].isspace(): i+=1
        elif expr[i] in '+-*/()': tokens.append(expr[i]); i+=1
        elif expr[i].isalpha():
            start = i
            while i < len(expr) and expr[i].isalpha(): i+=1
            tokens.append(expr[start:i])
        elif expr[i].isdigit():
            start = i
            while i < len(expr) and expr[i].isdigit(): i+=1
            tokens.append(int(expr[start:i]))
        else:
            raise ValueError("syntax error")

    def parse(tokens):
        out = []
        ops = []
        for t in tokens:
            if isinstance(t, int) or (isinstance(t, str) and t.isalpha()):
                out.append(t)
            elif t in '+-*/':
                while ops and ops[-1] != '(':
                    out.append(ops.pop())
                ops.append(t)
            elif t == '(':
                ops.append(t)
            elif t == ')':
                while ops and ops[-1] != '(':
                    out.append(ops.pop())
                if not ops: raise ValueError("syntax error")
                ops.pop()
        while ops:
            if ops[-1] == '(': raise ValueError("syntax error")
            out.append(ops.pop())
        return out

    postfix = parse(tokens)
    if not postfix: raise ValueError("syntax error")

    stack = []
    for t in postfix:
        if isinstance(t, int):
            stack.append(t)
        elif isinstance(t, str) and t.isalpha():
            if not isinstance(ctx, dict) or t not in ctx: raise KeyError("undefined variable")
            stack.append(ctx[t])
        else:
            if len(stack) < 2: raise ValueError("syntax error")
            b = stack.pop()
            a = stack.pop()
            if t == '+': stack.append(a + b)
            elif t == '-': stack.append(a - b)
            elif t == '*': stack.append(a * b)
            elif t == '/':
                if b == 0: raise ZeroDivisionError("division by zero")
                stack.append(a // b)
    if len(stack) != 1: raise ValueError("syntax error")
    return stack[0]

def main():
    try:
        data = sys.stdin.read()
        if not data: return
        try: req = json.loads(data)
        except:
            print(json.dumps({"status":"error","reason":"invalid json"}, separators=(',', ':')))
            return
        if not isinstance(req, dict) or "expression" not in req or "context" not in req:
            print(json.dumps({"status":"error","reason":"invalid json"}, separators=(',', ':')))
            return

        try:
            res = eval_expr(req["expression"], req["context"])
            print(json.dumps({"status":"success","value":res}, separators=(',', ':')))
        except ZeroDivisionError:
            print(json.dumps({"status":"error","reason":"division by zero"}, separators=(',', ':')))
        except KeyError:
            print(json.dumps({"status":"error","reason":"undefined variable"}, separators=(',', ':')))
        except ValueError:
            print(json.dumps({"status":"error","reason":"syntax error"}, separators=(',', ':')))
        except Exception:
            print(json.dumps({"status":"error","reason":"syntax error"}, separators=(',', ':')))

    except Exception:
        pass

if __name__ == '__main__':
    main()
EOF

    # Compile to a binary to simulate a stripped executable
    cd /tmp
    pyinstaller --onefile legacy_calc.py

    mkdir -p /app
    cp dist/legacy_calc /app/legacy_calc
    chmod +x /app/legacy_calc

    # Cleanup
    rm -rf /tmp/legacy_calc* /tmp/build /tmp/dist /tmp/__pycache__

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
