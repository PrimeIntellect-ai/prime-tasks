Malformed classifications being saved that break exports
Occasionally, classification export jobs for a given project or workflow will mysteriously vanish and unhelpful NoMethodErrors show up in Honeybadger. This is due to malformed classifications being saved by PFE and when the exporter tries to untangle them, it chokes and dies silently. This seems to happen with huge tasks consisting of many dropdowns and combos.

I've tracked down a few examples which will hopefully help us track this down. I've formatted them but put them in gists because lordy they're humungous. Project 3414. workflow 5919. There's a significant number of these classifications for this project/workflow and tbh I'm not sure yet how we fix/clean these so that exports run once we stop this from happening.

Workflow task definition:
https://gist.github.com/zwolf/f00b4f67629dc465aecbe8be9ffd9fc8

Here's an annotation that causes the NoMethodError in the exporter:
https://gist.github.com/zwolf/ed952817b4308ca3d64c6c972d299093

Seems like this kind of thing could be the culprit:
```
      {
        "task": "T13",
        "value": [
          null,
          null,
          {
            "value": "Canada",
            "option": false
          }
        ]
      },
```

cc: @mcbouslog / @trouille

### Additional contract requirements

When a dropdown task has no annotation values (an empty `value` array), it must produce one valid unanswered entry for each configured select. Each such entry has `value: null` and `option: false`, so no select is represented by a bare `null`. This applies both when the task first appears and when it changes to a task whose annotation values are empty. This concerns generating defaults for an empty values array; it does not require rewriting a non-empty incoming annotation.
