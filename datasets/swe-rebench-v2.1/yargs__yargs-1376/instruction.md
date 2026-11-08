Using `hasOwnProperty` breaks for config objects with null prototype
I'm loading a config object from a third-party library, then passing it to yargs.  This library happens to return an object with a null prototype.  yargs breaks because it's trying to call `config.hasOwnProperty`.

https://github.com/yargs/yargs/blob/master/lib/apply-extends.js#L22
