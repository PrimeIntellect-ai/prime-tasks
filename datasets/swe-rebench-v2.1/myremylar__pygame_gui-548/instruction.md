UITextEntryLine acceps a Tuple in relative_rect but crashes since its expecting a pygame.Rect
UITextEntryLine acceps a Tuple in relative_rect but crashes since its expecting a pygame.Rect by calling its .size attribute.
```py
AttributeError: 'Tuple' object has no attribute 'size'
```
Steps to reproduce the behaviour:
1. Pass a Tuple in the relative_rect attribute of pygame_gui.elements.UITextEntryLine.

The element should handle correctly the data type of relative_rect and not try to get its .size attribute since it is not a pygame.Rect.

 - OS: Linux Mint 21.2 x86_64
 - Pygame GUI version e.g. 0.6.9
 - Pygame version: 2.4.1
