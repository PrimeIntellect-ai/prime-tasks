Activation of Scope should fire @Initialized event
Both org.jboss.weld.junit.WeldCDIExtension#activateContexts  and
org.jboss.weld.junit.WeldCDIExtension#deactivateContexts
currently don't not fire any Events.

It would be nice to have them fire `@Initialized` and `@Destroyed` events as they would in an application server environment.
