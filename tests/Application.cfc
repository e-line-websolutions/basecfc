component {
  this.name = "basecfctests";

  this.root = replace( getDirectoryFromPath( getCurrentTemplatePath( ) ), "\", "/", "all" );
  this.basecfcRoot = listDeleteAt( this.root, listLen( this.root, "/" ), "/" );

  this.mappings = {
    "/root" = this.root,
    "/basecfc" = this.basecfcRoot,
    "/testbox" = expandPath( "../../testbox" ),
    "/hyrule" = expandPath( "../../hyrule" )
  };

  this.ORMEnabled = true;
  this.ORMSettings = {
    "datasource" = "basecfc",
    "dbCreate" = "dropcreate",
    "sqlScript" = "nuke.sql",
    "cfcLocation" = expandPath( "./model/beans" )
  };

  public void function onRequestStart( ) {
    ORMReload( );

    request.appName = this.name;
    request.context = {
      "debug" = ( structKeyExists( url, "debug" ) ? url.debug : false ),
      "config" = {
        "logLevel" = "debug"
      }
    };
  }
}