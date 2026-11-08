Implement Default cross Functionality for Base Tensor Type.
<!-- Please make sure that you review this: https://github.com/OpenMined/Docs/blob/master/contributing/guidelines.md  -->
<!-- If you are looking to file a bug make sure to look at the .github/BUG_ISSUE_TEMPLATE.md -->


#### User story:
As a Data Scientist using Syft's Base Tensor type, I want to leverage a default method for computing operations on a Tensor of arbitrary type. For this ticket to be complete `cross` should return a new tensor. For a reference on the operation these perform check out [PyTorch's](http://pytorch.org/docs/master/torch.html#torch.cross) documentation.

<!-- Provide a detailed explaination about the proposed feature, you can draw inspiration from something like this:
https://github.com/OpenMined/PySyft/issues/227 or https://github.com/OpenMined/PySyft/issues/12 -->

#### Acceptance Criteria:

<!-- Provide an outline af all the things that needs to be addressed in order to close this Issue,
be as descriptive as possible -->
 - [ ] If the Base Tensor type's attribute "encrypted" is set to True, it should return a NotImplemented error.
 - [ ] corresponding unit tests demonstrating the correct operation on the Base Tensor type implemented over int and float Tensors.
 - [ ] inline documentation as described over [here](https://github.com/OpenMined/PySyft/blob/85bc68e81a2f4bfc0f0bf6c4252b88d6d7b54004/syft/math.py#L5).

<!-- Thanks for your contributions! -->

### Additional contract requirements

- Add a public method `cross(self, tensor, dim=-1)` on the `TensorBase` class (in `syft.tensor`) that computes the vector cross product of two equally-shaped tensors along dimension `dim` and returns a new `TensorBase`.
- `dim` defaults to `-1` and must be a valid axis of the tensors; the size of the chosen dimension must be 3.
- Raise `ValueError` when the two tensors have mismatched shapes, when `dim` is an invalid axis, or when the size of the chosen dimension is not 3.
- Return `NotImplemented` when either operand tensor is encrypted.
