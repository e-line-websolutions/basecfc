component {
  this.name = "basecfctests";

  this.rootDir = getDirectoryFromPath( getCurrentTemplatePath());

  this.mappings["/"] = this.rootDir;
  this.mappings["/basecfc"] = this.rootDir;
  this.mappings["/root"] = this.rootDir & "tests";
  this.mappings["/testbox"] = this.rootDir & "../testbox";

  this.datasources["basecfc"] = {
    database = "basecfc",
    host = "192.168.1.45",
    port = "5432",
    driver = "PostgreSQL",
    username = "postgres"
  };

  this.ORMEnabled = true;

  this.ORMSettings = {
    datasource = "basecfc",
    DBCreate = "dropcreate",
    CFCLocation = this.rootDir & "tests/model"
  };

  if( structKeyExists( server, "lucee" ) || structKeyExists( server, "railo" )) {
    // Lucee
    this.datasources["basecfc"] = {
      class = "org.postgresql.Driver",
      connectionString = "jdbc:postgresql://localhost:5432/basecfc",
      username = "postgres"
    };
  }

  function onRequestStart() {
    request.appName = this.name;
    request.context = {
      debug = structKeyExists( url, "debug" ) ? url.debug : false
    };
  }
}