component {
  this.name = "basecfctests";

  this.rootDir = getDirectoryFromPath( getCurrentTemplatePath());

  this.mappings = {
    "/" = this.rootDir,
    "/basecfc" = this.rootDir,
    "/root" = this.rootDir & "tests",
    "/testbox" = this.rootDir & "../testbox"
  };

  this.datasources["basecfc"] = getDatasourceConfig();

  this.ORMEnabled = true;

  this.ORMSettings = {
    datasource = "basecfc",
    DBCreate = "dropcreate",
    CFCLocation = this.rootDir & "tests/model"
  };


  public void function onRequestStart() {
    ORMReload();

    request.appName = this.name;
    request.context = {
      debug = structKeyExists( url, "debug" ) ? url.debug : false
    };
  }

  private any function getDatasourceConfig() {
    if( structKeyExists( server, "lucee" ) || structKeyExists( server, "railo" )) {
      // Lucee
      return {
        class = "org.postgresql.Driver",
        connectionString = "jdbc:postgresql://localhost:5432/basecfc",
        username = "postgres"
      };
    }

    if( cgi.server_name contains '.home' ) {
      // Home
      return "basecfc";
    }

    return {
      database = "basecfc",
      host = "192.168.1.45",
      port = "5432",
      driver = "PostgreSQL",
      username = "postgres"
    };
  }
}