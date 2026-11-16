`apoc.text.clean` should not clean umlauts
In case of e.g. German umlauts `clean` just removes those characters. I assume general expectation is convert those to a base form.

I guess the same issue arises with any non standard text character.

http://stackoverflow.com/questions/1008802/converting-symbols-accent-letters-to-english-alphabet has some solution for this.

Before changing this I'd love to hear comments from others.

### Additional contract requirements

- For the input `German umlaut Ä Ö Ü ä ö ü ß `, `apoc.text.clean` must return `germanumlautaeoeueaeoeuess`.
- - For the input `French çÇéèêëïîôœàâæùûü`, `apoc.text.clean` must return `frenchcceeeeiioaauuue`.
