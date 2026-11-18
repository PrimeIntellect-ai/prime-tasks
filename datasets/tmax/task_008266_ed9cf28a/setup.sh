#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ gcc golang
pip3 install pytest requests

mkdir -p /home/user/app/cpp /home/user/app/go /home/user/app/lib

# C++ Code
cat << 'EOF' > /home/user/app/cpp/Task.h
#ifndef TASK_H
#define TASK_H
#include <string>
#include "Worker.h"

struct Task {
    std::string id;
    int priority;
    Worker* assigned_worker;
};
#endif
EOF

cat << 'EOF' > /home/user/app/cpp/Worker.h
#ifndef WORKER_H
#define WORKER_H
#include <string>
#include "Task.h"

struct Worker {
    std::string name;
    Task* current_task;
};
#endif
EOF

cat << 'EOF' > /home/user/app/cpp/TaskQueue.h
#ifndef TASK_QUEUE_H
#define TASK_QUEUE_H
#include <vector>
#include <mutex>
#include "Task.h"

class TaskQueue {
private:
    std::vector<Task*> tasks;
    std::mutex mtx;
public:
    void push_task(const char* id, int priority);
    Task* pop_task();
    int size();
};

extern "C" {
    void* create_queue();
    void push_queue(void* q, const char* id, int priority);
    char* pop_queue(void* q);
    void destroy_queue(void* q);
}
#endif
EOF

cat << 'EOF' > /home/user/app/cpp/TaskQueue.cpp
#include "TaskQueue.h"
#include <cstring>
#include <algorithm>

void TaskQueue::push_task(const char* id, int priority) {
    std::lock_guard<std::mutex> lock(mtx);
    Task* t = new Task();
    t->id = std::string(id);
    t->priority = priority;
    t->assigned_worker = nullptr;
    tasks.push_back(t);
}

Task* TaskQueue::pop_task() {
    // TODO: Implement thread-safe extraction of highest priority task
    return nullptr;
}

int TaskQueue::size() {
    std::lock_guard<std::mutex> lock(mtx);
    return tasks.size();
}

extern "C" {
    void* create_queue() { return new TaskQueue(); }
    void push_queue(void* q, const char* id, int priority) {
        static_cast<TaskQueue*>(q)->push_task(id, priority);
    }
    char* pop_queue(void* q) {
        Task* t = static_cast<TaskQueue*>(q)->pop_task();
        if (!t) return nullptr;
        char* res = strdup(t->id.c_str());
        delete t;
        return res;
    }
    void destroy_queue(void* q) { delete static_cast<TaskQueue*>(q); }
}
EOF

# Go Code
cat << 'EOF' > /home/user/app/go/go.mod
module task-broker

go 1.18
EOF

cat << 'EOF' > /home/user/app/go/main.go
package main

/*
#cgo CFLAGS: -I../cpp
#cgo LDFLAGS: -L../lib -ltaskqueue
#include <stdlib.h>
#include "TaskQueue.h"
*/
import "C"
import (
	"encoding/json"
	"net/http"
	"unsafe"
)

var queue unsafe.Pointer

type EnqueueReq struct {
	ID       string `json:"id"`
	Priority int    `json:"priority"`
}

func enqueueHandler(w http.ResponseWriter, r *http.Request) {
	var req EnqueueReq
	json.NewDecoder(r.Body).Decode(&req)
	cid := C.CString(req.ID)
	defer C.free(unsafe.Pointer(cid))

	C.push_queue(queue, cid, C.int(req.Priority))
	w.WriteHeader(http.StatusOK)
}

func dequeueHandler(w http.ResponseWriter, r *http.Request) {
	cres := C.pop_queue(queue)
	if cres == nil {
		http.Error(w, "empty", http.StatusNotFound)
		return
	}
	defer C.free(unsafe.Pointer(cres))

	res := C.GoString(cres)
	json.NewEncoder(w).Encode(map[string]string{"id": res})
}

func main() {
	queue = C.create_queue()
	defer C.destroy_queue(queue)

	http.HandleFunc("/enqueue", enqueueHandler)
	http.HandleFunc("/dequeue", dequeueHandler)
	http.ListenAndServe(":8080", nil)
}
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
