New handling of default= for ModelSerializer
Then changes in #9030 lead to a issue in my implemenation:
With 3.14 and its ModelSerializer we could determine if a user was passing a field to the API or not. (Basically we allow setting the DB field to everything EXCEPT the default via the REST API.)

Example:
```
class Message(Model):
  content_type = models.TextField(null=False, blank=False, default="undefined")

class MessageSerializer(ModelSerializer):
  class Meta:
     model = Message
```

We could de-serialize the JSON `{}` and the validated data didn't contain the default value for content_type. We still can create the model instance from it because there is a default in the database. BUT we disallow actively setting the content_type to `undefined` by checking if `content_type` is in the validated data and refusing a JSON with `{"content_type": "undefined"}`.

With 3.15 we can't determine this anymore, yes? Or is there something in the validated data to tell us where the data came from (the JSON the user posted or the models default)?
