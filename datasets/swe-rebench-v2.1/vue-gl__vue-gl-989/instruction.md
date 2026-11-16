VueGL + Nuxt: Cannot read property 'trim' of undefined
I created a project with Nuxt (2.14.0), VueGL (0.22.0) and Three (0.117.1) packages. Then I created 3 pages, each one with a different VueGL example. Each page have only one section with `vgl-` components inside, all of they imported and exposed to the template. This is [the repository](https://github.com/ErickPetru/tdcsp2020-vuegl) of the project.

When in development (`yarn dev`), I receive an error when trying to navigate between pages with `$router.push` or `nuxt-link`:

    TypeError: Cannot read property 'trim' of undefined
      at ze (vue-gl.esm.js?2692:1)
      at VueComponent.beforeDestroy (vue-gl.esm.js?2692:1)
      ...

Strangely, I have no error if I reload the page from scratch (i.e. <kbd>F5</kbd>) or even if I run the project from `dist` folder, after using `yarn generate` (as you can see it working without errors in [the deployed static site](https://tdcsp2020-vuegl.netlify.app/).
