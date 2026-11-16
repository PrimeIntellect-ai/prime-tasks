Are image or pixel masks required for segmentation?
So, we have diverging behavior if we create the plane segmentation. This, no image mask, works:

```python
from pynwb.testing.mock.file import mock_NWBFile
from pynwb.testing.mock.ophys import mock_ImagingPlane, mock_OpticalChannel
from pynwb.testing.mock.device import mock_Device
from pynwb.ophys import ImageSegmentation
from pynwb import NWBHDF5IO
from pynwb.ophys import PlaneSegmentation


nwbfile = mock_NWBFile()

device = mock_Device(name="device")
nwbfile.add_device(device)

imaging_plane = mock_ImagingPlane(name="imaging_plane", device=device)
nwbfile.add_imaging_plane(imaging_plane)

segmentation = ImageSegmentation(name="segmentation")
ophys_module = nwbfile.create_processing_module(name="ophys", description="processing_module")
ophys_module.add(segmentation)

plane_segmentation = PlaneSegmentation(id=[0, 1, 2], imaging_plane=imaging_plane, description="")
segmentation.add_plane_segmentation(plane_segmentation)



with NWBHDF5IO("./test.nwb", "w") as io:
    io.write(nwbfile)

```

But this, using the `nwbfile.add_roi`, does not work:

```python
from pynwb.testing.mock.file import mock_NWBFile
from pynwb.testing.mock.ophys import mock_ImagingPlane, mock_OpticalChannel
from pynwb.testing.mock.device import mock_Device
from pynwb.ophys import ImageSegmentation
from pynwb import NWBHDF5IO
from pynwb.ophys import PlaneSegmentation


nwbfile = mock_NWBFile()

device = mock_Device(name="device")
nwbfile.add_device(device)

imaging_plane = mock_ImagingPlane(name="imaging_plane", device=device)
nwbfile.add_imaging_plane(imaging_plane)

segmentation = ImageSegmentation(name="segmentation")
ophys_module = nwbfile.create_processing_module(name="ophys", description="processing_module")
ophys_module.add(segmentation)

plane_segmentation = PlaneSegmentation(imaging_plane=imaging_plane, description="Test Plane Segmentation")
plane_segmentation.add_roi() # this trows and error
segmentation.add_plane_segmentation(plane_segmentation)



with NWBHDF5IO("./test.nwb", "w") as io:
    io.write(nwbfile)
```

```python
File ~/miniconda3/envs/work/lib/python3.12/site-packages/pynwb/ophys.py:361, in PlaneSegmentation.add_roi(self, **kwargs)
    359 pixel_mask, voxel_mask, image_mask = popargs('pixel_mask', 'voxel_mask', 'image_mask', kwargs)
    360 if image_mask is None and pixel_mask is None and voxel_mask is None:
--> 361     raise ValueError("Must provide 'image_mask' and/or 'pixel_mask'")
    362 rkwargs = dict(kwargs)
    363 if image_mask is not None:

ValueError: Must provide 'image_mask' and/or 'pixel_mask'
```

So at least for the `add_roi` we have a criteria stopping you from doing this. However, this only seems to be enforced at the API level but there is no mention of this on the schema:

https://github.com/NeurodataWithoutBorders/nwb-schema/blob/c288427124fd74fecd00aa83b1e4c20d07298e55/core/nwb.ophys.yaml#L125

What gives?
Is this required and in that case we should add documentation to the schema or is is not and we should remove the check on the API?

What does matlab do @ehennestad?

### Additional contract requirements

A `PlaneSegmentation` with no ROI rows or data and no ROI-mask columns is a valid empty table. Providing IDs without any ROI-mask column (`image_mask`, `pixel_mask`, or `voxel_mask`) must raise `ValueError`. A populated table, meaning one that has rows or column data, whose columns include no ROI-mask column must raise `ValueError`. A ROI-mask column that holds data is accepted.
