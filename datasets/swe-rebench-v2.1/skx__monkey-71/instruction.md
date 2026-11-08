Implement switch-statements
I want to allow this to succeed:

```

function test( name ) {
  switch( name ) {
    case /^steve$/i {
       printf("I'm a regexp\n");
    }
    case "Steven" {
	printf("I know you!\n" );
    }
    default {
	printf("I don't know who you are\n" );
    }
  }
}

test( "Steve" );    // Regexp match
test( "Steven" );   // Literal match
test( "Bob" );      // Unhandled case

```

**NOTE**: I explicitly use blocks here, because fall-throughs are evil :)

### Additional contract requirements

A switch statement with a parenthesized controlling expression and block-delimited `case` and `default` arms must parse successfully. A regular-expression case matches when its expression matches the controlling value, and a literal case matches when its value equals the controlling value. If no case matches, the `default` arm runs when present. Once a matching arm runs, no later arm in that switch runs.
