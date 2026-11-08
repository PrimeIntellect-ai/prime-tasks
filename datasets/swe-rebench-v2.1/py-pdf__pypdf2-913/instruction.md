Rename `rotate_clockwise` to `rotate`
## Explanation

In 2.x, there is one method (`rotate_clockwise`) to handle PDF page rotations. The suffix made sense in 1.x as there was `rotateClockwise` and `rotateCounterClockwise`, but in 2.x, given there's just the one method, I feel like it's fine to just drop the `_clockwise` suffix and call it `rotate` and document that the rotation is clockwise (though that can be assumed I think by average user).

We have "prior art" on a similar method with PikePDF: https://pikepdf.readthedocs.io/en/latest/api/models.html?highlight=rotate#pikepdf.Page.rotate

## Code Example

```python
pageObject = reader.pages[0]

# rotate a page clockwise, then counter clockwise:

# in 1.x:
pageObject.rotateClockwise(90)
pageObject.rotateCounterClockwise(90)

# in 2.x currently:
pageObject.rotate_clockwise(90)
pageObject.rotate_clockwise(-90)

# proposed:
pageObject.rotate(90)
pageObject.rotate(-90)
```
