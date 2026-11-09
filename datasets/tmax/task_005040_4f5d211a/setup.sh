#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc jq
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/backup_mgr.db <<EOF
CREATE TABLE tbl_bckp_manifest (
    idx INTEGER PRIMARY KEY,
    bckp_alias TEXT NOT NULL UNIQUE
);

CREATE TABLE tbl_bckp_edges (
    src_idx INTEGER,
    dst_idx INTEGER,
    FOREIGN KEY(src_idx) REFERENCES tbl_bckp_manifest(idx),
    FOREIGN KEY(dst_idx) REFERENCES tbl_bckp_manifest(idx)
);

INSERT INTO tbl_bckp_manifest (idx, bckp_alias) VALUES 
(100, 'app_server_backup'),
(101, 'db_cluster_1'),
(102, 'auth_service'),
(103, 'network_storage_A'),
(104, 'user_uploads');

INSERT INTO tbl_bckp_edges (src_idx, dst_idx) VALUES (100, 101);
INSERT INTO tbl_bckp_edges (src_idx, dst_idx) VALUES (100, 102);
INSERT INTO tbl_bckp_edges (src_idx, dst_idx) VALUES (101, 103);
INSERT INTO tbl_bckp_edges (src_idx, dst_idx) VALUES (102, 103);
INSERT INTO tbl_bckp_edges (src_idx, dst_idx) VALUES (104, 103);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
