Foreign key relationship between Collection and managed Class
### I'm submitting a
- [ ] bug report.
- [x] feature request.

### Current Behaviour:
<!-- Describe about the bug -->
Presently, if an object is deleted from a Class it would still be there in the collection table in database( if it was previously inserted in a Collection that directly manages that Class). In such case, a GET response from Collection endpoint will show the member available in the database but will throw an InstanceNotFound error when a GET request will be made to view details of the object because it has already been deleted from the Class.

### Expected Behaviour:
<!-- Describe what will happen if bug is removed -->
hydrus should check if an object is also present in the database table of a Collection that directly manages the class and then delete the object from both concurrently. There should be foreign-key relationship between a Class and a Collection that manages that Class. We can use `ondelete=CASCASE` and `onupdate` while creating a foreign key column. Using this, a member could be deleted automatically if it’s available in it’s Class table.

### Steps to reproduce:
<!-- If you can then please provide the steps to reproduce the bug -->

### Snapshot:
<!-- If you can then please provide the screenshot of the issue you are facing -->

### Environment:
<!-- Please provide the following environment details -->
* python version
* pip version
* OS details

### Do you want to work on this issue?
<!-- yes/no -->

### Additional contract requirements

- A Collection that directly manages a Class must store its member reference as a database foreign key to that Class's instance identifier. Deleting a Class instance directly in the database must cascade to the corresponding Collection member; this behavior must not depend solely on cleanup performed by an HTTP request handler.
