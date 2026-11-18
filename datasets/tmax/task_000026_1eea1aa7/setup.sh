#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

data = [
    {"timestamp": "2023-11-01 10:05:00", "msg_en": "System start", "msg_es": "Inicio\ndel sistema", "msg_zh": "系统启动", "msg_ru": "Запуск системы"},
    {"timestamp": "2023-11-01 10:12:00", "msg_en": "User login", "msg_es": "", "msg_zh": "用户登录", "msg_ru": "Вход пользователя"},
    {"timestamp": "2023-11-01 10:18:00", "msg_en": "Data load\nsuccess", "msg_es": "Carga de datos", "msg_zh": "", "msg_ru": ""},
    {"timestamp": "2023-11-01 10:35:00", "msg_en": "Error 404", "msg_es": "Error\n404", "msg_zh": "错误404", "msg_ru": "Ошибка 404"},
    {"timestamp": "2023-11-01 10:40:00", "msg_en": "Retry", "msg_es": "Reintentar", "msg_zh": "", "msg_ru": "Повторить\nпопытку"},
    {"timestamp": "2023-11-01 11:05:00", "msg_en": "Timeout", "msg_es": "Tiempo agotado", "msg_zh": "超时", "msg_ru": ""},
]

df = pd.DataFrame(data)
df.to_csv("/home/user/raw_server_logs.csv", index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
