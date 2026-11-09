#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/aggregator/ws
    mkdir -p /home/user/aggregator/models
    cd /home/user/aggregator
    go mod init aggregator
    go get github.com/gorilla/websocket

    cat << 'EOF' > /home/user/aggregator/models/trade.go
package models

type Trade struct {
	Symbol string `json:"symbol"`
	Price  int    `json:"price"` // BUG: should be float64
	Amount int    `json:"amount"`
}
EOF

    cat << 'EOF' > /home/user/aggregator/ws/client.go
package ws

import (
	"encoding/json"
	"log"
	"sync"
	"github.com/gorilla/websocket"
	"aggregator/models"
)

type Client struct {
	Conn     *websocket.Conn
	Stats    map[string]int
	statsMut sync.RWMutex
}

func NewClient(conn *websocket.Conn) *Client {
	return &Client{
		Conn:  conn,
		Stats: make(map[string]int),
	}
}

func (c *Client) Start() {
	// BUG: This loop blocks the caller. It should be run in a goroutine: go func() { ... }()
	for {
		_, message, err := c.Conn.ReadMessage()
		if err != nil {
			log.Println("read err:", err)
			break
		}
		var trade models.Trade
		if err := json.Unmarshal(message, &trade); err != nil {
			log.Println("unmarshal err:", err)
			continue
		}
		c.statsMut.Lock()
		c.Stats[trade.Symbol] += trade.Amount
		c.statsMut.Unlock()
	}
}

func (c *Client) GetStats() map[string]int {
	c.statsMut.RLock()
	defer c.statsMut.RUnlock()

	// return a copy
	res := make(map[string]int)
	for k, v := range c.Stats {
		res[k] = v
	}
	return res
}
EOF

    cat << 'EOF' > /home/user/aggregator/main.go
package main

import (
	"encoding/json"
	"net/http"
	"aggregator/ws"
)

type Server struct {
	wsClient *ws.Client
}

func (s *Server) StatsHandler(w http.ResponseWriter, r *http.Request) {
	stats := s.wsClient.GetStats()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}
EOF

    cat << 'EOF' > /home/user/aggregator/main_test.go
package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"aggregator/ws"
)

var upgrader = websocket.Upgrader{}

func mockWSServer(w http.ResponseWriter, r *http.Request) {
	c, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer c.Close()
	// Send mock trades (Note price is a float)
	trades := []string{
		`{"symbol":"AAPL", "price":150.25, "amount":10}`,
		`{"symbol":"AAPL", "price":151.00, "amount":5}`,
		`{"symbol":"MSFT", "price":300.50, "amount":20}`,
	}
	for _, t := range trades {
		c.WriteMessage(websocket.TextMessage, []byte(t))
		time.Sleep(10 * time.Millisecond)
	}
}

func TestIntegration(t *testing.T) {
	// Setup mock WS server
	wsServer := httptest.NewServer(http.HandlerFunc(mockWSServer))
	defer wsServer.Close()

	wsURL := "ws" + strings.TrimPrefix(wsServer.URL, "http")
	dialer := websocket.DefaultDialer
	conn, _, err := dialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("Failed to connect to WS: %v", err)
	}

	client := ws.NewClient(conn)

	// Start processing (if this blocks, the test times out)
	done := make(chan bool)
	go func() {
		client.Start()
		done <- true
	}()

	select {
	case <-done:
		// if Start doesn't block, it should return immediately (or run in background)
		// Wait actually Start() itself shouldn't block.
	case <-time.After(100 * time.Millisecond):
		t.Fatalf("client.Start() is blocking!")
	}

	time.Sleep(200 * time.Millisecond) // wait for messages to be processed

	// Setup REST server
	srv := &Server{wsClient: client}
	req, _ := http.NewRequest("GET", "/stats", nil)
	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(srv.StatsHandler)

	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v", status, http.StatusOK)
	}

	var stats map[string]int
	if err := json.Unmarshal(rr.Body.Bytes(), &stats); err != nil {
		t.Fatalf("Failed to parse response: %v", err)
	}

	if stats["AAPL"] != 15 {
		t.Errorf("Expected 15 AAPL, got %d", stats["AAPL"])
	}
	if stats["MSFT"] != 20 {
		t.Errorf("Expected 20 MSFT, got %d", stats["MSFT"])
	}
}
EOF

    chown -R user:user /home/user/aggregator
    chmod -R 777 /home/user
