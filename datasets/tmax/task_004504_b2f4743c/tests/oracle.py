import sys, binascii, hmac, hashlib
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad

def main():
    if len(sys.argv) != 2:
        print("ERROR: INVALID_FORMAT")
        sys.exit(1)

    hex_str = sys.argv[1]
    try:
        raw_bytes = binascii.unhexlify(hex_str)
    except:
        print("ERROR: INVALID_FORMAT")
        sys.exit(1)

    if len(raw_bytes) < 64:
        print("ERROR: INVALID_FORMAT")
        sys.exit(1)

    iv = raw_bytes[0:16]
    provided_mac = raw_bytes[16:48]
    ciphertext = raw_bytes[48:]

    key = b'CorpPolicySecuXY'

    expected_mac = hmac.new(key, iv + ciphertext, hashlib.sha256).digest()
    if not hmac.compare_digest(expected_mac, provided_mac):
        print("ERROR: INTEGRITY_VIOLATION")
        sys.exit(2)

    try:
        cipher = AES.new(key, AES.MODE_CBC, iv)
        plaintext = unpad(cipher.decrypt(ciphertext), AES.block_size)
        sys.stdout.buffer.write(plaintext)
        sys.exit(0)
    except Exception:
        print("ERROR: DECRYPTION_FAILED")
        sys.exit(3)

if __name__ == '__main__':
    main()
