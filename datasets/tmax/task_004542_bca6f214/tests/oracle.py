import sys
import math

def main():
    ALPHA = 0.125
    BETA = 0.015625
    data = sys.stdin.read().split()
    if not data:
        print(0.0)
        return
    inputs = [float(x) for x in data]
    res = math.fsum(v * ALPHA - (v**2) * BETA for v in inputs)
    print(repr(res))

if __name__ == '__main__':
    main()
