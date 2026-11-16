robocop format --check does not seem to return correct exit code
Used robocop version 6.0.2

0 exit code is returned even files would be reformatted:

$ robocop format --check --line-length 140
Would reformat robot/resources/SEC/crl.resource
Would reformat robot/resources/SEC/gnmi.resource

2 files would be reformatted, 75 files would be left unchanged.
$ echo $?
0

Using robotidy this returns exit code 1 and according to documentation I
understand that "robocop format" should work similarly.
