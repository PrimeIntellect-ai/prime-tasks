Problem with php langs generation
Hi,

I am facing an issue in our project with generation of langs from php files. Our project started out i  think on laravel 7 and as the time passed we updated it to 10 as of now.

However we still have langs in 'resources/lang' directory.

When I tried to specify this path as mentioned in docs in mix.i18n("resources/lang") my build crashes with following error:
```

/var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:69
    if (expr.kind === 'string') {
             ^

TypeError: Cannot read properties of undefined (reading 'kind')
    at parseItem (/var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:69:14)
    at parseItem (/var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:85:12)
    at parseItem (/var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:83:36)
    at /var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:73:46
    at Array.map (<anonymous>)
    at parseItem (/var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:73:32)
    at parseItem (/var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:83:36)
    at /var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:73:46
    at Array.map (<anonymous>)
    at parseItem (/var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:73:32)
    at parseItem (/var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:83:36)
    at /var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:73:46
    at Array.map (<anonymous>)
    at parseItem (/var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:73:32)
    at parse (/var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:65:32)
    at /var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:121:66
    at Array.forEach (<anonymous>)
    at readThroughDir (/var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:114:35)
    at parseAll (/var/www/html/node_modules/laravel-vue-i18n/dist/loader.cjs:41:49)
    at /var/www/html/node_modules/laravel-vue-i18n/dist/mix.cjs:39:141
    at Hook.eval [as call] (eval at create (/var/www/html/node_modules/tapable/lib/HookCodeFactory.js:19:10), <anonymous>:16:1)
    at Hook.CALL_DELEGATE [as _call] (/var/www/html/node_modules/tapable/lib/Hook.js:14:14)
    at /var/www/html/node_modules/webpack/lib/Compiler.js:1168:23
    at Hook.eval [as callAsync] (eval at create (/var/www/html/node_modules/tapable/lib/HookCodeFactory.js:33:10), <anonymous>:22:1)
    at Hook.CALL_ASYNC_DELEGATE [as _callAsync] (/var/www/html/node_modules/tapable/lib/Hook.js:18:14)
    at Compiler.compile (/var/www/html/node_modules/webpack/lib/Compiler.js:1165:28)
    at /var/www/html/node_modules/webpack/lib/Watching.js:218:19
    at Hook.eval [as callAsync] (eval at create (/var/www/html/node_modules/tapable/lib/HookCodeFactory.js:33:10), <anonymous>:22:1)
    at Hook.CALL_ASYNC_DELEGATE [as _callAsync] (/var/www/html/node_modules/tapable/lib/Hook.js:18:14)
    at run (/var/www/html/node_modules/webpack/lib/Watching.js:172:33)
    at /var/www/html/node_modules/webpack/lib/Watching.js:167:6
    at Compiler.readRecords (/var/www/html/node_modules/webpack/lib/Compiler.js:989:5)
    at run (/var/www/html/node_modules/webpack/lib/Watching.js:163:26)
    at Watching._go (/var/www/html/node_modules/webpack/lib/Watching.js:222:3)
    at Watching._invalidate (/var/www/html/node_modules/webpack/lib/Watching.js:423:9)
    at /var/www/html/node_modules/webpack/lib/Watching.js:69:28
    at processTicksAndRejections (node:internal/process/task_queues:78:11)
```

Got any advice please? If I dont specify the path I see the lang folder beign created during the build / watcher process but as soon as it hits 100% it gets deleted.

Thank you.

### Additional contract requirements

- When parsing a PHP translation file, omit entries whose value is an empty array or `null`; those keys must be absent from the parsed result (`undefined`).
