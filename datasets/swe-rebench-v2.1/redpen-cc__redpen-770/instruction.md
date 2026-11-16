Document validators should be located under `cc.redpen.validator.document`
Just like `section` or `sentence` validators, validators overriding `validate(Document document)` should be located under `cc.redpen.validator.document`.

Currently, some validators (e.g. `FrequentSentenceStartValidator`) are located under `cc.redpen.validator.section`.
