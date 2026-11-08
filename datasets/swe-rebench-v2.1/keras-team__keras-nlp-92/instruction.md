Fix rank 1 outputs for WordPieceTokenizer
Right now, a scalar string inputs to the tokenizer will turn into rank 2 outputs, which we do not want. Scalar inputs should result in rank 1 outputs.

See this colab for a reproduction of the issue:
https://colab.research.google.com/gist/mattdangerw/8e1fdbebadf0ff6ff2dc065b2e00db65/rank1wordpiece.ipynb

### Additional contract requirements

- Calling `WordPieceTokenizer` on a single scalar string (a rank-0 string tensor) returns a rank-1 result containing the token IDs, with no extra batch dimension.
