Non-destructive JSON serialization
Currently, keys in the JSON file may be reordered by the plugin. Similarly, trailing line returns and whitespaces are always discarded when exported (which is not POSIX compliant, yet arguably a _de facto_ standard imposed by JSON serializers in many languages and tools). This can lead to edition wars and merge conflicts in translation files, where an external tool (such as Weblate or even vim) would use a different order or would append a newline at the end.

The ideal solution would be to make the exporter preserve everything and just add keys like a human would do. We could get closer to this by relying on a lexer such as [moo](https://github.com/no-context/moo/blob/master/test/json.js) in order to keep a tokenized version of the original JSON file that we could use to re-export it just as it was before.

[HIDDEN]

See discussions in #58

### Additional contract requirements

When an existing JSON file is exported again, retain and re-emit its trailing whitespace and line breaks, including after keys are added.
