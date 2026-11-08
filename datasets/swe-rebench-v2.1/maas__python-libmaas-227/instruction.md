Once a vid is updated subsequent vlan attribute changes fail to save.
Commit 112ca7bd introduced a bug where once the vid is updated subsequent vlan attribute changes fail to save.

ubuntu@hoskins:~/python-libmaas$ git status
On branch master
Your branch is up to date with 'origin/master'.

Untracked files:
  (use "git add <file>..." to include in what will be committed)

        show_libmaas_failure.py

nothing added to commit but untracked files present (use "git add" to track)

ubuntu@hoskins:~/python-libmaas$ git remote -v
origin  https://github.com/maas/python-libmaas.git (fetch)
origin  https://github.com/maas/python-libmaas.git (push)

Checkout the revision that introduced the bug:
ubuntu@hoskins:~/python-libmaas$ git checkout 112ca7bd
Note: checking out '112ca7bd'.

You are in 'detached HEAD' state. You can look around, make experimental
changes and commit them, and you can discard any commits you make in this
state without impacting any branches by performing another checkout.

If you want to create a new branch to retain commits you create, you may
do so (now or later) by using -b with the checkout command again. Example:

  git checkout -b <new-branch-name>

HEAD is now at 112ca7b Issue #210: Every subsequent call to machine.interfaces takes longer (#216)

Run the test script:
ubuntu@hoskins:~/python-libmaas$ ./show_libmaas_failure.py --apikey $API_KEY  http://192.168.211.4:5240/MAAS
Starting vid is 1005
Set vid to 1006
Setting v.name to a new value.
Traceback (most recent call last):
  File "./show_libmaas_failure.py", line 81, in <module>
    sys.exit(entry_point())
  File "./show_libmaas_failure.py", line 77, in entry_point
    main(sys.argv[1:])
  File "./show_libmaas_failure.py", line 71, in main
    v.save()
  File "/home/ubuntu/python-libmaas/maas/client/utils/maas_async.py", line 49, in wrapper
    result = eventloop.run_until_complete(result)
  File "/usr/lib/python3.6/asyncio/base_events.py", line 473, in run_until_complete
    return future.result()
  File "/home/ubuntu/python-libmaas/maas/client/viscera/vlans.py", line 125, in save
    [HIDDEN]
  File "/home/ubuntu/python-libmaas/maas/client/bones/__init__.py", line 308, in __call__
    response = await self.bind(**params).call(**data)
  File "/home/ubuntu/python-libmaas/maas/client/bones/__init__.py", line 469, in dispatch
    raise CallError(request, response, content, self)
maas.client.bones.CallError: PUT http://192.168.211.4:5240/MAAS/api/2.0/fabrics/0/vlans/1005/ -> HTTP 404 Not Found (Not Found)

Roll back to the previous revision:

ubuntu@hoskins:~/python-libmaas$ git checkout 9aa1b491
Previous HEAD position was 112ca7b Issue #210: Every subsequent call to machine.interfaces takes longer (#216)
HEAD is now at 9aa1b49 Support veiwing/updating resource pools for machines (#215)

Rerun the test script:
ubuntu@hoskins:~/python-libmaas$ ./show_libmaas_failure.py --apikey $API_KEY  http://192.168.211.4:5240/MAAS
Starting vid is 1006
Set vid to 1007
Setting v.name to a new value.
vlan now set to vid: 1007 and name: boom

### Additional contract requirements

- After a VLAN's VID is changed and saved, a later change to another VLAN attribute, such as its name, must also save successfully.
- After a VLAN's VID is changed and saved, a later VID change must save successfully using the VLAN's current VID.
