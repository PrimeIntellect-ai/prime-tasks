Subword tokenisation spacer can mark the beginning of word
Certain sequence noising operations need to retrieve a list of words from the raw list of subword tokens. For example:

* Decoding with word removal/reordering to produce noisy back-translations as in [Scaling BT paper](https://arxiv.org/abs/1808.09381)

* Word omission to support the new contrastive learning feature as in the [contrastive learning paper](https://www.aclweb.org/anthology/P19-1623.pdf)

* Presumably more features relying on word level noise might come up in the future

In these cases the user should specify some details for the sub-tokenisation process:
1. What subword tokens was used? (`decoding_subword_token`)
2. Was that token a joiner or a spacer? (`decoding_subword_token_is_spacer`)

When the user specifies (explicitly or implicitly) a spacer, the framework assumes that the spacer symbol appears at the beginning of each word, similar to what SentencePiece does. However this does not have to be the case, the spacer could also appear at the end of each word - for example [this one does](https://github.com/kovalevfm/SubTokenizer). If that extra sub-tokenisation flexibility is desired, we can add this configuration parameter. A sample implementation could look like [this](https://github.com/steremma/OpenNMT-tf/commit/d109af49911431e424b28def575fb94f07bfec47).

I realise that most user's rely on standard tools that are covered by the current implementation. If there is a user base for which the extra flexibility is desired, I can submit a PR that reads this option from the YAML.

### Additional contract requirements

When spacer mode is selected, the caller-specified subword marker at the end of a token marks a boundary before the following token. This behavior applies to non-default marker values as well as `▁`. Continue to support markers at the beginning of words.
