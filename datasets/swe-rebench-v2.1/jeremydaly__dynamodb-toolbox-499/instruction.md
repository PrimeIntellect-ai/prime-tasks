Error Instantiating Table with V3 SDK (v0.8.0)
https://github.com/jeremydaly/dynamodb-toolbox/blob/646127d42ea5ad8d65e3afb32d0aec6ce954bcc3/src/classes/Table/Table.ts#L113

I'm getting errors on the latest release (v0.8.0) when instantiating a Table. On the new DocClient, `config.translateConfig` is undefined and the evaluation (linked above) short-circuits to `undefined !== false`, which is true, and then attempts to reference `translateConfg` to set a property. This yields "TypeError: Cannot read properties of undefined (reading 'marshallOptions')"

Here is a sample of what I'm creating:
```javascript
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { Table } from 'dynamodb-toolbox';

const ddbClient = new DynamoDBClient({ region: process.env.AWS_REGION });
const docClient = DynamoDBDocumentClient.from(ddbClient);

new Table({
    name: tableName,
    partitionKey: 'pk',
    sortKey: 'sk',
    DocumentClient: docClient,
  });
```

Unfortunately, I am unfamiliar with the configuration settings of the aws-sdk, and so I don't have any positive suggestions to make here.  Is anyone else encountering this problem?
