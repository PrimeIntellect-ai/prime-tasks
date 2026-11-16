--readme-path is ignored by the marketplace
Hi, I created an extension and when packaging, I specified the path to the readme file `--readme-path README.marketplace.md`. The `README.marketplace.md` got included into the `visx` package and the package manifest points to it.

Having published the extension, I was surprised that Visual Studio Marketplace ignored the `README.marketplace.md` and shows the `README.md` from GitHub (!!) as a readme.
