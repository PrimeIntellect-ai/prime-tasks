Spanish verb conjugations: `*-person` tags for imperative forms are shifted by one
## Description

All imperative forms of verbs in Spanish have wrong person tags. And they are shifted exactly by one cell: 2nd is replaced by 1st, 3rd by 2nd, and 1st (plural) by 3rd.

Example for "[pasar](https://es.wiktionary.org/wiki/pasar)":

```json
    {
      "form": "pasa^(tú)",
      "tags": [
        "affirmative",
        "singular",
        "first-person"
      ]
    },
    {
      "form": "pasáᵛᵒˢ",
      "tags": [
        "affirmative",
        "singular",
        "first-person"
      ]
    },
    {
      "form": "pase",
      "tags": [
        "affirmative",
        "singular",
        "second-person"
      ]
    },
    {
      "form": "pasemos",
      "tags": [
        "affirmative",
        "singular",
        "third-person"
      ]
    },
```

- "pasa" and "pasá" should have a "second-person" tag instead of "first-person"
- "pase" should have a "third-person" tag instead of "second-person"
- and so on...

However, note that numbers are correct.

## Possible reason

I believe this happens because the template has an empty header cell for 1st person singular in the section for imperative forms:

<img width="1028" alt="Screenshot 2025-01-03 at 18 40 56" src="https://github.com/user-attachments/assets/c0039e77-bc65-4f9a-bab5-5684ccd7e93c" />

## Possible solution

[HIDDEN]

https://github.com/tatuylonen/wiktextract/blob/f889f659cd5690d0f50741810e77a03e8a7e3d1a/src/wiktextract/extractor/es/conjugation.py#L80-L82

[HIDDEN]

However, I don't see why this doesn't also affect number tags. These are probably added somewhere else based on the text inside cells, but I couldn't find it.

### Additional contract requirements

- Every Spanish imperative form must have a person tag matching its grammatical person, not one shifted by a position. For example, singular tú/vos forms are second person, singular usted forms are third person, nosotros forms are first person plural, vosotros forms are second person plural, and ustedes forms are third person plural.
- Preserve the correct number tags.
