ENOENT, no such file or directory 'undefined/
When running `ember watson:convert-ember-data-model-lookups`, I get this:

```
ENOENT, no such file or directory 'undefined/'
Error: ENOENT, no such file or directory 'undefined/'
    at Error (native)
    at Object.fs.readdirSync (fs.js:761:18)
    at walkSync (/Users/Tristan/dev/Ludu/node_modules/ember-watson/node_modules/walk-sync/index.js:14:20)
    at module.exports (/Users/Tristan/dev/Ludu/node_modules/ember-watson/lib/helpers/find-files.js:10:13)
    at EmberWatson.transformEmberDataModelLookups (/Users/Tristan/dev/Ludu/node_modules/ember-watson/lib/watson.js:27:15)
    at Class.module.exports.run (/Users/Tristan/dev/Ludu/node_modules/ember-watson/addon/commands/convert-ember-data-model-lookups.js:16:12)
    at Class.<anonymous> (/Users/Tristan/dev/Ludu/node_modules/ember-cli/lib/models/command.js:136:17)
    at lib$rsvp$$internal$$tryCatch (/Users/Tristan/dev/Ludu/node_modules/ember-cli/node_modules/rsvp/dist/rsvp.js:489:16)
    at lib$rsvp$$internal$$invokeCallback (/Users/Tristan/dev/Ludu/node_modules/ember-cli/node_modules/rsvp/dist/rsvp.js:501:17)
    at lib$rsvp$$internal$$publish (/Users/Tristan/dev/Ludu/node_modules/ember-cli/node_modules/rsvp/dist/rsvp.js:472:11)
```

Could it have anything to do with the fact that I'm using a POD structure?

### Additional contract requirements

The model-lookups command must scan the directory given by its first positional argument, defaulting to `app` when no directory is supplied. It must not forward an undefined directory.
