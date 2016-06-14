component {
  this.name = "basecfctests";

  this.rootDir = getDirectoryFromPath( getCurrentTemplatePath());

  this.mappings = {
    "/" = this.rootDir,
    "/basecfc" = this.rootDir,
    "/root" = this.rootDir & "tests",
    "/testbox" = this.rootDir & "../testbox"
  };

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
}