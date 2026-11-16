Entities need to list all attributes
If an entity does not list an attribute that exists in the database, `get` fails.

To make `await entityName.get(item)` work, in the definition of the entity `entityName`, it needs to list all attributes it may pull from the database for that particular item. Otherwise, it shows an `alias of undefined` error.

This is counterproductive for a single-table NoSQL design as often times, there is data that is there in the database, may get pulled by DynamoDB `get`, but the function doesn't need to be explicit about it.
