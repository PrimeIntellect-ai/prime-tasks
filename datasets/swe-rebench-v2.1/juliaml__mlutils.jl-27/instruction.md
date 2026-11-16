extend batch to handle vectors of tuples, named tuples, dicts

### Additional contract requirements

When batching a vector of tuples, batch each tuple position across the inputs and return the batched components in a tuple at the corresponding positions. For a vector of named tuples, preserve each field name and batch values associated with that name across the inputs. For a vector of dictionaries, preserve each key and batch values associated with that key across the inputs.
