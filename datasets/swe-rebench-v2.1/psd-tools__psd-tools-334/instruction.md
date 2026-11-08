Toggling layer visibility on and off causes incorrect compositing
### **Describe the bug**
Toggling visibility of layers on and off causes layers to be permanently ignored after compositing once. Using debug logging, it appears that the `bbox` or `viewport` is getting corrupted after compositing, which prevents further meaningful changes to layer visibility and continued compositing.

### **To Reproduce**
Steps to reproduce the behavior:
- Run the script below on the PSD below.

Basic minimal script. This script will search for any layers called `scene ...` and then toggle each one on and off in turn, and export each result.
```python
import pathlib
import re
import logging

from psd_tools import PSDImage

scene_regex = re.compile('scene (\d+).*')

def find_scene_layers(psd):
    return list(filter(lambda layer: scene_regex.match(layer.name), psd.descendants()))

def export_variants(file_name):
    psd = PSDImage.open(file_name)
    png_name = pathlib.Path(file_name).with_suffix('.png')

    scene_layers = find_scene_layers(psd)
    for layer in scene_layers:
        layer.visible = False

    for layer in scene_layers:
        layer.visible = True
        print(layer)
        image = psd.composite(ignore_preview=True)
        layer.visible = False
        scene_number = scene_regex.match(layer.name)[1]
        export_name = png_name.with_stem(f'{png_name.stem}-{scene_number}')
        image.save(export_name)

if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG)
    export_variants('test.psd')
```

### **Expected behavior**
Toggling various layers on and off and compositing again should yield correct composited images.
Here is the incorrect results; Only the first composite works correctly, and after that they are all broken:
![image](https://user-images.githubusercontent.com/82557197/192174352-a9e0f389-a473-429c-bce9-c96f436311a1.png)

These should be the correct results (done by exporting manually from a paint program):
![image](https://user-images.githubusercontent.com/82557197/192174471-8a5f3311-827d-4fc4-a165-9fddc8b78ef6.png)

### **File and screenshots**
Sample small PSD:
[test.zip](https://github.com/psd-tools/psd-tools/files/9642152/test.zip)

### **Environment**
 - Python [3.9.5]
 - Version [v1.9.22]

### **Additional context**
Here is the layer composition of `test.psd`:
![image](https://user-images.githubusercontent.com/82557197/192174692-3aafc84d-ba94-4c7b-98e7-051351691da7.png)

Here is the debug log associated with running the script above. Notice the logs after `Group('scene 2')` and `Group('scene 3')` where it outputs `DEBUG:psd_tools.composite:Out of viewport Group('scene 2')`. This seems to indicate where the problem may be occurring, as this output seems incorrect.
```
DEBUG:psd_tools.psd:read FileHeader(version=1, channels=3, height=200, width=200, depth=8, color_mode=<ColorMode.RGB: 3>)
DEBUG:psd_tools.psd.color_mode_data:reading color mode data, len=0
DEBUG:psd_tools.psd.image_resources:reading image resources, len=80
DEBUG:psd_tools.psd.layer_and_mask:reading layer and mask info, len=14230, offset=114
DEBUG:psd_tools.psd.layer_and_mask:reading layer info, len=14222
DEBUG:psd_tools.psd.layer_and_mask:  read layer record, len=140
DEBUG:psd_tools.psd.layer_and_mask:  read layer record, len=142
DEBUG:psd_tools.psd.layer_and_mask:  read layer record, len=118
DEBUG:psd_tools.psd.layer_and_mask:  read layer record, len=142
DEBUG:psd_tools.psd.layer_and_mask:  read layer record, len=114
DEBUG:psd_tools.psd.layer_and_mask:  read layer record, len=146
DEBUG:psd_tools.psd.layer_and_mask:  read layer record, len=142
DEBUG:psd_tools.psd.layer_and_mask:  read layer record, len=114
DEBUG:psd_tools.psd.layer_and_mask:  read layer record, len=146
DEBUG:psd_tools.psd.layer_and_mask:  read layer record, len=142
DEBUG:psd_tools.psd.layer_and_mask:  read layer record, len=114
DEBUG:psd_tools.psd.layer_and_mask:  read layer record, len=146
DEBUG:psd_tools.psd.layer_and_mask:  read layer record, len=130
DEBUG:psd_tools.psd.layer_and_mask:  read layer records, len=1738
DEBUG:psd_tools.psd.layer_and_mask:  read channel image data, len=12483
DEBUG:psd_tools.psd.layer_and_mask:reading global layer mask info, len=0
DEBUG:psd_tools.psd.image_data:  read image data, len=4808
Group('scene 1' size=50x50)
DEBUG:psd_tools.composite:Compositing PixelLayer('Background' size=200x200)
DEBUG:psd_tools.composite:Compositing Group('fg' size=200x200)
DEBUG:psd_tools.composite:Compositing PixelLayer('Layer1' size=200x200)
DEBUG:psd_tools.composite:Compositing Group('scene 1' size=50x50)
DEBUG:psd_tools.composite:Compositing PixelLayer('base' size=50x50)
DEBUG:psd_tools.composite:Compositing Group('scene 2' invisible)
DEBUG:psd_tools.composite:Ignore Group('scene 2' invisible)
DEBUG:psd_tools.composite:Compositing Group('scene 3' invisible)
DEBUG:psd_tools.composite:Ignore Group('scene 3' invisible)
DEBUG:psd_tools.composite:Skipping alpha: 1
Group('scene 2')
DEBUG:psd_tools.composite:Compositing PixelLayer('Background' size=200x200)
DEBUG:psd_tools.composite:Compositing Group('fg' size=200x200)
DEBUG:psd_tools.composite:Compositing PixelLayer('Layer1' size=200x200)
DEBUG:psd_tools.composite:Compositing Group('scene 1' size=50x50 invisible)
DEBUG:psd_tools.composite:Ignore Group('scene 1' size=50x50 invisible)
DEBUG:psd_tools.composite:Compositing Group('scene 2')
DEBUG:psd_tools.composite:Out of viewport Group('scene 2')
DEBUG:psd_tools.composite:Compositing Group('scene 3' invisible)
DEBUG:psd_tools.composite:Ignore Group('scene 3' invisible)
DEBUG:psd_tools.composite:Skipping alpha: 1
Group('scene 3')
DEBUG:psd_tools.composite:Compositing PixelLayer('Background' size=200x200)
DEBUG:psd_tools.composite:Compositing Group('fg' size=200x200)
DEBUG:psd_tools.composite:Compositing PixelLayer('Layer1' size=200x200)
DEBUG:psd_tools.composite:Compositing Group('scene 1' size=50x50 invisible)
DEBUG:psd_tools.composite:Ignore Group('scene 1' size=50x50 invisible)
DEBUG:psd_tools.composite:Compositing Group('scene 2' invisible)
DEBUG:psd_tools.composite:Ignore Group('scene 2' invisible)
DEBUG:psd_tools.composite:Compositing Group('scene 3')
DEBUG:psd_tools.composite:Out of viewport Group('scene 3')
DEBUG:psd_tools.composite:Skipping alpha: 1
```

### Additional contract requirements

- `Layer.visible` is a writable boolean property; assigning to it changes the layer's visibility.
- `Layer.bbox` is a read-only property returning the layer's bounding box as a `(left, top, right, bottom)` tuple of integers. An invisible group has bounding box `(0, 0, 0, 0)`.
