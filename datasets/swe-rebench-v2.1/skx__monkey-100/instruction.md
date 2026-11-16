Range operator assumes increasing direction
This works:

     puts( 1..5 )

This does not return what you expect:

     puts(10..0)

Instead of "10, 9,.." you get "10, 11, 12 ."

We should be able to count down as appropriate.
