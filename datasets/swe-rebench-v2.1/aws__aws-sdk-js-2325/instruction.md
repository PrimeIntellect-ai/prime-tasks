node: timers leaked on HTTP connection errors
If the `connectTimeout` http option has been supplied, timers are used to manage the connection timeout. The timers are cleared when a connection is established, however, the timers are *not* cleared if an error happens.

The end result is that timers are leaked for every attempt to make an HTTP connection that does not succeed.

https://github.com/aws/aws-sdk-js/blob/master/lib/http/node.js#L60

## Reproduction

1. Create the following application:
    ```
    const AWS = require('aws-sdk')

    const dbOptions = {
      region: 'us-east-1',
      accessKeyId: 'accessKeyId',
      secretAccessKey: 'secretAccessKey',
      endpoint: new AWS.Endpoint('http://localhost:12345'),
      httpOptions: {
        connectTimeout: 10000
      }
    }
    const dynamo = new AWS.DynamoDB(dbOptions)

    console.log('about to start query')

    dynamo.listTables({}).promise()
      .then(() => {
        console.log('query complete')

        console.time('waiting for leaked timers')

        process.on('exit', () => {
          console.timeEnd('waiting for leaked timers')
        })
      })
      .catch((err) => {
        console.log('error executing query', err)
      })
    ```
2. Run the node application
3. A couple seconds after starting the application, fire up local dynamo:

    `docker run -it --rm -p 12345:8000 --name dynamo amazon/dynamodb-local`

### Expected

`waiting for leaked timers: ` reports < 1 millisecond.

### Unexpected

Application hangs for multiple seconds after seeing "query complete".

`waiting for leaked timers: ` reports multiple seconds (approximately `10 - <time to start dynamo>` seconds)
