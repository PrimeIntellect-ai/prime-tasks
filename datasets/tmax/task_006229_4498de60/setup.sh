#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/graph_nodes.csv
1,Server,WebSrv1
2,Server,WebSrv2
3,Service,AuthService
4,Service,PaymentService
5,Database,UserDB
6,Database,TxDB
7,Server,BackgroundWorker
8,Service,NotificationService
9,Database,LogDB
10,Server,APIGateway
EOF

    cat << 'EOF' > /home/user/graph_edges.csv
1,3,DEPENDS_ON
1,4,DEPENDS_ON
2,3,DEPENDS_ON
3,5,DEPENDS_ON
4,6,DEPENDS_ON
7,4,DEPENDS_ON
7,8,DEPENDS_ON
8,9,DEPENDS_ON
10,3,DEPENDS_ON
10,8,DEPENDS_ON
4,5,DEPENDS_ON
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
