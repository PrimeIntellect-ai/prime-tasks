Support for channels first data format with zeropadding1D
Hi Keras team,

It appears that the 1D ZeroPadding layer always assumes a channels-last data format. It would be beneficial to add support for cases where the data format is channels-first. Currently, the 1D ZeroPadding layer does not accept an input variable for data_format, unlike the ZeroPadding2D layer which includes this parameter.

https://github.com/keras-team/keras/blob/v3.3.3/keras/src/layers/reshaping/zero_padding1d.py

Thank you.

### Additional contract requirements

`ZeroPadding1D` must support both `channels_last` and `channels_first` data formats. It pads only the spatial dimension for the selected format; batch and channel values remain unchanged, and the output shape reflects the added padding on that spatial dimension. The selected data format must be retained in the layer configuration so that serialization and reconstruction preserve it.
