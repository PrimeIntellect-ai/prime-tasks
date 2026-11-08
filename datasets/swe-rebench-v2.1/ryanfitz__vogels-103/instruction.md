range query error
Hi, executing this example below throws an error `ExpressionAttributeNames can only be specified when using expressions` in 2.1.0 while working as expected in 2.0.0-rc10. Reverting for now.

```
var Joi    = require('joi');
var vogels = require('vogels');
var AWS    = require('aws-sdk');

var params = {
	"accessKeyId": "xxx",
	"secretAccessKey": "yyy",
	"endpoint": "http://192.168.99.100:18000",
	"region": "eu-west-1"
}

var dynamodb = new AWS.DynamoDB(params);
vogels.dynamoDriver(dynamodb);

var BlogPost = vogels.define('BlogPost', {
	"hashKey": "email",
	"rangeKey": "title",
	"schema": {
		"email": Joi.string().email(),
		"title": Joi.string()
	}
});

BlogPost
	.query('werner@vogels.com')
	.loadAll().exec(function(err, posts){
		console.log(err, posts);
	});
```

### Additional contract requirements

- A query request must include the model's key condition. The condition is represented through `ExpressionAttributeNames` (attribute names prefixed with `#`, e.g. `{'#age': 'age'}`), `ExpressionAttributeValues` (value placeholders prefixed with `:`, e.g. `{':age': 18}`) and `KeyConditionExpression` (e.g. `'(#age = :age)'`).
- When `loadAll()` continues past a `LastEvaluatedKey` and issues further requests, the key condition is added only once: every page request carries the same `KeyConditionExpression` as the first page, and it is not repeated or extended on later pages.
