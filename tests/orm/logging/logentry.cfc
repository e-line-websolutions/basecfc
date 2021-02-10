component extends=basecfc.base persistent=true {
  property name;
  property type="boolean" name="deleted" default="false";
  property type="numeric" name="sortorder" default=0 ormtype="integer";

  property name="relatedentity" fieldtype="many-to-one" cfc="basecfc.tests.orm.logging.logged" fkcolumn="entityid";
  property name="logaction" fieldtype="many-to-one" cfc="basecfc.tests.orm.logging.logaction" fkcolumn="logactionid";
  property name="savedstate" type="string";
  property name="by" fieldtype="many-to-one" cfc="basecfc.tests.orm.logging.contact" fkcolumn="contactid";
  property name="dd" ormtype="timestamp";
  property name="ip" length=15;

  public string function getSavedState() {
    return variables.savedstate ?: '{}';
  }

  public any function enterIntoLog( string action = 'init', struct newstate = {}, component entitytolog ) {
    if ( isNull( entitytolog ) && !isNull( variables.relatedentity ) ) {
      entitytolog = variables.relatedentity;
    }

    if ( isNull( entitytolog ) ) {
      writeOutput( 'entitytolog is null' );abort;
      return this;
    }

    var formdata = {
      'dd' = now(),
      'ip' = cgi.remote_addr,
      'relatedentity' = entitytolog.getid()
    };

    if ( !isNull( request.context.auth.userid ) ) {
      var contact = entityLoadByPK( 'contact', request.context.auth.userid );

      if ( !isNull( contact ) ) {
        formdata[ 'by' ] = contact;
      }
    }

    if ( len( trim( action ) ) ) {
      var logaction = entityLoad( 'logaction', { name = action }, true );

      if ( isNull( logaction ) ) {
        var logaction = entityLoad( 'logaction', { name = 'init' }, true );
      }

      if ( !isNull( logaction ) ) {
        formdata[ 'logaction' ] = logaction;
      }
    }

    if ( newstate.isEmpty() ) {
      newstate = { 'init' = true, 'name' = entitytolog.getname() };
    }

    newstate.delete( 'savedstate' );

    formdata[ 'savedstate' ] = serializeJSON( newstate );

    transaction {
      var result = save( formdata );
    }

    return result;
  }
}