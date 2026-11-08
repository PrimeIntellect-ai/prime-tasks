`RichTextElement.elements` items are never promoted to a proper Python object type
Using the rich text editor widget with the following content:
<img width="477" alt="Screenshot 2024-03-05 at 11 39 10" src="https://github.com/slackapi/python-slack-sdk/assets/118377/0b627c94-4804-4535-8ada-38c4bd91be58">
gets you an unordered list, which upon a `view_submission` event gets posted into the state values as:

<details><summary>JSON representation of state value</summary>

```
{
  "type": "rich_text",
  "elements": [
    {
      "type": "rich_text_list",
      "style": "bullet",
      "indent": 0,
      "elements": [
        {
          "type": "rich_text_section",
          "elements": [
            {
              "type": "text",
              "text": "a"
            }
          ]
        },
        {
          "type": "rich_text_section",
          "elements": [
            {
              "type": "text",
              "text": "b"
            }
          ]
        }
      ],
      "border": 0
    }
  ]
}
```

</details>

which can then be converted into an object like so:
```
>>> obj = Block.parse(example)
>>> type(obj)
slack_sdk.models.blocks.blocks.RichTextBlock
>>> len(obj.elements)
1
>>> type(obj.elements[0])
slack_sdk.models.blocks.block_elements.RichTextListElement
```
which is all well and good... But the child elements of the encountered `RichTextElement` subclass are not converted to the equivalent Python class, and always remain as a dict, effectively looking like the parsing "gave up" at a certain depth (which isn't strictly true):
```
>>> type(obj.elements[0].elements[0])
dict
>>> obj.elements[0].elements[0]
{'type': 'rich_text_section', 'elements': [{'type': 'text', 'text': 'a'}]}
```
As far as I can tell, this is because the `RichTextListElement`, `RichTextPreformattedElement`, `RichTextQuoteElement` and `RichTextSectionElement` never themselves do any parsing, as all of them are defined using:
```python
[HIDDEN]
```
[HIDDEN]
The latter of which would at least make it so that:
```
>>> type(obj.elements[0].elements[0])
slack_sdk.models.blocks.block_elements.RichTextSectionElement
```

That still leaves some child elements unpromoted, because there's nothing which converts `{'type': 'text', 'text': 'a'}` to a `RichTextElementParts.Text` etc, but that feels like a somewhat separate issue.

### Category
- [x] **slack_sdk.models** (UI component builders)

### Additional contract requirements

When a rich-text list, section, quote, or preformatted element contains another structural rich-text element, that child must be available as its corresponding Python model object rather than a raw dictionary.
