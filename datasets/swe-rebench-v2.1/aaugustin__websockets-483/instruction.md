handling closed connections in ws_handler
I recently noticed that if a connection closes abnormally (and additionally is one that `websockets` is aware of), then `ws_handler` on the server side just continues running normally. This can create a problem by leaving protocol objects on the server-side running for longer than they need to be.

I sort of expected in this case that the server would send `CancelledError` in to `ws_handler` to notify the handler that there is no longer a connection to be handled.

I'm wondering then if it would make sense for `websockets` to send `CancelledError` in this case. If not, what is the right way for a `ws_handler` to "subscribe" to or be notified of the connection closing? It would be much better for `ws_handler` e.g. to be able to register a callback on a future rather than having to, say, check that `protocol.open` is true at regular intervals.

Here is example code to illustrate the issue:

```python
def log(msg):
    print(f'****: {msg}')

async def fail_connection(protocol):
    await asyncio.sleep(5)
    log('failing connection')
    await protocol.fail_connection()

async def handle_connection(protocol, path):
    asyncio.ensure_future(fail_connection(protocol))
    try:
        while True:
            await asyncio.sleep(1)
            log('still handling connection')
    finally:
        log('exiting handle_connection()')

async def run_client():
    async with websockets.connect('ws://localhost:8765'):
        print('client connected')
        await asyncio.sleep(10)

    print('client exiting')

async def run():
    async with websockets.serve(handle_connection, 'localhost', 8765):
        await run_client()
```

And here are the logs:

    client connected
    INFO:asyncio:poll 998.616 ms took 1003.063 ms: timeout
    ****: still handling connection
    INFO:asyncio:poll 999.874 ms took 1004.412 ms: timeout
    ****: still handling connection
    INFO:asyncio:poll 999.875 ms took 1003.993 ms: timeout
    ****: still handling connection
    INFO:asyncio:poll 999.880 ms took 1004.832 ms: timeout
    ****: still handling connection
    ****: failing connection
    DEBUG:websockets.protocol:server ! failing WebSocket connection: 1011
    DEBUG:websockets.protocol:server > Frame(fin=True, opcode=8, data=b'\x03\xf3', rsv1=False, rsv2=False, rsv3=False)
    DEBUG:asyncio:poll 15.719 ms took 0.015 ms: 1 events
    DEBUG:websockets.protocol:client < Frame(fin=True, opcode=8, data=b'\x03\xf3', rsv1=False, rsv2=False, rsv3=False)
    DEBUG:websockets.protocol:client > Frame(fin=True, opcode=8, data=b'\x03\xf3', rsv1=False, rsv2=False, rsv3=False)
    DEBUG:websockets.protocol:server < Frame(fin=True, opcode=8, data=b'\x03\xf3', rsv1=False, rsv2=False, rsv3=False)
    DEBUG:websockets.protocol:server x half-closing TCP connection
    DEBUG:asyncio:poll 14.151 ms took 0.010 ms: 1 events
    DEBUG:asyncio:<_SelectorSocketTransport fd=12 read=polling write=<idle, bufsize=0>> received EOF
    DEBUG:websockets.protocol:client - eof_received()
    DEBUG:websockets.protocol:client - connection_lost(None)
    DEBUG:asyncio:<_SelectorSocketTransport fd=13 read=polling write=<idle, bufsize=0>> received EOF
    DEBUG:websockets.protocol:server - eof_received()
    DEBUG:websockets.protocol:client x closing TCP connection
    DEBUG:websockets.protocol:server - connection_lost(None)
    DEBUG:websockets.protocol:server x closing TCP connection
    ****: still handling connection
    INFO:asyncio:poll 999.879 ms took 1002.503 ms: timeout
    ****: still handling connection
    INFO:asyncio:poll 999.879 ms took 1004.720 ms: timeout
    ****: still handling connection
    INFO:asyncio:poll 999.879 ms took 1000.126 ms: timeout
    ****: still handling connection
    INFO:asyncio:poll 999.880 ms took 1003.233 ms: timeout
    ****: still handling connection
    client exiting
    ****: exiting handle_connection()
    DEBUG:websockets.protocol:server ! failing WebSocket connection: 1001

### Additional contract requirements

- When the server is closed with `WebSocketServer.close()`, it does not cancel
  connection handlers. A connection handler keeps running until it returns on
  its own; it observes the shutdown as a normal connection closure, not as
  `asyncio.CancelledError`.
- `WebSocketServer.wait_closed()` resolves only after all connection handlers
  have completed.
