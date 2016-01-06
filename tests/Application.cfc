component{
  this.name = request.appName = "basecfctests";
  this.mappings = {
    "/root" = getDirectoryFromPath( getCurrentTemplatePath()),
    "/tests" = getDirectoryFromPath(getCurrentTemplatePath()),
    "/testbox" = getDirectoryFromPath(getCurrentTemplatePath()) & "../../testbox"
  };

  this.datasource = "basecfc";
  this.ormEnabled = true;

  this.ORMSettings.saveMapping = false;
  this.ORMSettings.cfcLocation = "/model";
  this.ORMSettings.dbCreate = "dropcreate";
  this.ORMSettings.flushAtRequestEnd = false;
  this.ORMSettings.autoManageSession = false;

  param boolean url.debug=false;

  request.context.debug = url.debug;

  public void function onRequestStart() {
  }
}