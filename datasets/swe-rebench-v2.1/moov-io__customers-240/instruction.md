Customer phone numbers can not be deleted.
Customers Version: v0.5.0-dev24

**What were you trying to do?**
Modify and delete a customer's phone numbers by PUTing an updated customer object to `/customers/{customerID}`.


**What did you expect to see?**
Removing a phone number object from the `phones` array and PUTing the new object will remove that phone from the customer.


**What did you see?**
Phone numbers can not be removed by a PUT to `/customers/{customerID}`
Modifying a number will create a duplicate of that number in the array.


**How can we reproduce the problem?**
Modify or delete a phone number from an existing customer object and PUT the result to `customers/{customerID}
