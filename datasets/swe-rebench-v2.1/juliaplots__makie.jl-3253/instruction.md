Error: Multiple colormaps found for plot
Hi, it looks like the latest release (GLMakie v0.8.10) broke something

- [x] are you running newest version (version from docs) ?
   - the issue arises when updating to GLMakie v0.8.10 or WGLMakie v0.8.14. Older versions seem to work fine.
- [x] can you reproduce the bug with a fresh environment ? (`]activate --temp; add Makie`)
   - yes, a fresh environment containing only `GLMakie` seems to be the easiest way to reproduce the issue
- [x] What platform + GPU are you on?
   - I'm on Ubuntu with an NVIDIA GeForce RTX 3050 card.
<details><summary>GPU info</summary>

```
$ nvidia-smi
Mon Sep 25 08:21:46 2023
+---------------------------------------------------------------------------------------+
| NVIDIA-SMI 535.86.05              Driver Version: 535.86.05    CUDA Version: 12.2     |
|-----------------------------------------+----------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |         Memory-Usage | GPU-Util  Compute M. |
|                                         |                      |               MIG M. |
|=========================================+======================+======================|
|   0  NVIDIA GeForce RTX 3050 ...    Off | 00000000:01:00.0 Off |                  N/A |
| N/A   43C    P0             ERR! /  60W |      8MiB /  4096MiB |      0%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+

+---------------------------------------------------------------------------------------+
| Processes:                                                                            |
|  GPU   GI   CI        PID   Type   Process name                            GPU Memory |
|        ID   ID                                                             Usage      |
|=======================================================================================|
|    0   N/A  N/A      3291      G   /usr/lib/xorg/Xorg                            4MiB |
+---------------------------------------------------------------------------------------+
```
</details>

The issue I'm having is triggered by a code heavily inspired by the ["volumeslices example"](https://docs.makie.org/stable/reference/plots/volumeslices/#volumeslices) in the Makie documentation. The only addition I made (which seems to be relevant) is a Colorbar:
```julia
using GLMakie

x = let t=0:0.02:2π
    [sin(x)*cos(y)*cos(z) for x in t, y in t, z in t]
end

function volumeslices(x)
    (m, n, p) = size(x)
    fig = Figure()

    # Volume slices
    ax = LScene(fig[1, 1][1, 1], show_axis=false)
    plt = volumeslices!(ax, 1:m, 1:n, 1:p, x,
                        colormap=:bluesreds)
    Colorbar(fig[1, 1][1, 2], plt)  # This seems to be the problem

    # Sliders
    sgrid = SliderGrid(
        fig[2, 1],
        (label = "yz plane - x axis", range = 1:m),
        (label = "xz plane - y axis", range = 1:n),
        (label = "xy plane - z axis", range = 1:p),
    )
    sl_yz, sl_xz, sl_xy = sgrid.sliders
    on(sl_yz.value) do v; plt[:update_yz][](v) end
    on(sl_xz.value) do v; plt[:update_xz][](v) end
    on(sl_xy.value) do v; plt[:update_xy][](v) end

    set_close_to!(sl_yz, m÷2)
    set_close_to!(sl_xz, n÷2)
    set_close_to!(sl_xy, p÷2)

    fig
end

volumeslices(x)
```

The code above works fine with WGLMakie v0.8.13 (my originally intended backend) and GLMakie v0.8.9 (which I tested afterwards to check whether this was backend-dependent). But an error arises after upgrading to WGLMakie v0.8.14 or GLMakie v0.8.10:
```
ERROR: LoadError: Multiple colormaps found for plot Combined{Makie.volumeslices, Tuple{UnitRange{Int64}, UnitRange{Int64}, UnitRange{Int64}, Array{Float64, 3}}}, please specify which one to use manually. [HIDDEN]
Stacktrace:
 [1] error(s::String)
   @ Base ./error.jl:35
 [2] extract_colormap_recursive(plot::Combined{Makie.volumeslices, Tuple{UnitRange{Int64}, UnitRange{Int64}, UnitRange{Int64}, Array{Float64, 3}}})
   @ Makie ~/.julia/packages/Makie/1hq9u/src/makielayout/blocks/colorbar.jl:79
 [3] Colorbar(fig_or_scene::GridSubposition, plot::Combined{Makie.volumeslices, Tuple{UnitRange{Int64}, UnitRange{Int64}, UnitRange{Int64}, Array{Float64, 3}}}; kwargs::Base.Pairs{Symbol, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
   @ Makie ~/.julia/packages/Makie/1hq9u/src/makielayout/blocks/colorbar.jl:86
 [4] Colorbar(fig_or_scene::GridSubposition, plot::Combined{Makie.volumeslices, Tuple{UnitRange{Int64}, UnitRange{Int64}, UnitRange{Int64}, Array{Float64, 3}}})
   @ Makie ~/.julia/packages/Makie/1hq9u/src/makielayout/blocks/colorbar.jl:84
 [5] volumeslices(x::Array{Float64, 3})
   @ Main ~/projets/DataViewer.jl/bug/bug.jl:15
 [6] top-level scope
   @ ~/projets/DataViewer.jl/bug/bug.jl:36
 [7] include(fname::String)
   @ Base.MainInclude ./client.jl:478
 [8] top-level scope
   @ REPL[3]:1
in expression starting at /home/francois/projets/DataViewer.jl/bug/bug.jl:36
```

All in all, I was surprised because I wasn't expecting anything to break for these releases. On the other hand, I'm very new to Makie, so it might very well be that I was using the Colorbar in an unintended way in the first place...

What do you think?

And many thanks for the great packages and the tremendous amount of work you put in them!

### Additional contract requirements

A `Colorbar` can be constructed directly from a `volumeslices` plot. The resulting colorbar reflects the plotted data's limits and uses the colormap configured for that plot.
