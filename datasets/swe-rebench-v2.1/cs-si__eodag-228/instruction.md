Sentinel SAFE / non-SAFE product types distinction
All providers do not provide Sentinel products in SAFE format, which means for example that searching `S2_MSI_L1C` products on `peps` or `astraea_eod` can return products packaged differently, and differently formatted ids.

We should add more product types to be able to distinguish:
- Sentinel products in SAFE / jp2 format (S2_MSI_L1C peps)
- Sentinel products in non-SAFE / jp2 format (S2_MSI_L1C astraea_eod)
- Sentinel products in cog format (sentinel-s2-l2a-cogs earth_search)

See https://github.com/CS-SI/eodag/issues/136#issuecomment-808082569, #171

### Additional contract requirements

- For the COG case, expose product type `S2_MSI_L2A_COG` and provider `earth_search_cog`.
- Expose distinguishable Sentinel product types for SAFE and non-SAFE (JP2) packaging: `S2_MSI_L1C` (SAFE) and `S2_MSI_L1C_JP2` (non-SAFE), `S2_MSI_L2A` (SAFE) and `S2_MSI_L2A_JP2` (non-SAFE).
