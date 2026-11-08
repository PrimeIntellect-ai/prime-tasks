#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import json

data = [
    # English
    {"id": "E1", "lang": "en", "text": "Ｈｅｌｌｏ ｗｏｒｌｄ! This is a test."}, # len 28
    {"id": "E2", "lang": "en", "text": "hello world! this is a test."}, # Duplicate of E1 after NFKC + lower. E1 kept.
    {"id": "E3", "lang": "en", "text": "Short"}, # Too short (<15)
    {"id": "E4", "lang": "en", "text": "This is a completely normal english sentence."}, # len 45
    {"id": "E5", "lang": "en", "text": "Another sentence that has exact same length!!"}, # len 45
    {"id": "E6", "lang": "en", "text": "This is the longest english sentence in the dataset, it should be first."}, # len 72
    {"id": "E7", "lang": "en", "text": "A moderately long sentence for english."}, # len 39

    # Japanese
    {"id": "J1", "lang": "ja", "text": "ﾊﾝｶｸｶﾀｶﾅ is half-width katakana."}, # len 32 after NFKC (ハンカクカタカナ is half-width katakana.)
    {"id": "J2", "lang": "ja", "text": "ハンカクカタカナ is half-width katakana."}, # Duplicate of J1. J1 kept.
    {"id": "J3", "lang": "ja", "text": "これはテスト"}, # Too short
    {"id": "J4", "lang": "ja", "text": "日本語のテキスト処理は、Unicode正規化が非常に重要です。"}, # len 30
    {"id": "J5", "lang": "ja", "text": "もう一つの長い日本語の文章を作成しています。これで長さが足りますか？"}, # len 33

    # French
    {"id": "F1", "lang": "fr", "text": "C'est la vie! C'est très bien."}, # len 30
    {"id": "F2", "lang": "fr", "text": "C'est la vie! c'est très bien."}, # Duplicate of F1
    {"id": "F3", "lang": "fr", "text": "Bonjour tout le monde, comment allez-vous aujourd'hui?"}, # len 54
    {"id": "F4", "lang": "fr", "text": "Un autre texte français qui est assez long pour être inclus."}, # len 60
    {"id": "F5", "lang": "fr", "text": "Texte court"} # Too short
]

with open('/home/user/raw_data.jsonl', 'w', encoding='utf-8') as f:
    for item in data:
        f.write(json.dumps(item, ensure_ascii=False) + '\n')
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
