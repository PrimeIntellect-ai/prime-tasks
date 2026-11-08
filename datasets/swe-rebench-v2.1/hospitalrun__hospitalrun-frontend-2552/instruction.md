Lab - In the Request Lab routine make the visit field required
## 🐛 Bug Report

When **Request Lab** for a patient without any visit, it will crash.

## To Reproduce

Steps to reproduce the behavior:
1. Create an patient without adding a visit
2. Click **Request Lab**, input the patient field, leave the visit field blank since it is not required.
3. Notice the crash/error (see screenshot in comments)

## Expected behavior

Request Lab should behave similar to **New Imaging Request** i.e. make the visit field required

## Technical Details

Make the visit field required (as in Imaging Request)

## Your Environment

- *node version*: 12
- *os*: Windows
