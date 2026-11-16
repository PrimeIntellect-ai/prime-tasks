The "extends" field in Tsconfig is not supported
Hello,

I'm trying to use resolve-tspaths in a mono-repo but it seems that the extends in tsconfig is not supported.
Here is an example repo where you can see the problem: [example project](https://github.com/Nooka10/resolve-tspaths-test)

The backend's tsconfig extends `tsconfig/server.json`, which extends `packages/tsconfig/server.json` which extends `packages/tsconfig/base.json`.

The `base.json` config contains the paths but when you run the `build` command, you get an error saying that `compilerOptions.paths is not set in tsconfig`...

<img width="666" alt="Capture d’écran 2023-10-12 à 09 55 05" src="https://github.com/benyap/resolve-tspaths/assets/11243999/f2e1c5a1-110e-4db1-9185-044e4965e2ff">

If you copy the content of the `base.json` file in `backend/tsconfig.json`, then the build works perfectly...

Thanks for the help!
