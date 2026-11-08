[Leaflet] Error during installation
Module build failed: Module not found:
"./vendor/symfony/ux-leaflet-map/assets/dist/map_controller.js" contains a reference to the file "@symfony/ux-map/abstract-map-controller".
This file can not be found, please check it for typos or update it if the file got moved.

"./vendor/symfony/ux-leaflet-map/assets/dist/map_controller.js" contains a reference to the file "leaflet/dist/leaflet.min.css".
This file can not be found, please check it for typos or update it if the file got moved.

### Additional contract requirements

- The packaged Leaflet controller must not reference any module that a bundler cannot resolve; in particular, its reference to the shared map controller must resolve.
- The packaged Leaflet controller's stylesheet reference must resolve when the bundler is configured with the alias `leaflet/dist/leaflet.min.css` → `leaflet/dist/leaflet.css`.
