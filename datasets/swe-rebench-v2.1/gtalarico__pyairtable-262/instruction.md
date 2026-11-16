ORM get all() entries returns a json, not a Model
Talking about this:
https://github.com/gtalarico/pyairtable/blob/main/pyairtable/orm/model.py#L234-L238

This confuses me, as it really does not help for the ORM. I am currently trying to download existing data **as Model**. I thought that the `all()` function would do that, but it returns the json data, which is not what we want.
