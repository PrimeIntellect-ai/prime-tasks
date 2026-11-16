Interpretation of colormaps
I was personally surprised with the results of using a very simple colormap `[(0, 0, 0), (1, 1, 1)]` with the image visuals.


![image](https://github.com/pygfx/pygfx/assets/90008/26af706a-6d60-4fd9-b637-f1983be19547)

What I found was that the colormap was sampled as if there were only "two" pixels placed at the position `0.25`, and `0.75`.

This sampling makes sense maybe for images, but it didn't jive with my expectation of colormaps.

In my own shader, I am shifting things and rescaling them so as to sample the full "range" of the colormap.

1D example
```
[HIDDEN]
```

For example, sampling a matplotlib colormap at a value of 0.1 will give you something much closer to 0.1 than the equivalent 2 value colormap in pygfx (pygfx will clamp it to 0).

<details><smmary>Matplotlib code</summary>

```python
import numpy as np
from matplotlib.colors import LinearSegmentedColormap

colors = [(0, 0, 0), (1, 1, 1)]

custom_cmap = LinearSegmentedColormap.from_list('custom_cmap', colors)

print(custom_cmap(0.1))
```

</details>

<details> <summary>PyGFX code</summary>

```python
import numpy as np
from wgpu.gui.auto import WgpuCanvas, run
import pygfx as gfx

canvas = WgpuCanvas(size=(512 * 2 + 100, 400), max_fps=999)
renderer = gfx.renderers.WgpuRenderer(canvas, show_fps=True)
scene = gfx.Scene()
camera = gfx.OrthographicCamera(512 * 2 + 50 + 100, 550)
camera.local.y = 256
camera.local.scale_y = -1
camera.local.x = (512 * 2 + 50)/ 2

cmap = gfx.Texture(
    np.asarray([(0, 0, 0), (1, 1, 1)], dtype='float32'),
    dim=1
)

img = np.arange(256, dtype='float32').reshape(16, 16)
geometry = gfx.Geometry(grid=gfx.Texture(img, dim=2))

image0 = gfx.Image(
    geometry,
    gfx.ImageBasicMaterial(clim=(0, 255))
)
image0.local.scale = 512 / 16, 512/16, 1

scene.add(image0)

image1 = gfx.Image(
    geometry,
    gfx.ImageBasicMaterial(clim=(0, 255), map=cmap)
)
image1.local.scale = 512 / 16, 512/16, 1
image1.local.x = 50 + 512

scene.add(image1)

def animate():
    renderer.render(scene, camera)

if __name__ == "__main__":
    canvas.request_draw(animate)
    run()
```

</details>

Maybe there is an easier way to do this by changing how the GPU interpolates a texture?

Thank you for the discussion.

### Additional contract requirements

Provide `pygfx.utils.cm.create_colormap` for creating a colormap from a sparse list of color stops. It returns a `TextureMap` containing sampled RGBA colors. The resulting colors must include interpolated intermediate colors throughout the normalized range between the stops, rather than treating each stop as an isolated sample.
