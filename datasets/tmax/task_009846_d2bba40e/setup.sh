#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/forensic_service/models
    mkdir -p /home/user/forensic_service/db

    cat << 'EOF' > /home/user/forensic_service/models/models.go
package models

type Event struct {
	ID       int
	Username string
	Action   string
	Severity int
}

type AuditStore interface {
	GetCriticalEvents() ([]Event, error)
	SaveEvent(ev Event) error
}
EOF

    cat << 'EOF' > /home/user/forensic_service/db/db.go
package db

import (
	"database/sql"
	"forensic_service/models"
	_ "github.com/mattn/go-sqlite3"
)

type SQLiteStore struct {
	db *sql.DB
}

func NewSQLiteStore(db *sql.DB) *SQLiteStore {
	return &SQLiteStore{db: db}
}

// BUG 1: Signature mismatch with interface (returns []*models.Event instead of []models.Event)
func (s *SQLiteStore) GetCriticalEvents() ([]*models.Event, error) {
	rows, err := s.db.Query("SELECT id, username, action, severity FROM events WHERE severity >= 5 ORDER BY id ASC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []*models.Event
	for rows.Next() {
		var ev models.Event
		// BUG 2: Swapped action and username in Scan
		if err := rows.Scan(&ev.ID, &ev.Action, &ev.Username, &ev.Severity); err != nil {
			return nil, err
		}
		events = append(events, &ev)
	}
	return events, nil
}

func (s *SQLiteStore) SaveEvent(ev models.Event) error {
	_, err := s.db.Exec("INSERT INTO events (id, username, action, severity) VALUES (?, ?, ?, ?)", ev.ID, ev.Username, ev.Action, ev.Severity)
	return err
}

func (s *SQLiteStore) InitSchema() error {
	_, err := s.db.Exec(`CREATE TABLE IF NOT EXISTS events (
		id INTEGER PRIMARY KEY,
		username TEXT,
		action TEXT,
		severity INTEGER
	)`)
	return err
}
EOF

    cat << 'EOF' > /home/user/forensic_service/main.go
package main

import (
	"database/sql"
	"fmt"
	"log"

	"forensic_service/db"
	"forensic_service/models"
)

func main() {
	database, err := sql.Open("sqlite3", ":memory:")
	if err != nil {
		log.Fatal(err)
	}

	store := db.NewSQLiteStore(database)
	store.InitSchema()

	// This assignment will fail to compile due to Bug 1
	var audit models.AuditStore = store

	events, err := audit.GetCriticalEvents()
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("Found %d critical events\n", len(events))
}
EOF

    cd /home/user/forensic_service
    go mod init forensic_service
    go get github.com/mattn/go-sqlite3
    go mod tidy

    chmod -R 777 /home/user
