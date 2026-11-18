#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'DATA' > /home/user/config_stream.csv
1612345678,alice,US,max_conn,MOD,100
1612345679,bob,US,timeout,ADD,30
1500000000,charlie,US,retry,MOD,5
1612345680,dave,US,port,DEL,
1612345681,eve,EU,host,MOD,localhost
1612345682,frank,EU,user,UPDATE,admin
1612345683,grace,E,pass,MOD,secret
1612345684,heidi,EU,ssl,ADD,true
1612345685,,AP,cache,MOD,1
1612345686,judy,AP,log,MOD,debug
DATA

    chmod -R 777 /home/user
