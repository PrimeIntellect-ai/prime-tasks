#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/raw_data

echo "1,ALICE SMITH,(555) 111-2222,12/05/2019
2,bob jones,555-333-4444,01/15/2020
3,RENÉE DUPONT,+1 555 999 0000,05/20/2021" | iconv -f UTF-8 -t ISO-8859-1 > /home/user/raw_data/export_a.csv

echo "4,CHLOË GRACE,555.444.5555,11/01/2018
5,dave brown,555 666 7777,03/10/2020" | iconv -f UTF-8 -t WINDOWS-1252 > /home/user/raw_data/export_b.csv

echo "6,Eve White,555-777-8888,08/22/2022
7,françois leblanc,(555)888-9999,02/28/2019" > /home/user/raw_data/export_c.csv

chmod -R 777 /home/user
