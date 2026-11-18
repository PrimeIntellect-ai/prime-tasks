#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/config_commits.csv
1698242400,auth.login,Login,Вход,ログイン
1698244200,auth.login,Login Screen,Экран входа,ログイン画面
1698246000,ui.button,Submit,Отправить,送信
1698246050,ui.button,Submit!,Отправить!,送信!
1698328800,auth.logout,Log out,Выйти,ログアウト
EOF

    cat << 'EOF' > /home/user/expected_output.csv
bucket,config_key,lang_pair,max_distance
2023-10-25T14,auth.login,en-ja,12
2023-10-25T14,auth.login,en-ru,12
2023-10-25T15,ui.button,en-ja,7
2023-10-25T15,ui.button,en-ru,10
2023-10-26T14,auth.logout,en-ja,7
2023-10-26T14,auth.logout,en-ru,7
EOF

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
