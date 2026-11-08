[2.3.5] Problem with intersecting parameters
Hi, first of all, thank you so much for this amazing package!

I recently noticed a problem after upgrading to 2.3.5 from 2.3.4, it seems like the translator "confused" if there are multiple parameters with intersecting names. Here's the example:

translation array:
`'showing'  => 'Showing :from - :to of :total items',`

Result:
`Showing 1 - 1 of 1tal items`

Seems like the translator thought there two instances of "to", even though it's actually "to" and "total".

The expected result is:
`Showing 1 - 1 of 2 items`

This is my first time submitting an issue. Sorry if I mistype something! Thanks!
