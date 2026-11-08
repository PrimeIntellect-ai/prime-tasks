Update default extractor for purgeCSS to account for escaped class names
### Describe the problem:

Not sure if this is a bug or a feature request, but I just noticed that the default extractor for purgeCSS does not extract class names that have been escaped. For example, in translation JSON files, we have a need to include html elements as such:

```
{
  "helloThere": "Hello there, <span class=\"whitespace-no-wrap\">Mr. Jones</span>"
}
```

But it seems like the patterns used in the default extractor don't collect these class names properly. Using a Regex tester, it looks like the final `\` is also included:

![image](https://user-images.githubusercontent.com/1256477/92688835-ffb68c00-f378-11ea-8b2b-e7698fbafae1.png)

I guess it's not too much of a problem, as one can just add another extractor for JSON files. But it took as a while to figure out the work around, so it might help others in the future if the patterns could also account for escaped strings.
