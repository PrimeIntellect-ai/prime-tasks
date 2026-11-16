When marshalling strings they are not escaped property
Example: https://play.golang.org/p/8eLm27d9NHe

I am escaping stars and backticks by having them wrapped in single/double quotes in my yaml file.

I have yaml in a file like bellow:
```yaml
keyword: a test keyword
response:
- "**This line will print the first time** Fails to add when marshalling"
- "This line will be printed alone after marshalling and unmarshalling"
```

If you marshal it strips the outside quotes resulting in the following:
```yaml
keyword: a test keyword
response:
- **This line will print the first time** Fails to add when marshalling
- This line will be printed alone after marshalling and unmarshalling
```

The result after marshalling is that the first line gets lost due to being parsed as a pointer when unmarshalling again. This also affects when reading and writing from files.
