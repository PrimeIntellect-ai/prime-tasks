#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/projects_raw/module1/submodule
    mkdir -p /home/user/projects_raw/module2
    mkdir -p /home/user/projects_raw/docs

    echo "print('main')" > /home/user/projects_raw/main.py
    echo "print('utils')" > /home/user/projects_raw/module1/utils.py
    echo "print('auth')" > /home/user/projects_raw/module1/submodule/auth.py
    echo "print('db')" > /home/user/projects_raw/module2/db.py

    echo "readme" > /home/user/projects_raw/docs/readme.md
    echo "todo" > /home/user/projects_raw/todo.txt

    chmod -R 777 /home/user
