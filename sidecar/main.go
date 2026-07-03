package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

const (
	listenAddr  = "127.0.0.1:9876"
	apiBase     = "https://your-api.example.com" // TODO: replace before shipping
	httpTimeout = 8 * time.Second
)

var httpClient = &http.Client{Timeout: httpTimeout}

type Request struct {
	Action string `json:"action"`
	Name   string `json:"name,omitempty"`
	Score  int64  `json:"score,omitempty"`
}

type Response struct {
	OK     bool          `json:"ok"`
	Error  string        `json:"error,omitempty"`
	Scores []LeaderEntry `json:"scores,omitempty"`
}

type LeaderEntry struct {
	Rank  int    `json:"rank"`
	Name  string `json:"name"`
	Score int64  `json:"score"`
}

func main() {
	ln, err := net.Listen("tcp", listenAddr)
	if err != nil {
		log.Fatalf("listen %s: %v", listenAddr, err)
	}
	fmt.Fprintf(os.Stderr, "sss-net ready on %s\n", listenAddr)

	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("accept: %v", err)
			continue
		}
		go handle(conn)
	}
}

func handle(conn net.Conn) {
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(10 * time.Second))

	data, err := io.ReadAll(conn)
	if err != nil || len(data) == 0 {
		return
	}

	var req Request
	if err := json.Unmarshal(data, &req); err != nil {
		writeResp(conn, Response{Error: "bad request"})
		return
	}

	switch req.Action {
	case "submit":
		writeResp(conn, submitScore(req))
	case "fetch":
		writeResp(conn, fetchScores())
	default:
		writeResp(conn, Response{Error: "unknown action: " + req.Action})
	}
}

func submitScore(req Request) Response {
	body, _ := json.Marshal(map[string]any{
		"name":  req.Name,
		"score": req.Score,
	})
	r, err := httpClient.Post(apiBase+"/scores", "application/json",
		strings.NewReader(string(body)))
	if err != nil {
		return Response{Error: err.Error()}
	}
	defer r.Body.Close()
	ok := r.StatusCode == http.StatusOK || r.StatusCode == http.StatusCreated
	return Response{OK: ok}
}

func fetchScores() Response {
	r, err := httpClient.Get(apiBase + "/scores/top10")
	if err != nil {
		return Response{Error: err.Error()}
	}
	defer r.Body.Close()

	var scores []LeaderEntry
	if err := json.NewDecoder(r.Body).Decode(&scores); err != nil {
		return Response{Error: "decode: " + err.Error()}
	}
	return Response{OK: true, Scores: scores}
}

func writeResp(conn net.Conn, resp Response) {
	data, _ := json.Marshal(resp)
	conn.Write(data)
}
