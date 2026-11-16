CampbellResults.plot() - damping ratio and filtering
I have started using Ross 1.0.0, and have some two suggestions for improving plotting of Campbell results. My goal is to incorporate changes that may be of interest to other users, so I do not have to change the modules manually every time I update.

Damping ratio: We use damping ratio, not log dec. There should be an option for plotting using damping ratio:
1. The damping ratio could be passed to CampbellResults, or calculated in plot. [HIDDEN]
2. The color axis should be reversed when using damping ratio: coloraxis_colorscale="rdbu"
3. Change text: coloraxis_colorbar=dict(title=dict(text="<b>Damping ratio</b>", side="right"))

Filtering: The RAPPID rotordynamic software has options for filtering the modes shown on the campbell diagram. For example, modes with high damping may not be of interest, so we can supply options for a range of damping ratios that should be included (or left out) of the plot. Also, I had some 0.5 cpm modes that I didn't want to show, so filtering of frequencies could also be optional. Filtering of machine speeds is easily obtained by limiting the X-axis, which may be done outside of the plot function.
I did this filtering manually, something like:
                whirl_mask = whirl_i == whirl_dir
                # lpa 2021-02-25 added a second masking for high damping, and zero modes
                damping_mask = log_dec_i < lpa_damping
                freq_mask = w_i > lpa_low_freq
                lpa_mask = whirl_mask & damping_mask & freq_mask

### Additional contract requirements

- `CampbellResults.plot` accepts a `damping_parameter` argument (default `"log_dec"`) that selects which damping metric is displayed. The accepted values are `"log_dec"` and `"damping_ratio"`; any other value raises `ValueError`.
- `CampbellResults.plot` accepts a `frequency_range` argument (default `None`) giving optional `(min, max)` limits for the natural frequencies that are plotted. It accepts either a plain tuple or a Pint Quantity (for example `Q_((2000, 10000), "RPM")`). Modes whose natural frequency lies outside the range are omitted from the plot. A plain tuple is interpreted in rad/s, regardless of `frequency_units`; a Pint Quantity is converted from its own units.
- `CampbellResults.plot` accepts a `damping_range` argument (default `None`) giving optional `(min, max)` limits for the selected damping metric. Modes whose damping value lies outside the range are omitted from the plot.
- The figure axes are labelled with the requested frequency units.
