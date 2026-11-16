Split "License" into "License" and "Copyright"
**Description**
There is a difference between the License name and the actual Copyright text. This means that the properties in the Package class need to change and the retrieval methods need to change

**Implementation**
1. Add "copyright" to the Package class
2. Add a method of retrieval for "copyright" text

**References**
Some places in the code base to look for reference implementations if any

**Super Issues**
#239

### Additional contract requirements

- Treat the license name and copyright text as separate package values. `Package.copyright` must be readable and assignable; when unset, it returns an empty string.
- This request concerns Package metadata, not end-to-end collection from package sources. `Package.fill` must populate the copyright value when its input mapping contains `copyright`, and `Package.to_dict` must include the current copyright value under the `copyright` key.
