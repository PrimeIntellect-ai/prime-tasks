Language files are not Reading Recursive
I used this plugin but i'm running into a issue.

My lang folder structure is as follow:
```
Lang
| en
  | pages
  | - admin
  | - - dashboard.php
  | pagination.php
  | validation.php
| nl
  | pages
  | - admin
  | - - dashboard.php
  | pagination.php
  | validation.php
| php_en.json
| php_nl.json
  ```
  But if i read the json files, i only see the translations from the files of the root dir of a languages and not the sub folder translations.

  Or is there any fix for it?

  App.js:
  ```js
import './bootstrap';
import '../css/app.css';

import { createApp, h } from 'vue';
import { createInertiaApp } from '@inertiajs/inertia-vue3';
import { InertiaProgress } from '@inertiajs/progress';
import { resolvePageComponent } from 'laravel-vite-plugin/inertia-helpers';
import { ZiggyVue } from '../../vendor/tightenco/ziggy/dist/vue.m';
import { i18nVue } from 'laravel-vue-i18n';

const appName = window.document.getElementsByTagName('title')[0]?.innerText || 'Laravel';

createInertiaApp({
    title: (title) => `${title} - ${appName}`,
    resolve: (name) => resolvePageComponent(`./Pages/${name}.vue`, import.meta.glob('./Pages/**/*.vue')),
    setup({ el, app, props, plugin }) {
        return createApp({ render: () => h(app, props) })
            .use(plugin)
            .use(ZiggyVue, Ziggy)
            .use(i18nVue, {
                resolve: async lang => {
                    const langs = import.meta.glob('../../lang/php_*.json');
                    return await langs[`../../lang/php_${lang}.json`]();
                }
            })
            .mount(el);
    },
});

InertiaProgress.init({ color: '#4B5563' });
```
Vite Config:
```js
import { defineConfig } from 'vite';
import laravel from 'laravel-vite-plugin';
import vue from '@vitejs/plugin-vue';
import i18n from 'laravel-vue-i18n/vite';

export default defineConfig({
    plugins: [
        laravel({
            input: 'resources/js/app.js',
            refresh: true,
        }),
        vue({
            template: {
                transformAssetUrls: {
                    base: null,
                    includeAbsolute: false,
                },
            },
        }),

        // https://github.com/xiCO2k/laravel-vue-i18n
        i18n(),
    ],
});
```


  Versions:
  Laravel 9.38
  PHP: 8.1.0
  Yarn: 1.22.19
  Vite: 3.0.0
  Vue: 3.2.41
