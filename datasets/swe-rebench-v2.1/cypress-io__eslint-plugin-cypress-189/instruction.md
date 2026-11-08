cypress/no-pause is not working if the command is chained
I using Intellij with eslint in my Project.

If I use pause as a parent command the linter works fine.

cy.pause();

If I use pause as a child command nothing is highlighted.

cy.get('p').pause();
