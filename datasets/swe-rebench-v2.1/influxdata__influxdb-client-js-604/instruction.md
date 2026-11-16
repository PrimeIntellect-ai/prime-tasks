triggerUncaughtException after field type conflict
### Specifications

* Client Version: 1.30.0
* InfluxDB Version: 2.4.0
* Platform: client: MacOS and nodejs 18.2.0, server: docker container on synology

When using the writeApi interface to add points, when the auto flushing kicks in, the following error is thrown and my nodejs script exits:
```
WARN: Write to InfluxDB failed (attempt: 2). d [HttpError]: unexpected error writing points to database: field type conflict
    at IncomingMessage.<anonymous> (<hidden>/node_modules/@influxdata/influxdb-client/dist/index.js:5:5309)
    at IncomingMessage.emit (node:events:539:35)
    at endReadableNT (node:internal/streams/readable:1344:12)
    at process.processTicksAndRejections (node:internal/process/task_queues:82:21) {
  statusCode: 500,
  statusMessage: 'Internal Server Error',
  body: '{"code":"internal error","message":"unexpected error writing points to database: field type conflict"}',
  contentType: 'application/json; charset=utf-8',
  json: {
    code: 'internal error',
    message: 'unexpected error writing points to database: field type conflict'
  },
  code: 'internal error',
  _retryAfter: 0
}
node:internal/process/promises:288
            triggerUncaughtException(err, true /* fromPromise */);
            ^

d [HttpError]: unexpected error writing points to database: field type conflict
    at IncomingMessage.<anonymous> (<hidden>/node_modules/@influxdata/influxdb-client/dist/index.js:5:5309)
    at IncomingMessage.emit (node:events:539:35)
    at endReadableNT (node:internal/streams/readable:1344:12)
    at process.processTicksAndRejections (node:internal/process/task_queues:82:21) {
  statusCode: 500,
  statusMessage: 'Internal Server Error',
  body: '{"code":"internal error","message":"unexpected error writing points to database: field type conflict"}',
  contentType: 'application/json; charset=utf-8',
  json: {
    code: 'internal error',
    message: 'unexpected error writing points to database: field type conflict'
  },
  code: 'internal error',
  _retryAfter: 0
}
```

The question is not what I should do to solve the type conflict, but how to catch the error to prevent my code from exiting?


### Code sample to reproduce problem

My code listens to mqtt topics and based on a selector it writes data to influxdb.


### Expected behavior

A way to catch the error that is thrown from the flush logic that gets automatically triggered based on the number of pending points or the time since the last write.

### Actual behavior

My code exits with this error message:

```
WARN: Write to InfluxDB failed (attempt: 2). d [HttpError]: unexpected error writing points to database: field type conflict
    at IncomingMessage.<anonymous> (<hidden>/node_modules/@influxdata/influxdb-client/dist/index.js:5:5309)
    at IncomingMessage.emit (node:events:539:35)
    at endReadableNT (node:internal/streams/readable:1344:12)
    at process.processTicksAndRejections (node:internal/process/task_queues:82:21) {
  statusCode: 500,
  statusMessage: 'Internal Server Error',
  body: '{"code":"internal error","message":"unexpected error writing points to database: field type conflict"}',
  contentType: 'application/json; charset=utf-8',
  json: {
    code: 'internal error',
    message: 'unexpected error writing points to database: field type conflict'
  },
  code: 'internal error',
  _retryAfter: 0
}
node:internal/process/promises:288
            triggerUncaughtException(err, true /* fromPromise */);
            ^

d [HttpError]: unexpected error writing points to database: field type conflict
    at IncomingMessage.<anonymous> (<hidden>/node_modules/@influxdata/influxdb-client/dist/index.js:5:5309)
    at IncomingMessage.emit (node:events:539:35)
    at endReadableNT (node:internal/streams/readable:1344:12)
    at process.processTicksAndRejections (node:internal/process/task_queues:82:21) {
  statusCode: 500,
  statusMessage: 'Internal Server Error',
  body: '{"code":"internal error","message":"unexpected error writing points to database: field type conflict"}',
  contentType: 'application/json; charset=utf-8',
  json: {
    code: 'internal error',
    message: 'unexpected error writing points to database: field type conflict'
  },
  code: 'internal error',
  _retryAfter: 0
}
```


### Additional info

_No response_
