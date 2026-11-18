import sys
import struct

def run_oracle():
    magic = b"DOC_BETA_99"
    data = sys.stdin.buffer.read()
    idx = 0
    while True:
        idx = data.find(magic, idx)
        if idx == -1:
            break

        if idx + len(magic) + 4 > len(data):
            break

        len_bytes = data[idx + len(magic) : idx + len(magic) + 4]
        payload_len = struct.unpack("<I", len_bytes)[0]

        start_payload = idx + len(magic) + 4
        if start_payload + payload_len > len(data):
            idx += 1
            continue

        payload_bytes = data[start_payload : start_payload + payload_len]
        try:
            text = payload_bytes.decode('utf-8')
            text = text.replace("DRAFT", "FINAL").rstrip()
            print(text)
        except UnicodeDecodeError:
            pass

        idx = start_payload + payload_len

if __name__ == "__main__":
    run_oracle()
