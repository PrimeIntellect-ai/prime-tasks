#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Generate the raw_reviews.csv file with mixed valid/invalid data, NFD unicode, and bad UTF-8
    python3 -c '
import csv

with open("raw_reviews.csv", "wb") as f:
    # 1. Valid row
    f.write(b"A1B2C3D4,en,5,Great product!\n")

    # 2. Invalid ID length (7 chars)
    f.write(b"A1B2C3D,en,5,Short ID\n")

    # 3. Invalid language (uppercase)
    f.write(b"A1B2C3D5,EN,5,Uppercase lang\n")

    # 4. Invalid rating (6)
    f.write(b"A1B2C3D6,fr,6,Bad rating\n")

    # 5. Invalid UTF-8 byte (\xff) in text
    f.write(b"A1B2C3D7,es,4,Me gusta \xff el producto\n")

    # 6. Unnormalized Unicode (NFD: e + \u0301) -> should become NFC (é = \u00e9)
    f.write("A1B2C3D8,fr,3,Tre\u0301s bien\n".encode("utf-8"))

    # 7. Empty text after trimming
    f.write(b"A1B2C3D9,ja,1,   \n")

    # 8. Another valid row with mixed unicode
    f.write("X9Y8Z7W6,ko,2,  \u1100\u1161\u11a8  \n".encode("utf-8")) # NFD Hangul -> NFC "각"
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
