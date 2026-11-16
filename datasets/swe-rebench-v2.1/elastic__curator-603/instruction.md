Fix regex to not escape non-special characters.
I am having some indices in elasticsearch whose naming format is `elk-console-YYYY-MM-DDtHH`. For example:-

```
elk-console-2016-03-30t14
elk-console-2016-03-30t16
```
I want to delete all indices which are more than 1 hour old using curator. So I tried executing the below command:-

`curator --host localhost delete indices --older-than 1 --time-unit hours --timestring '%Y-%m-%dt%H'`

But it is giving me the following output:-

```
2016-04-22 16:27:36,049 INFO      Job starting: delete indices
2016-04-22 16:27:36,058 INFO      Pruning Kibana-related indices to prevent accidental deletion.
2016-04-22 16:27:36,058 WARNING   No indices matched provided args: {'regex': None, 'index': (), 'suffix': None, 'newer_than': None, 'closed_only': False, 'prefix': None, 'time_unit': 'hours', 'timestring': u'%Y-%m-%dt%H', 'exclude': (), 'older_than': 1, 'all_indices': False}
No indices matched provided args: {'regex': None, 'index': (), 'suffix': None, 'newer_than': None, 'closed_only': False, 'prefix': None, 'time_unit': 'hours', 'timestring': u'%Y-%m-%dt%H', 'exclude': (), 'older_than': 1, 'all_indices': False}
```
I also tried executing the below command:-

`curator --host localhost delete indices --older-than 1 --time-unit hours --timestring '%Y-%m-%dt%H' --prefix elk-console-`

But still getting the below error:-

```
2016-04-22 16:48:43,848 INFO      Job starting: delete indices
2016-04-22 16:48:43,856 INFO      Pruning Kibana-related indices to prevent accidental deletion.
2016-04-22 16:48:43,856 WARNING   No indices matched provided args: {'regex': None, 'index': (), 'suffix': None, 'newer_than': None, 'closed_only': False, 'prefix': u'elk-console-', 'time_unit': 'hours', 'timestring': u'%Y-%m-%dt%H', 'exclude': (), 'older_than': 1, 'all_indices': False}
No indices matched provided args: {'regex': None, 'index': (), 'suffix': None, 'newer_than': None, 'closed_only': False, 'prefix': u'elk-console-', 'time_unit': 'hours', 'timestring': u'%Y-%m-%dt%H', 'exclude': (), 'older_than': 1, 'all_indices': False}
```
I also tried without using `'` in the `timestring` but still no luck.

Environment:-

- Curator 3.5.1
- Elasticsearch - 2.3.1
