getFrom on Mail object does not return correct value
#### Issue Summary

[getFrom in Mail.java](https://github.com/sendgrid/sendgrid-java/blob/master/src/main/java/com/sendgrid/helpers/mail/Mail.java#L64) requires an Email object then just returns it.

#### Steps to Reproduce

1. Create new Mail object.
2. Set the from field on the mail object to any Email.
3. call `.getFrom` on mail object.
4. Notice what's returned is the Email object you're required to give.

It should return the Email object that was given in `setFrom`.

#### Technical details:

* sendgrid-java Version: master
* Java Version: 1.8
