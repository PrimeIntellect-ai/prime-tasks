Add support for PolyLoss (ICLR 2022)
Hi, thanks for maintaining the library!
What are your thoughts on adding support for PolyLoss (see https://arxiv.org/pdf/2204.12511.pdf, page 10)?

Though it can be implemented externally based on the existing `softmax_cross_entropy`, I would still suggest to add it to the library alongside with some tests

I would also like to volunteer to work on that, if the change seems reasonable :)

### Additional contract requirements

- Add `poly_loss_cross_entropy(logits, labels, epsilon=2.0)` to the library’s loss API.
