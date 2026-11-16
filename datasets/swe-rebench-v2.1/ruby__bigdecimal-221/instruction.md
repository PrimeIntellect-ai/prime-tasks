"ERROR(VpDivd): space for remainder too small" for certain division
When upgrading to Ruby 3.1, I noticed a crashing edge-case when dividing by a certain number. It does not happen for bigdecimal < 3.1.1, but its 100% reproducible on 3.1.1.

The reproduction code is simple:

```ruby
BigDecimal('1.0') / BigDecimal('3672577333.6608990499165058135986328125')
```

Happens on both linux and macos.

```
irb(main):001:0> BigDecimal::VERSION
=> "3.1.1"
irb(main):002:0> BigDecimal('63.0') / BigDecimal('3672577333.6608990499165058135986328125')
(irb):2: [BUG] ERROR(VpDivd): space for remainder too small.
ruby 3.0.3p157 (2021-11-24 revision 3fb7d2cadc) [x86_64-linux]

-- Control frame information -----------------------------------------------
c:0034 p:---- s:0198 e:000197 CFUNC  :/
c:0033 p:0012 s:0193 e:000192 EVAL   (irb):2 [FINISH]
c:0032 p:---- s:0190 e:000189 CFUNC  :eval
c:0031 p:0020 s:0182 e:000181 METHOD /usr/local/lib/ruby/3.0.0/irb/workspace.rb:116
c:0030 p:0059 s:0174 e:000172 METHOD /usr/local/lib/ruby/3.0.0/irb/context.rb:450
```

Further debug info is I think irrelevant, but I can attach if needed.
