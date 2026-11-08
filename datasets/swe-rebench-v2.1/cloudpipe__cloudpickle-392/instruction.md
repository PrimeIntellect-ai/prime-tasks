Expose CloudPickler as Pickler instead of pickle.Pickler
Hi,

I don't know whether there is a convention what `<pickle_module>.Pickler` is but it seems that some projects [1] assume that they can use it.

Unfortunately, `Cloudpickle.Pickler` is pickle's Pickler. It might be helpful if it points to `cloudpickle.CloudPickler`.

If the solution is to simply [HIDDEN], I'm happy to create a PR for that.

[1] https://github.com/pytorch/pytorch/issues/38098
