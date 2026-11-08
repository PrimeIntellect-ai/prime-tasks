Increase DateTime by 1 day across daylight saving change point fails
<!--
  Hi there! Thank you for discovering and submitting an issue.

  Before you submit this; let's make sure of a few things.
  Please make sure the following boxes are ticked if they are correct.
  If not, please try and fulfill these first.
-->

<!-- Checked checkbox should look like this: [x] -->
- [x] I am on the [latest](https://github.com/sdispater/pendulum/releases/latest) Pendulum version.
- [x] I have searched the [issues](https://github.com/sdispater/pendulum/issues) of this repo and believe that this is not a duplicate.

<!--
  Once those are done, if you're able to fill in the following list with your information,
  it'd be very helpful to whoever handles the issue.
-->

- **OS version and name**: <!-- Replace with version + name --> Manjaro Linux 6.6.0
- **Pendulum version**: <!-- Replace with version --> 2.1.2

## Issue
<!-- Now feel free to write your issue, but please be descriptive! Thanks again 🙌 ❤️ -->
```python
>>> import pendulum; pendulum.datetime(2023,11,5,0,0,tz='America/Chicago') + pendulum.duration(days=1)
DateTime(2023, 11, 5, 23, 0, 0, tzinfo=Timezone('America/Chicago'))
```
The result should be `DateTime(2023, 11, 6, 0, 0, 0, tzinfo=Timezone('America/Chicago'))`. A workaround is using the traditional datetime library as the base datetime:
```python
>>> start = pendulum.datetime(2023,11,5,0,0,tz='America/Chicago')
>>> import datetime
>>> pendulum.instance(datetime.datetime.fromtimestamp(start.timestamp(), tz=start.tzinfo) + pendulum.duration(days=1))
DateTime(2023, 11, 6, 0, 0, 0, tzinfo=Timezone('America/Chicago'))
```

This bug made my customized Airflow time schedule failed yesterday.
