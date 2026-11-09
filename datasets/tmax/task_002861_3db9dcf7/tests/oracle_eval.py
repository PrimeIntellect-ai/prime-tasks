import sys
import math

def evaluate(expr):
    tokens = expr.split()
    stack = []
    min_bound = -9999
    max_bound = 9999

    i = 0
    while i < len(tokens):
        token = tokens[i]
        if token == 'MIN':
            i += 1
            if i >= len(tokens): return "ERROR"
            try: min_bound = int(tokens[i])
            except ValueError: return "ERROR"
        elif token == 'MAX':
            i += 1
            if i >= len(tokens): return "ERROR"
            try: max_bound = int(tokens[i])
            except ValueError: return "ERROR"
        elif token in ('+', '-', '*', '/'):
            if len(stack) < 2: return "ERROR"
            b = stack.pop()
            a = stack.pop()
            if token == '+': stack.append(a + b)
            elif token == '-': stack.append(a - b)
            elif token == '*': stack.append(a * b)
            elif token == '/':
                if b == 0: return "ERROR"
                stack.append(int(a / b))
        else:
            try: stack.append(int(token))
            except ValueError: return "ERROR"
        i += 1

    if len(stack) != 1: return "ERROR"

    res = stack[0]
    if res > max_bound: res = max_bound
    if res < min_bound: res = min_bound
    return str(res)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("ERROR")
    else:
        print(evaluate(sys.argv[1]))
