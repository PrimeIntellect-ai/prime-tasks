Implement Default eq Functionality for Base Tensor Type
**User Story A:** As a Data Scientist using Syft's Base Tensor type, we want to implement a default method for computing operations on a Tensor of arbitrary type. For this ticket to be complete, eq() should return a new tensor and eq_() should perform the operation inline. For a reference on the operation this performs check out [PyTorch](http://pytorch.org/docs/master/tensors.html)'s documentation.

**Acceptance Criteria:**
- If the Base Tensor type's attribute "encrypted" is set to True, it should return a NotImplemented error.
- a unit test demonstrating the correct operation on the Base Tensor type implemented over int and float Tensors.
- inline documentation in the python code. For inspiration on inline documentation, please check out [PyTorch](http://pytorch.org/docs/master/tensors.html)'s documentation for this operator.
