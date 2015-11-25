component{
  this.name = request.appName = "basecfctests";
  this.mappings = {
    "/root" = getDirectoryFromPath( getCurrentTemplatePath()),
    "/testbox" = "G:\Dropbox\Projects\thirdparty\testbox"
  };

  this.datasource = "basecfc";
  this.ormEnabled = true;

  this.ORMSettings.saveMapping = false;
  this.ORMSettings.cfcLocation = "/model";
  this.ORMSettings.dbCreate = "dropcreate";
  // this.ORMSettings.flushAtRequestEnd = false;
  // this.ORMSettings.autoManageSession = false;

  request.context.debug = false;

  public void function onRequestStart() {
    ORMReload();
  }
}