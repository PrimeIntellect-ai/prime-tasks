import sys
import json
import base64

def process():
    input_data = sys.stdin.read()
    if not input_data.strip():
        return
    arr = json.loads(input_data)
    out = {}
    for i, x in enumerate(arr):
        val = (x ** 2) - (3 * x)
        if val < 0:
            val = -val
        # 32-bit big-endian unsigned
        b = val.to_bytes(4, byteorder='big', signed=False)
        b64 = base64.b64encode(b).decode('ascii')
        out[str(i)] = b64
    print(json.dumps(out, separators=(',', ':')))

if __name__ == '__main__':
    process()
