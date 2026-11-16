feature: flopy.plot.crosssection plot cell centres (DISU)
I appreciate the plotting utilities in flopy - flopy.plot.crosssection

I use the plot_array and plot_grid.. but the plot_grid only plots the lines - would be nice if there was an option to plot cell centres (and be able to change the marker size/color).

I can extract the grid xyz cell centres gwf.modelgrid.xcellcenters - but it's not obvious how to plot cell centres on DISU cross-sections
(Unless I have missed something...)

Thanks!

### Additional contract requirements

Provide a public `PlotCrossSection.plot_centers` operation for plotting cell centers on cross-section views, including DISU cross-sections. Callers can set marker size with the `s` argument and select marker color with the `color` keyword.
