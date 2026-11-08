#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/input
    mkdir -p /home/user/output
    mkdir -p /home/user/loc_pipeline

    python3 -c '
import os
with open("/home/user/input/raw_translations.csv", "wb") as f:
    f.write(b"EntryID,Context,SourceText,Translation\n")
    f.write(b"1,ui.button,Save,Enregistrer\n")
    f.write(b"2,ui.alert,\"Error occurred.\r\nPlease retry.\",\"Erreur.\r\nR\xc3\xa9essayer.\"\n")
    f.write(b"3,ui.button,Save,Guardar\n")
    f.write(b"4,ui.msg,Bad \xff Encoding,Mauvais encodage\n")
    f.write(b"5,ui.cafe,Cafe\xcc\x81,Cafeteria\n")
    f.write(b"6,ui.cafe,Cafe\xcc\x81,Bistro\n")
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
