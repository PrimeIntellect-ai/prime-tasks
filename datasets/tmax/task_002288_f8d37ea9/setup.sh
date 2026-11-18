#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/datasets.db <<EOF
CREATE TABLE datasets (id INTEGER PRIMARY KEY, name TEXT, domain TEXT, size_mb INTEGER);
CREATE TABLE derivations (source_id INTEGER, target_id INTEGER, method TEXT);

INSERT INTO datasets VALUES (1, 'Root_Alpha', 'Core', 5000);
INSERT INTO datasets VALUES (2, 'Text_Cleaned', 'NLP', 4000);
INSERT INTO datasets VALUES (3, 'Text_Tokenized', 'NLP', 4500);
INSERT INTO datasets VALUES (4, 'Images_Raw', 'CV', 10000);
INSERT INTO datasets VALUES (5, 'Images_Filtered', 'CV', 2000);
INSERT INTO datasets VALUES (6, 'Images_Resized', 'CV', 2000);
INSERT INTO datasets VALUES (7, 'Embeddings_V1', 'ML', 8000);
INSERT INTO datasets VALUES (8, 'Embeddings_Filtered', 'ML', 1000);
INSERT INTO datasets VALUES (9, 'Unrelated_Data', 'NLP', 500);

-- Root_Alpha -> Text_Cleaned (clean)
INSERT INTO derivations VALUES (1, 2, 'clean');
-- Text_Cleaned -> Text_Tokenized (tokenize)
INSERT INTO derivations VALUES (2, 3, 'tokenize');

-- Root_Alpha -> Images_Raw (extract)
INSERT INTO derivations VALUES (1, 4, 'extract');
-- Images_Raw -> Images_Filtered (filter)
INSERT INTO derivations VALUES (4, 5, 'filter');
-- Images_Filtered -> Images_Resized (resize)
INSERT INTO derivations VALUES (5, 6, 'resize');

-- Text_Tokenized -> Embeddings_V1 (embed)
INSERT INTO derivations VALUES (3, 7, 'embed');
-- Embeddings_V1 -> Embeddings_Filtered (filter)
INSERT INTO derivations VALUES (7, 8, 'filter');
EOF

    chmod -R 777 /home/user
