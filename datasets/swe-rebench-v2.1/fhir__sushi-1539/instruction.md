Improve handling of complex id, and assignment of primitive instances generally
If an entity’s id is an object and not just a string, it can produce errors and undesirable results. As long as that object has a “value” attribute, we should be able to use that attribute for the actual string. This only happens when assigning an inline instance of string to “id”.

The right thing to do is to make it so that the value ends up on the actual “id” and the other parts end up on “_id”.

While we discovered this with id, this is applicable when assigning any inline instance of a primitive.
