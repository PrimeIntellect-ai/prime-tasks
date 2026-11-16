Bug: Query parameters getting lost while switching between graphFetch and projection mode in QueryBuilder
### Similar issues

- [X] I have searched and found no existing similar issues

### How are you using Studio?

Legend Query

### Current and expected behavior

Current Behaviour:
 When you toggle between graphFetch and projection mode in query builder you notice that the query parameters are getting lost.

Expected Behaviour:
When you toggle between graphFetch and projection mode in query builder query parameters should not get changed.

### Steps to reproduce

Copy and paste the below model data and open the query builder from service editor

### Model data

```text
###Service
Service my::service
{
  pattern: '/e70d2c08-4169-44f1-89d4-0fa9971c3995';
  documentation: '';
  autoActivateUpdates: true;
  execution: Single
  {
    query: businessDate: Date[1]|my::Person.all();
    mapping: my::map;
    runtime:
    #{
      mappings:
      [
        my::map
      ];
    }#;
  }
  test: Single
  {
    data: '';
    asserts:
    [
    ];
  }
}


###Relational
Database my::db
(
  Table PersonTable
  (
    NAME CHAR(200),
    FIRMID INTEGER
  )
  Table FirmTable
  (
    FIRMNAME CHAR(200),
    ID INTEGER
  )

  Join Firm_Person(PersonTable.FIRMID = FirmTable.ID)
)


###Pure
Class my::Firm
{
  legalName: String[1];
  id: Integer[1];
}

Class my::Person
{
  name: String[1];
  firmID: Integer[1];
}


###Mapping
Mapping my::map
(
  *my::Person: Pure
  {
  }
)

```


### Environment

```text
Windows 10
```


### Possible solution and workaround

_No response_

### Contribution

- [X] I would like to work on the fix for this issue
