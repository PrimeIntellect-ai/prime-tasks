Batch mode InterpolatedLazyVariable __getitem__ doesn't behave like torch.Tensor.__getitem__
`InterpolatedLazyVariable`'s `__getitem__` method has different behavior than `torch.Tensor` in batch mode. Here's a simple example:

```python
matrix = InterpolatedLazyVariable(...) # Some batch mode ILV, say 2 x 10 x 10
eval_matrix = matrix.evaluate() # Get a torch.Tensor of the same matrix.

 # Returns a 2 x 11 tensor containing eval_matrix[0, 0, :] and eval_matrix[1, 2, :]
res1 = eval_matrix[[0, 1], [0, 2], :]

# Returns a 2 x 2 x 11 tensor containing res1 replicated twice.
res2 = matrix[[0, 1], [0, 2], :].evaluate()
```

@gpleiss
