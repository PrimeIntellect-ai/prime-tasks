Faker is failing on 29th of February on the leap year
* Faker version: 4.0.1
* OS: ubuntu 18.04

Currently, Faker fails to generate a date_of_birth on 29th of February on the leap year, due to the code in here:
https://github.com/joke2k/faker/blob/master/faker/providers/date_time/__init__.py#L1999

        start_date = now.replace(year=now.year - (maximum_age+1))
        end_date = now.replace(year=now.year - minimum_age)

### Steps to reproduce

Execute a faker for date of birth on 29th of February

### Expected behavior

Works as usual

### Actual behavior

Raises exception: ValueError: day is out of range for month
