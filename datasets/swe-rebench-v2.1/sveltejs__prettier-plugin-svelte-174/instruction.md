Quotes inside if blocks
Inside if blocks, double quotes are replaced by single quotes when running prettier with this plugin. For example,

    {#if foo === "bar"}
      <div>baz</div>
    {/if}

is changed to

    {#if foo === 'bar'}
      <div>baz</div>
    {/if}

Most (all?) other places double quotes are enforced. Is this intentional, or can quotes inside if blocks also be enforced as double?
