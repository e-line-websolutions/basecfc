component {
  this.name = "basecfctests";

  this.rootDir = getDirectoryFromPath( getCurrentTemplatePath( ) );

  this.mappings = {
    "/" = this.rootDir,
    "/basecfc" = this.rootDir,
    "/root" = this.rootDir,
    "/testbox" = expandPath( "../../testbox" ),
    "/hyrule" = expandPath( "../../hyrule" )
  };

  this.ORMEnabled = true;
  this.ORMSettings = {
    datasource = "basecfc",
    DBCreate = "dropcreate",
    CFCLocation = this.rootDir & "model/beans"
  };

  public void function onRequestStart( ) {
    ORMReload( );

    request.appName = this.name;
    request.context = { debug = structKeyExists( url, "debug" ) ? url.debug : false };
  }
}