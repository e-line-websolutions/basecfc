component extends="basecfc.base" persistent=true {
  property name;
  property type="boolean" name="deleted" default="false";
  property type="numeric" name="sortorder" default=0 ormType="integer";

  property name="relatedEntity" fieldType="many-to-one" cfc="root.model.beans.logging.logged" FKColumn="entityid";
  property name="logaction" fieldType="many-to-one" cfc="root.model.beans.logging.logaction" FKColumn="logactionid";
  property name="savedState" length=4000;
  property name="by" fieldType="many-to-one" cfc="root.model.beans.logging.contact" FKColumn="contactid";
  property name="dd" ORMType="timestamp";
  property name="ip" length=15;

  public any function enterIntoLog( string action = "init", struct newState = { }, component entityToLog ) {
    if ( isNull( entityToLog ) && !isNull( variables.relatedEntity ) ) {
      entityToLog = variables.relatedEntity;
    }

    if ( isNull( entityToLog ) ) {
      return this;
    }

    writeLog( text = "Logging entry for #entityToLog.getId( )#", file = request.appName );

    var formData = {
      "dd" = now( ),
      "ip" = cgi.remote_addr,
      "relatedEntity" = entityToLog.getId( )
    };

    if ( isDefined( "request.context.auth.userID" ) ) {
      var contact = entityLoadByPK( "contact", request.context.auth.userID );

      if ( !isNull( contact ) ) {
        formData[ "by" ] = contact;
      }
    }

    if ( len( trim( action ) ) ) {
      var logaction = entityLoad( "logaction", { name = action }, true );

      if ( isNull( logaction ) ) {
        var logaction = entityLoad( "logaction", { name = "init" }, true );
      }

      if ( !isNull( logaction ) ) {
        formData[ "logaction" ] = logaction;
      }
    }

    if ( structIsEmpty( newState ) ) {
      newState = { "init" = true, "name" = entityToLog.getName( ) };
    }

    formData[ "savedState" ] = left( serializeJson( deORM( newState ) ), 4000 );

    transaction {
      var result = save( formData );
    }

    var e = result.getRelatedEntity( );

    if ( !isNull( e ) ) {
      writeLog( text = "Entry logged for #e.getId( )#", file = request.appName );
    }

    return result;
  }
}