Builder images contain duplicate layers
I noticed [this issue with pack](https://github.com/buildpacks/pack/issues/1081) where `pack builder create` produces builder images with multiple copies of an identical layer. This happens when a builder contains metabuildpacks that include some overlapping implementation buildpacks. (A common example is the Paketo Procfile buildpack, which is included in the Paketo Go, Dotnet Core, and Ruby buildpacks, to name a few.)

Out of curiosity, I took a look to see if kpack has the same problem. It seems to. Take a look at [this gist](https://gist.github.com/fg-j/72bc224a8770a5094678385d661cd610) for an analysis of the layers in a builder whose metabuildpacks contain overlapping buildpacks.

The layer duplication creates unnecessary builder size bloat. This can slow down image pulling. But it also poses a larger problem: builders grow rapidly with the addition of each metabuildpack. Since there is an underlying limit to the number of layers that a filesystem driver can package into an image ([for docker's backend this is about 128 layers](https://docs.docker.com/storage/storagedriver/overlayfs-driver/#how-the-overlay2-driver-works)), there will probably come a point where a builder gets too large and can't be built/pushed to the registry!

### Additional contract requirements

Deduplicate builder layers by diff id. This removes duplicate layers that result from two buildpacks in a builder that have the same layer diff id. The distinct buildpacks are still included in the builder's buildpack metadata and order.
