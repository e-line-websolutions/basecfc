component{
  this.name = request.appName = "basecfctests";
  this.mappings = {
    "/root" = getDirectoryFromPath( getCurrentTemplatePath()),
    "/tests" = getDirectoryFromPath(getCurrentTemplatePath()),
    "/testbox" = getDirectoryFromPath(getCurrentTemplatePath()) & "../../testbox"
  };

  this.datasources["basecfc"] = {
    class = "org.postgresql.Driver",
    connectionString = "jdbc:postgresql://localhost:5432/basecfc",
    username = "postgres"
  };

  this.ORMEnabled = true;

  this.ORMSettings = {
    datasource = "basecfc",
    saveMapping = false,
    cfcLocation = "/model",
    dbCreate = "dropcreate"
    // flushAtRequestEnd = false,
    // autoManageSession = false
  };

  param boolean url.debug=false;

  request.context.debug = url.debug;

  public void function onRequestStart() {
    ORMReload();
  }
}