<a href="./default.cfc?method=runRemote">Run tests</a>

<cfset test = new model.test() />

<cfdump var="#test.save({'name'='test'})#"><cfabort>