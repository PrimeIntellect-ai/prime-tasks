bug: Why isn’t space preprocessing consistent between Longest Matching and Multi-Cut?
### Description

Hi,

I noticed that Multi-Cut preprocesses spaces (e.g., grouping consecutive spaces into one token), while Longest Matching does not. Why not preprocess spaces the same way for both tokenizers to ensure consistency?

Thanks for your clarification!

### Expected results

A clear explanation

### Current results

Multi-Cut preprocesses spaces (e.g., grouping consecutive spaces into one token), while Longest Matching does not.

### Steps to reproduce

-

### PyThaiNLP version

5.0.5

### Python version

3.9.6

### Operating system and version

Google Colab Latest

### More info

_No response_

### Possible solution

_No response_

### Files

_No response_

### Additional contract requirements

Longest Matching tokenization must preprocess whitespace consistently with Multi-Cut: consecutive whitespace characters are grouped into a single token, and whitespace runs are retained as separate token elements in the output. This behaviour is provided by the public `segment(text)` function in the `pythainlp.tokenize.longest` module, which returns a list of token strings.
