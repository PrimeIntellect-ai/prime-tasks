RGBColor does not correctly convert hexadecimal integer to a tuple of floats
When I input an integer in 0xRRGGBB format to the RGBColor trait, I get the following error:

`... , line 59, in convert_to_color
    ((num / 0x100) & 0xFF) / 255.0,
TypeError: unsupported operand type(s) for &: 'float' and 'int'`

I'm still using TraitsUI 7.0.1, but I think the issue is still relevant. I think this is due to Python converting the result of the first division to a float, and [HIDDEN]

https://github.com/enthought/traitsui/blob/bffbb3b518c57ac1a4178b60b942f0f6a9831cd2/traitsui/null/rgb_color_trait.py#L52

### Additional contract requirements

- When an integer encoded as `0xRRGGBB` is input to `RGBColor`, it must be accepted and converted to a tuple of floating-point RGB values rather than raising the reported `TypeError`.
