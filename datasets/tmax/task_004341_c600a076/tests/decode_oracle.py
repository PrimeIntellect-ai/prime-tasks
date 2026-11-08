import sys

SECRET_KEY = "diag_enc_9942a_prod"

def decode_bits(bits):
    if len(bits) % 8 != 0:
        bits = bits + "0" * (8 - (len(bits) % 8))

    chars = []
    for i in range(0, len(bits), 8):
        byte_str = bits[i:i+8]
        if byte_str:
            chars.append(chr(int(byte_str, 2)))

    return "".join(chars) + SECRET_KEY

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    print(decode_bits(sys.argv[1]), end="")
