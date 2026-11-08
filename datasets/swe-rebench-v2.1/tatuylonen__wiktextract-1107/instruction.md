ancient greek articles treated as separate forms
Ancient greek forms with comma-separated articles (e.g. [ἰχθυοκένταυρος](https://en.wiktionary.org/wiki/%E1%BC%B0%CF%87%CE%B8%CF%85%CE%BF%CE%BA%CE%AD%CE%BD%CF%84%CE%B1%CF%85%CF%81%CE%BF%CF%82#Ancient%20Greek)), result in the first article being treated as a separate form,  [ἰχθυοκένταυρος on kaikki](https://kaikki.org/dictionary/All%20languages%20combined/meaning/%E1%BC%B0/%E1%BC%B0%CF%87/%E1%BC%B0%CF%87%CE%B8%CF%85%CE%BF%CE%BA%CE%AD%CE%BD%CF%84%CE%B1%CF%85%CF%81%CE%BF%CF%82.html):

```json
{
      "form": "ὁ",
      "roman": "ho",
      "source": "declension",
      "tags": [
        "nominative",
        "singular"
      ]
}
```

### Additional contract requirements

- Ancient Greek declension cells may contain a comma-separated article followed
  by the word, such as `ὁ, ἡ ἰχθυοκένταυρος`. The article must be removed from
  the emitted form: the emitted form must be the word itself
  (`ἰχθυοκένταυρος`), and the article (`ὁ`) must not be emitted as a separate
  form. The same applies to the other articles and their forms, such as
  `οἱ, αἱ ἰχθυοκένταυροι`, which must emit `ἰχθυοκένταυροι` and not `οἱ`.
