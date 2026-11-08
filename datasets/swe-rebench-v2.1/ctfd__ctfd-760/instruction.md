dynamic challenges not work when using user mode

**Environment**:

  - CTFd Version/Commit:`2bd310b5d99f4305f8b61076f9af3b7e3c91ba8f`
  - Operating System: `ubuntu 16.04`
  - Web Browser and Version: `Chrome`

when using user mode , `solve_count` always get 0

https://github.com/CTFd/CTFd/blob/master/CTFd/plugins/dynamic_challenges/__init__.py#L95
```
        solve_count = Solves.query \
            .join(Teams, Solves.team_id == Teams.id) \
            .filter(Solves.challenge_id == challenge.id, Teams.banned == False) \
            .count()
```
