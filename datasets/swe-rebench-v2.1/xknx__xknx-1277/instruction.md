Feature Request: Improve generic DPT handling
Part 1:

It seems that some DPT parsing is implemented in remote values (e.g. [DPT 251.600](https://github.com/XKNX/xknx/blob/92b80c22827b5d5725d2f00118a40727b06dd187/xknx/remote_value/remote_value_color_rgbw.py#L49)). This makes these DPTs unavailable for generic transcoding via [transcoder_by_dpt](https://github.com/XKNX/xknx/blob/92b80c22827b5d5725d2f00118a40727b06dd187/xknx/dpt/dpt.py#L135) or [transcode_by_value_type](https://github.com/XKNX/xknx/blob/92b80c22827b5d5725d2f00118a40727b06dd187/xknx/dpt/dpt.py#L146).

Is there any deeper reason, that those DPTs are not part of the standard DPT handling? Is it, because they consist out of multiple values (in the RGBW case)?

If yes, followup question: is there a possibility to restructure the code to generically (via DPT main and sub number) get transcoders for those DPTs as well?

Part 2:

Some DPT implementations (like [DPTDate](https://github.com/XKNX/xknx/blob/92b80c22827b5d5725d2f00118a40727b06dd187/xknx/dpt/dpt_date.py#L12) seem to lack dpt_main_number and dpt_sub_number definitions from what I see.

Is that on purpose, am I missing something or is it just not implemented yet?

I'm happy to provide PRs to improve the handling of this, once it's clear, how it should be done.

### Additional contract requirements

The multi-value XY-Y color datapoint (DPT 242.600) must be available through generic transcoder lookup by its main and sub numbers, rather than only through remote-value-specific handling. Encoding and decoding through that transcoder must preserve the established KNX payload behavior described above.

XY-Y values accepted and reported by Light and its remote value must use the structured `XYYColor` value from `xknx.dpt.dpt_color`, carrying an optional color pair and optional brightness. Setting and reading these values must preserve their color and brightness, while retaining the established six-octet KNX encoding.
