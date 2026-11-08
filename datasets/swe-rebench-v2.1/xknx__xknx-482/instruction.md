cover.set_cover_position not stopping with no position_address
**Description of problem:**

Dear xknx team,

covers with **no position_address** do not longer stop when moving the slider in the ha frontpanel to a position e.g. 30%. I attached my according HA config as well as some debug log from HA. This was working in precious versions of Home Assistant for me ( version 0.111).

The **service cover.set_cover_position ist not stopping at this value**. The services cover.close_cover;  service cover.open_cover;  cover.stop_cover are working currently.

Maybe a bug to the reworked travelcalculator / cover.py? It seems to me, that there is no stop movement send to actor when the calculated position is reached.

Remark: My covers do not have a positional feedback. But this applies not only to my knx config, this reproducible to other knx hardware setup with HA as well (a friend of mine reproduces this bug with his knx covers (which have a position_address). When deleting the position address in his config, this bug occurs as well. It would be great, to have this feature back / working again! Let me know, if i can assist you reproducing this bug.

All the best
Jan


- [x ] using Home-Assistant knx plugin

**Version information:**
- xknx / Home-Assistant release with the issue:  0.116.4
- last working xknx / Home-Assistant release (if known): 0.111


**KNX installation:**
<!--
- Manufacturer and model of relevant actors, sensors or interfaces.

-->

**Problem-relevant `xknx.yaml` or `configuration.yaml` entries (fill out even if it seems unimportant):**
[LOG_ha.txt](https://github.com/XKNX/xknx/files/5434327/LOG_ha.txt)
[knx_cover.yaml.txt](https://github.com/XKNX/xknx/files/5434337/knx_cover.yaml.txt)
[knx.yaml.txt](https://github.com/XKNX/xknx/files/5434338/knx.yaml.txt)
![Log](https://user-images.githubusercontent.com/19536666/97102778-98466880-16a8-11eb-93fd-f1ca839db2ed.JPG)
