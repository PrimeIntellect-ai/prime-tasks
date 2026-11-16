typos-cli Crash Report
name = 'typos-cli'
operating_system = 'windows'
crate_version = '1.0.5'
explanation = '''
Panic occurred in file 'C:\Users\brian\.cargo\registry\src\github.com-1ecc6299db9ec823\typos-cli-1.0.5\src\policy.rs' at line 90
'''
cause = '[HIDDEN]'
method = 'Panic'
backtrace = '''

   0: 0x7ff7059f4f79 - <unresolved>
   1: 0x7ff705a1a1e0 - <unresolved>
   2: 0x7ff705a1a032 - <unresolved>
   3: 0x7ff7058a68b3 - <unresolved>
   4: 0x7ff7058b071e - <unresolved>
   5: 0x7ff7058a5b64 - <unresolved>
   6: 0x7ff7058ecd9d - <unresolved>
   7: 0x7ff7058ede8f - <unresolved>
   8: 0x7ff7058f56c4 - <unresolved>
   9: 0x7ff7058f032f - <unresolved>
  10: 0x7ff7058f55e9 - <unresolved>
  11: 0x7ff7059f850a - <unresolved>
  12: 0x7fffb9f37034 - BaseThreadInitThunk
  13: 0x7fffba122651 - RtlUserThreadStart'''

### Additional contract requirements

- Running `typos .` or `typos` must complete without panicking and exit with status 2.
