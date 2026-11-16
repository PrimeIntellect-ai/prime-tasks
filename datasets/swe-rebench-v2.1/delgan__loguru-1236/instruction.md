How to escape `\` before tag
In my server application, i'm using loguru logger to log messages from client. But in some case, the log failed with the error: https://github.com/nonebot/adapter-onebot/issues/74 `ValueError: Closing tag "</le>" has no corresponding opening tag`

Here is the example of the case:

```python
message = r"\\<le>test</le>"
logger.opt(colors=True).info(message)
```

It seems double `\` cannot escape the escape before tag according to the ansi parser. how can i escape this message currectly?

https://github.com/Delgan/loguru/blob/e1f48c91cf2646b6429020f784881cd200663114/loguru/_colorizer.py#L223-L232

### Additional contract requirements

When markup is enabled, two backslashes immediately before a markup tag produce one literal backslash followed by the parsed markup. A backslash immediately before a tag continues to escape the tag so it is displayed literally. Backslashes in ordinary text that are not immediately before markup remain unchanged.
