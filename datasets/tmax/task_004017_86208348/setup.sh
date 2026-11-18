#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/research_data.db <<EOF
CREATE TABLE patient_records (
    p_id INTEGER PRIMARY KEY,
    patient_age INTEGER,
    primary_condition TEXT
);

CREATE TABLE trial_assignments (
    t_id INTEGER PRIMARY KEY,
    fk_patient INTEGER,
    treatment_arm TEXT,
    FOREIGN KEY(fk_patient) REFERENCES patient_records(p_id)
);

CREATE TABLE observation_metrics (
    o_id INTEGER PRIMARY KEY,
    fk_trial INTEGER,
    recovery_days REAL,
    FOREIGN KEY(fk_trial) REFERENCES trial_assignments(t_id)
);

INSERT INTO patient_records (p_id, patient_age, primary_condition) VALUES 
(1, 45, 'Asthma'),
(2, 35, 'Asthma'),
(3, 25, 'Asthma'),
(4, 50, 'Diabetes'),
(5, 40, 'Asthma'),
(6, 60, 'Asthma'),
(7, 32, 'Asthma');

INSERT INTO trial_assignments (t_id, fk_patient, treatment_arm) VALUES 
(101, 1, 'Arm A'),
(102, 2, 'Arm B'),
(103, 3, 'Arm A'),
(104, 4, 'Arm B'),
(105, 5, 'Placebo'),
(106, 6, 'UNKNOWN'),
(107, 7, 'Arm A');

INSERT INTO observation_metrics (o_id, fk_trial, recovery_days) VALUES 
(1001, 101, 12.5),
(1002, 102, 8.0),
(1003, 103, 5.0),
(1004, 104, 15.0),
(1005, 105, 20.0),
(1006, 106, 10.0),
(1007, 107, 14.5);
EOF

    chmod -R 777 /home/user
