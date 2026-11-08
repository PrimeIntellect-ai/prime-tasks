Traffic split calculation should only use traffic-split revisions
When creating a traffic split and automatically calculating a percentage rest, all revisions are taken into account, even those the are currently nor part of the traffic distribution:

```
$ kn revision list
NAME           SERVICE   TRAFFIC   TAGS   GENERATION   AGE   CONDITIONS   READY   REASON
random-00002   random    100%             2            37s   3 OK / 4     True
random-00001   random                     1            66s   4 OK / 4     True

$ kn service update random --image rhuss/random:2.0 --traffic 50
Error: unable to allocate the remaining traffic: 50%. Reason: incorrect number of revisions specified. Only 1 revision should be missing
Run 'kn --help' for usage
```

Here only `random-00002` should be taken into account and automatically reduced to 50% (so there should be no error message, but the expected end result should be `random-0002` set to 50% and the new revision `random-00003` should be 50%.

### Additional contract requirements

When automatically allocating the remaining traffic, use only revisions currently in the traffic distribution. In an update with an inactive revision present and one active revision receiving all current traffic, specifying 50% for the new revision must succeed and leave 50% for the active revision.
