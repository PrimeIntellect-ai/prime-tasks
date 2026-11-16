Non-ASCII input and output are not properly handled
Reading element `BÜTTNER WIDGET COMPANY` from an EDI stream results in the Java String `BÃTTNER WIDGET COMPANY`.

Writing element `BÜTTNER` results in `B�TTNER` being written to the output.
