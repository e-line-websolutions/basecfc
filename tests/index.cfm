<cfsetting showDebugOutput="false" />

<cfscript>
  param url.reporter="simple";
  param url.directory="root.specs";
  param url.recurse=true;

  include "/testbox/system/runners/HTMLRunner.cfm";
</cfscript>