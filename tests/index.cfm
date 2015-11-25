<cftransaction>
  <cfset test = entityNew( "test" ) />
  <cfset mult = entityNew( "multiple" ) />

  <cfset entitySave( test ) />
  <cfset entitySave( mult ) />

  <cfset test.save( { multiples = [ mult ] } ) />
</cftransaction>

<cfdump var="#test#">

<a href="./default.cfc?method=runRemote">Run tests</a>