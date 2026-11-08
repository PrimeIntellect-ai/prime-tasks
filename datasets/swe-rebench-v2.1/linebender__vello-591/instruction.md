Can we re-export `wgpu` with the feature?
I didn't realize until now that the recent `wgpu` feature given to Vello doesn't re-export the version, e.g. `vello::wgpu::<what I need>`

Could we re-export this with the feature flag on?

Particularly, some of the examples in velato/vello_svg use `wgpu` types, and I'd prefer not to keep separately maintained versions in sync.
<img width="626" alt="image" src="https://github.com/linebender/vello/assets/48108917/e1af9184-4a6b-4996-8153-65b06c9e0474">
