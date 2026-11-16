Add as_caption_kwargs() method to aiogram.utils.formatting.Text
### aiogram version

3.x

### Problem

Methods like `Bot.send_document() ` use `caption` and `caption_enteties` parameters instead of `text` and `entities`. That results in repeating `Text(...).as_kwargs(text_key="caption", entities_key="caption_entities")` calls.

### Possible solution

I suggest introducing a shortcut method `as_caption_kwargs()` or something like that

### Alternatives

_No response_

### Code example

```python3

```

### Additional information

_No response_
