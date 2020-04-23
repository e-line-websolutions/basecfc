component extends=basecfc.base persistent=true {
  property name;
  property type="boolean" name="deleted" default="false";
  property type="numeric" name="sortorder" default=0 ormtype="integer";

  property name="relatedentity" fieldtype="many-to-one" cfc="basecfc.tests.orm.logging.logged" fkcolumn="entityid";
  property name="logaction" fieldtype="many-to-one" cfc="basecfc.tests.orm.logging.logaction" fkcolumn="logactionid";
  property name="savedstate" length=4000;
  property name="by" fieldtype="many-to-one" cfc="basecfc.tests.orm.logging.contact" fkcolumn="contactid";
  property name="dd" ormtype="timestamp";
  property name="ip" length=15;

  public any function enterintolog( string action = "init", struct newstate = { }, component entitytolog ) {
    if ( isnull( entitytolog ) && !isnull( variables.relatedentity ) ) {
      entitytolog = variables.relatedentity;
    }

    if ( isnull( entitytolog ) ) {
      return this;
    }

    writelog( text = "logging entry for #entitytolog.getid( )#", file = request.appname );

    var formdata = {
      "dd" = now( ),
      "ip" = cgi.remote_addr,
      "relatedentity" = entitytolog.getid( )
    };

    if ( isdefined( "request.context.auth.userid" ) ) {
      var contact = entityloadbypk( "contact", request.context.auth.userid );

      if ( !isnull( contact ) ) {
        formdata[ "by" ] = contact;
      }
    }

    if ( len( trim( action ) ) ) {
      var logaction = entityload( "logaction", { name = action }, true );

      if ( isnull( logaction ) ) {
        var logaction = entityload( "logaction", { name = "init" }, true );
      }

      if ( !isnull( logaction ) ) {
        formdata[ "logaction" ] = logaction;
      }
    }

    if ( structisempty( newstate ) ) {
      newstate = { "init" = true, "name" = entitytolog.getname( ) };
    }

    formdata[ "savedstate" ] = left( serializejson( deorm( newstate ) ), 4000 );

    transaction {
      var result = save( formdata );
    }

    var e = result.getrelatedentity( );

    if ( !isnull( e ) ) {
      writelog( text = "entry logged for #e.getid( )#", file = request.appname );
    }

    return result;
  }
}