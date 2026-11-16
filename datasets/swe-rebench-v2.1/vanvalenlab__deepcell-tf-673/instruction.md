Padding removal function results in zero-size array due to slicing with [0:-0]
## Bug Report

- DeepCell version: 0.12.5
- Python version: 3.10.10
- Operating System: Manjaro Linux 22.1.2

### Description
While running the `predict` method of `CytoplasmSegmentation`, an error is thrown with the message `ValueError: zero-size array to reduction operation maximum which has no identity`.

Upon investigation, the issue seems to be related to the `_untile_output` function in the `Application` class. Specifically, when the `_process` function is called to remove padding from the image, it results in a zero-dimensional array if the padding is zero.

Here is the problematic code ([link](https://github.com/vanvalenlab/deepcell-tf/blob/96aa1f429381edc0db0e962984482c72c0cf2ac8/deepcell/applications/application.py#LL242C17-L242C71)):

```python
[HIDDEN]
```

In Python, using negative zero indexing (like `a[0:-0]`) does not behave as expected. Instead of returning the whole array, it returns an empty array.

### Steps to Reproduce

1. Run the `predict` method of `CytoplasmSegmentation` with an image where y-padding is zero i.e. width of 512 for the default model.

### Expected Behavior
The `_process` function should handle the case where padding is zero, and return the original image in such cases, rather than an empty array. One solution is:

[HIDDEN]

### Actual Behavior
The function returns an empty array if padding is zero, leading to a `ValueError` in later processing steps.

Please let me know if you have any questions or if you need more information.

### Additional contract requirements

- Padding removal must retain the original extent of each zero-padded spatial axis while cropping any nonzero padding from the other spatial axis.
