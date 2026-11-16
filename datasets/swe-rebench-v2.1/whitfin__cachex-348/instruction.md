Fetch can allow multiple executions of `fallback` function
First off - thanks, as always, for maintaining this library!

I had a question / bug(?) report regarding `fetch/4`

I rely heavily on `fetch/4` when using cachex to leverage the fact that the `fallback` function will only be called once per key per ttl and recently found out that the reason for a very infrequent test failure was that the `fallback` function was in fact being called multiple times due to what I assume is a race condition

The general flow for `fetch` is as follows

```mermaid
stateDiagram-v2
    state cache_hit_state <<fork>>
    state fetch_state <<fork>>
    state task_notification <<join>>
    state response_state <<join>>

    [*] --> Cachex.fetch/4
    Cachex.fetch/4 --> check_cache
    check_cache --> cache_hit_state
    cache_hit_state --> cache_hit
    cache_hit_state --> cache_miss

    cache_miss --> dispatch_to_currier
    dispatch_to_currier --> fetch_state
    fetch_state --> task_executing
    fetch_state --> no_task_executing

    state Currier {
    task_executing --> queue_caller_await_notification
    no_task_executing --> execute_task
    no_task_executing --> queue_caller_await_notification
    queue_caller_await_notification --> task_notification
    update_cache --> task_notification
    task_notification --> notification
    notification --> reply_to_callers
    }

    state external_task {
        execute_task --> fallback
        fallback --> update_cache
    }


    reply_to_callers --> response_state
    cache_hit --> response_state

    response_state --> return_value
 ```

I believe the issue I am seeing is related to the fact that the initial check cache / queue a message with the currier is not an "atomic" operation and can interleave in a way in which we would execute the `fallback` function a second time.

Imagine a situation where the Currier has dispatched a task to generate the value for `key_1`
A new client (Client_3) now calls `fetch/4` for the value of `key_1`
- The cache value is checked, and is still empty
BEFORE we can dispatch a message to the Currier, the existing task finishes executing the fallback function, updates the cache and sends its notification to the Currier
The Currier sends responses to all currently enqueued clients for `key_1`
The Currier then gets the `dispatch` message from `Client_3` which triggers a new task to be executed

Here is an attempt to diagram that same workflow

```mermaid
sequenceDiagram
    box cache
    participant Cache
    end
    box Clients
    participant Client_1
    participant Client_2
    participant Client_3
    end
    box Currier
    participant Currier
    participant Task
    end

    Client_1->>Cache: check key_1
    Cache->>Client_1: no value
    Client_1->>Currier: fetch key_1
    Currier->>Task: dispatch
    Currier->>Currier: record Client_1->key_1
    Client_2->>Cache: check key_1
    Cache->>Client_2: no value
    Client_2->>Currier: fetch key_1
    Currier->>Currier: record Client_2->key_1
    Task->>Task: execute_fallback
    Client_3->>Cache: check key_1
    Cache->>Client_3: no value
    Task->>Task: update_cache
    Client_3->>Currier: fetch key_1
    Task->>Currier: notification of result
    Currier->>Client_1: result
    Currier->>Client_2: result
    Client_3->>Currier: fetch key_1
    Currier->>Task: dispatch

 ```

* I hope these mermaids make some sense - If you need more context I can try and update them to better match my thinking

I was wondering if you agree that this behavior is undesirable and if you do agree wanted to see what your thoughts were on a potential resolution.  My first thoughts was that [HIDDEN] - this would add some additional overhead, but only for the single message that would execute the task

### Additional contract requirements

- For a given key, concurrent fetches during one valid cache period must execute the fallback at most once, including when a dispatch arrives after an earlier fallback has populated the cache.
