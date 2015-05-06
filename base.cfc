component cacheuse="transactional"
          defaultSort="sortorder"

          mappedSuperClass=true
          hide=true
{
  property name="id" fieldType="id" generator="uuid";
  property name="name" fieldType="column" type="string" length=128;

  property name="deleted" fieldType="column" ORMType="boolean" default=false;
  property name="sortorder" fieldType="column" ORMType="integer";

  property name="createContact" fieldType="many-to-one" FKColumn="createcontactid" cfc="contact";
  property name="createDate" fieldType="column" ORMType="timestamp";
  property name="createIP" fieldType="column"  length=15;

  property name="updateContact" fieldType="many-to-one" FKColumn="updatecontactid" cfc="contact";
  property name="updateDate" fieldType="column" ORMType="timestamp";
  property name="updateIP" fieldType="column" length=15;

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  public any      function init()
  {
    lock scope="application" timeout="5"
    {
      variables.util = application.util;
    }

    return this;
  }

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  public array    function getFieldsToDisplay( required type, struct formdata = {} )
  {
    var properties = getInheritedProperties();
    var property = javaCast( "null", 0 );
    var key = "";
    var result = [];

    switch( type )
    {
      case "inlineedit-line":
        var propertiesInInline = structFindKey( properties, "ininline", "all" );
        var tempProperties = {};

        for( property in propertiesInInline )
        {
          tempProperties[property.owner.name] = property.owner;
          if( not structKeyExists( tempProperties[property.owner.name], "orderininline" ))
          {
            tempProperties[property.owner.name].orderininline = 9001;
          }
        }

        var sortKey = structSort( tempProperties, 'numeric', 'asc', '.orderininline' );
        var currentField = "";

        for( key in sortKey )
        {
          currentField = tempProperties[key].name;

          if( structKeyExists( formdata, currentField ))
          {
            local.valueToDisplay = formdata[currentField];
          }

          if( not structKeyExists( local, "valueToDisplay" ))
          {
            try
            {
              local.fn = "get" & currentField;
              local.exec = this[local.fn];
              local.valueToDisplay = local.exec();
            }
            catch( any cfcatch ){}
          }

          if( structKeyExists( local, "valueToDisplay" ) and isObject( local.valueToDisplay ))
          {
            local.valueToDisplay = local.valueToDisplay.getName();
          }

          param name="local.valueToDisplay" default="";

          arrayAppend( result, local.valueToDisplay );
          structDelete( local, "valueToDisplay" );
        }
        break;
      case "api":

        break;
    }

    return result;
  }

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  public boolean  function hasProperty( required string propertyToCheck )
  {
    return structKeyExists( getInheritedProperties(), propertyToCheck );
  }

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  public struct   function getInheritedProperties( struct result = {} )
  {
    var obj = getMetaData( this );

    if( structKeyExists( obj, "extends" ) and
        not obj.extends.fullname eq 'WEB-INF.cftags.component' and
        not obj.extends.fullname eq 'railo.Component' and
        not obj.extends.fullname eq 'lucee.Component' )
    {
      result = createObject( obj.extends.fullname ).getInheritedProperties( result );
    }

    if( structKeyExists( obj, "properties" ))
    {
      for( local.propNr = 1; local.propNr lte arrayLen( obj.properties ); local.propNr++ )
      {
        local.property = obj.properties[local.propNr];

        for( local.field in local.property )
        {
          result[local.property.name][local.field] = local.property[local.field];

          if( structKeyExists( local.property, "cfc" ))
          {
            result[local.property.name]["entityName"] = createObject( local.property.cfc ).getEntityName();
          }
        }
      }
    }

    return result;
  }

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  public string   function getEntityName()
  {
    return ORMGetSessionFactory().getClassMetadata( getClassName()).getEntityName();
  }

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  public string   function getClassName()
  {
    return listLast( getMetaData( this ).fullname, "." );
  }

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  /**
   * Base Save Method
   * This persists objects extending this base cfc into a database using ORM
   * It goes through all passed fields and updates all linked objects recursively
   * @formData  Struct    The data structure containing the new data to be saved
   * @calledBy  Struct    Used to prevent inv. loops (don't keep adding the caller to the callee and vice versa)
   * @depth     Numeric   Used to prevent inv. loops (don't keep going infinitely)
   */
  public any      function save( struct formData = {}, struct calledBy = { entity = '', id = '' }, numeric depth = 0 )
  {
    var key = 0;
    var property = 0;
    var propertyEntityName = 0;
    var savedState = {};
    var meta = getMetaData( this );
    var entityName = this.getEntityName();
    var CFCName = meta.name;
    var properties = getInheritedProperties();
    var canBeLogged = request.context.config.log;
    var uuid = createUUID();

    param name="request.ormActions" default="#{}#";
    param name="formData.deleted" default=false;

    if( request.context.debug )
    {
      // DEBUG:
      writeOutput( '<p>#depth# - #entityName#</p>' );
    }

    // Hard coded depth limit
    if( depth gt 6 )
    {
      return;
    }

    if( canBeLogged )
    {
      if( not len( trim( getCreateDate())))
      {
        setCreateDate( now());
      }

      if( not len( trim( getCreateIP())))
      {
        setCreateIP( cgi.remote_host );
      }

      setUpdateDate( now());
      setUpdateIP( cgi.remote_host );

      if( not request.context.config.disableSecurity )
      {
        if( not hasCreateContact())
        {
          setCreateContact( session.auth.user );
        }

        setUpdateContact( session.auth.user );
      }
    }

    // typeahead
    for( key in properties )
    {
      property = properties[key];

      if( structKeyExists( property, "cfc" ))
      {
        propertyEntityName = createObject( property.cfc ).getEntityName();
      }

      if( structKeyExists( formData, "#property.name#_tagsinput" ))
      {
        local.tagsField = formData["#property.name#_tagsinput"];
        if( len( trim( local.tagsField )))
        {
          formData["set_#property.name#"] = "";

          for( local.tag in local.tagsField )
          {
            local.tagToLink = entityLoad( propertyEntityName, { name = lCase( local.tag )});

            if( arrayLen( local.tagToLink ) eq 1 )
            {
              formData["set_#property.name#"] = listAppend( formData["set_#property.name#"], '{"id":"#local.tagToLink[1].getID()#"}' );
            }
            else
            {
              formData["set_#property.name#"] = listAppend( formData["set_#property.name#"], '{"name":"#local.tag#"}' );
            }
          }
        }
      }
    }

    if( request.context.debug )
    {
      var js = "document.getElementById('#uuid#').style.display=(document.getElementById('#uuid#').style.display==''?'none':'');";
      var display = depth gt 0 ? ' style="display:none;"' : '';

      // DEBUG:
      writeOutput( '
        <table cellpadding="5" cellspacing="0" border="1" width="100%">
          <tr>
            <th colspan="2" bgcolor="teal" style="cursor:pointer;" onclick="#js#"><font color="white">#entityName# #getID()#</font></th>
          </tr>
          <tr>
            <td colspan="2">
              <table cellpadding="5" cellspacing="0" border="1" width="100%" id="#uuid#"#display#>
                <tr>
                  <td colspan="2">#getName()#</td>
                </tr>
      ' );
    }

    // SAVE VALUES PASSED VIA FORM
    for( key in properties )
    {
      property = properties[key];

      param name="property.fieldtype" default="string";

      if( listFindNoCase( "log,createDate,createIP,createContact,updateDate,updateIP,updateContact,id", key ))
      {
        if( request.context.debug )
        {
          // DEBUG:
          writeOutput( 'Skipped #key#, default field.<br />' );
        }

        continue;
      }

      if( structKeyExists( property, "cfc" ))
      {
        propertyEntityName = createObject( property.cfc ).getEntityName();
      }

      savecontent variable="local.debugoutput"
      {
        switch( property.fieldtype )
        {
          case "one-to-many":
          case "many-to-many":
            //  ______   ______        __    __     ______     __   __     __  __
            // /\__  _\ /\  __ \      /\ "-./  \   /\  __ \   /\ "-.\ \   /\ \_\ \
            // \/_/\ \/ \ \ \/\ \     \ \ \-./\ \  \ \  __ \  \ \ \-.  \  \ \____ \
            //    \ \_\  \ \_____\     \ \_\ \ \_\  \ \_\ \_\  \ \_\\"\_\  \/\_____\
            //     \/_/   \/_____/      \/_/  \/_/   \/_/\/_/   \/_/ \/_/   \/_____/

            // OVERRIDE to
            if( structKeyExists( formdata, property.name ))
            {
              // Valid input:
              local.inputType = "invalid";

              // a JSON var
              if( isJSON( formdata[property.name] ))
              {
                local.inputType = "json";
              }
              else
              {
                // list of JSON structs
                if( isArray( formdata[property.name] ))
                {
                  formdata[property.name] = arrayToList( formdata[property.name] );
                }

                if( isJSON( "[#formdata[property.name]#]" ))
                {
                  local.inputType = "multiple-json";
                }
                else
                {
                  // list of UUIDs
                  local.inputType = "uuid";
                }
              }

              formdata["set_#property.name#"] = "";

              for( local.dataToSave in formdata[property.name] )
              {
                if( local.inputType eq "uuid" )
                {
                  local.dataToSave = '{"id":"#local.dataToSave#"}';
                }

                formdata["set_#property.name#"] = listAppend( formdata["set_#property.name#"], local.dataToSave );
              }

              local.workData = formdata[property.name];
              structDelete( formdata, property.name );
            }
            else if( request.context.debug )
            {
              // DEBUG
              writeOutput( '<br />Skipping #property.name#' );
            }

            // REMOVE
            if( structKeyExists( formdata, "set_#property.name#" ) or structKeyExists( formdata, "remove_#property.name#" ))
            {
              local.query = "SELECT b FROM #entityName# a JOIN a.#property.name# b WHERE a.id = :id ";
              local.params = { "id" = getID() };

              if( structKeyExists( formdata, "remove_#property.name#" ))
              {
                local.query &= " AND b.id IN ( :list )";
                local.params['list'] = listToArray( formdata['remove_#property.name#'] );
              }

              local.objectsToOverride = ORMExecuteQuery( local.query, local.params, { "cacheable" = true });

              for( local.objectToOverride in local.objectsToOverride )
              {
                if( property.fieldType eq "many-to-many" )
                {
                  local.reverseField = local.objectToOverride.getReverseField( CFCName, property.inverseJoinColumn, property.fieldtype, 'singular' );

                  local.fn = "remove" & local.reverseField;
                  local.exec = local.objectToOverride[local.fn];
                  local.exec( this );

                  if( request.context.debug )
                  {
                    // DEBUG
                    writeOutput( '<p>local.objectToOverride.remove#local.reverseField#(this)</p>' );
                  }
                }
                else
                {
                  local.reverseField = local.objectToOverride.getReverseField( CFCName, property.fkcolumn, property.fieldtype, 'plural' );

                  local.fn = "set" & local.reverseField;
                  local.exec = local.objectToOverride[local.fn];
                  local.exec( javaCast( "null", 0 ));

                  if( request.context.debug )
                  {
                    // DEBUG
                    writeOutput( '<p>local.objectToOverride.set#local.reverseField#(javaCast(''null'',0))</p>' );
                  }
                }

                local.fn = "remove" & property.singularName;
                local.exec = this[local.fn];
                local.exec( local.objectToOverride );

                if( request.context.debug )
                {
                  // DEBUG
                  writeOutput( '<p>remove#property.singularName#(local.objectToOverride)</p>' );
                }
              }
            }

            // SET
            if( structKeyExists( formdata, "set_#property.name#" ))
            {
              local.workData = deSerializeJSON( '[' & formdata["set_#property.name#"] & ']' );

              if( arrayLen( local.workData ))
              {
                formdata["add_#property.singularName#"] = "";
              }

              for( local.toAdd in local.workData )
              {
                if( not isJSON( local.toAdd ))
                {
                  local.toAdd = serializeJSON( local.toAdd );
                }

                formdata["add_#property.singularName#"] = listAppend( formdata["add_#property.singularName#"], local.toAdd );
              }

              structDelete( formdata, "set_#property.name#" );
            }

            // ADD
            if( structKeyExists( formdata, "add_#property.singularName#" ))
            {
              local.workData = deSerializeJSON( '[' & formdata["add_#property.singularName#"] & ']' );

              for( local.updatedStruct in local.workData )
              {
                if( isJSON( local.updatedStruct ))
                {
                  local.updatedStruct = deSerializeJSON( local.updatedStruct );
                }

                if( isStruct( local.updatedStruct ) and structKeyExists( local.updatedStruct, "id" ))
                {
                  local.objectToLink = entityLoadByPK( propertyEntityName, local.updatedStruct.id );
                  structDelete( local.updatedStruct, "id" );
                }

                if( isNull( local.objectToLink ))
                {
                  local.objectToLink = entityNew( propertyEntityName );
                  entitySave( local.objectToLink );
                }

                local.fn = "has" & property.singularName;
                local.exec = this[local.fn];
                local.alreadyHasValue = local.exec( local.objectToLink );

                if( request.context.debug )
                {
                  // DEBUG
                  writeOutput( '<p>this.has#property.singularName#( #local.objectToLink.getName()# #local.objectToLink.getID()# ) -> #local.alreadyHasValue#</p>' );
                }

                local.ormAction = "#getID()#_#local.objectToLink.getID()#";

                if( not local.alreadyHasValue and not structKeyExists( request.ormActions, local.ormAction ))
                {
                  local.fn = "add" & property.singularName;
                  local.exec = this[local.fn];
                  local.exec( local.objectToLink );

                  if( request.context.debug )
                  {
                    // DEBUG
                    writeOutput( '<p>add#property.singularName#(local.objectToLink)</p>' );
                    writeOutput( local.ormAction );
                  }

                  local.reverseField = local.objectToLink.getReverseField( CFCName, property.fkcolumn, property.fieldtype, 'singular' );

                  if( property.fieldtype eq "many-to-many" )
                  {
                    local.updatedStruct['add_#local.reverseField#'] = '{"id":"#getID()#"}';
                    request.ormActions[local.ormAction] = property.name;
                  }
                  else
                  {
                    local.updatedStruct[local.reverseField] = getID();
                    request.ormActions[local.ormAction] = property.name;
                  }
                }

                // Go down the rabbit hole:
                if( structCount( local.updatedStruct ))
                {
                  if( request.context.debug )
                  {
                    // DEBUG
                    writeOutput( '<b>ADD .save()</b>' );
                  }

                  local.objectToLink = local.objectToLink.save(
                    formData = local.updatedStruct,
                    depth= depth + 1,
                    calledBy = { entity = entityName, id = getID()}
                  );
                }

                // CLEANUP
                structDelete( local, "objectToLink" );
              }
            }

            // CLEANUP
            if( structKeyExists( local, "workData" ))
            {
              structDelete( local, "workData" );
            }

            break;
          default:

            //  ______   ______        ______     __   __     ______
            // /\__  _\ /\  __ \      /\  __ \   /\ "-.\ \   /\  ___\
            // \/_/\ \/ \ \ \/\ \     \ \ \/\ \  \ \ \-.  \  \ \  __\
            //    \ \_\  \ \_____\     \ \_____\  \ \_\\"\_\  \ \_____\
            //     \/_/   \/_____/      \/_____/   \/_/ \/_/   \/_____/

            // inline forms
            if(
                structKeyExists( property, "inlineedit" ) and
                (
                  structKeyExists( formdata, property.name ) or
                  structKeyList( formdata ) contains '#property.name#_' or
                  structKeyExists( formdata, "#property.name#id" )
                )
              )
            {
              if( propertyEntityName eq calledBy.entity )
              {
                // this prevents invinite loops
                local.inlineEntity = entityLoadByPK( "#calledBy.entity#", calledBy.id );
              }
              else
              {
                local.fn = "get" & property.name;
                local.exec = this[local.fn];
                local.inlineEntity = local.exec();

                if( request.context.debug )
                {
                  // DEBUG
                  writeOutput( '<p>get#property.name#()</p>' );
                }

                if( isNull( local.inlineEntity ))
                {
                  if( structKeyExists( formData, "#property.name#id" ))
                  {
                    local.inlineEntity = entityLoadByPK( propertyEntityName, formData["#property.name#id"] );
                  }

                  if( isNull( local.inlineEntity ))
                  {
                    local.inlineEntity = entityNew( propertyEntityName );
                    entitySave( local.inlineEntity );
                  }
                }

                local.inlineEntityParameters = {};

                for( local.formField in formData )
                {
                  if( listLen( local.formField, '_' ) gte 2 and listFirst( local.formField, "_" ) eq property.name )
                  {
                    local.inlineEntityParameters[listRest( local.formField, "_" )] = formData[local.formField];
                  }
                }

                if(
                    structKeyExists( formdata, property.name ) and
                    isJSON( formdata[property.name] ) and
                    not structCount( local.inlineEntityParameters )
                  )
                {
                  local.inlineEntityParameters = deSerializeJSON( formdata[property.name] );
                }
              }

              formdata[property.name] = local.inlineEntity.getID();
            }

            // save value and link objects together
            if( structKeyExists( formdata, property.name ))
            {
              local.value = formdata[property.name];
              local.valueToLog = left( local.value, 255 );

              if( structKeyExists( property, "cfc" ))
              {
                // LINK TO OTHER OBJECT (USING PROVIDED ID)
                if( structKeyExists( local, "inlineEntity" ))
                {
                  local.obj = local.inlineEntity;
                  structDelete( local, "inlineEntity" );
                }
                else if( len( trim( local.value )))
                {
                  local.obj = entityLoadByPK( propertyEntityName, local.value );
                }

                if( not isNull( local.obj ))
                {
                  if( not structKeyExists( local, "inlineEntityParameters" ))
                  {
                    local.inlineEntityParameters = {};
                  }

                  local.inlineEntityParameters["#propertyEntityName#id"] = local.obj.getID();
                  local.reverseField = local.obj.getReverseField( CFCName, property.fkcolumn, property.fieldtype, 'singular' );

                  local.fn = "has" & local.reverseField;
                  local.exec = local.obj[local.fn];
                  local.alreadyHasValue = local.exec( this );

                  if( request.context.debug )
                  {
                    // DEBUG
                    writeOutput( '<p>local.obj.has#local.reverseField#( #getID()# ) -> #local.alreadyHasValue#</p>' );
                  }

                  local.ormAction = "#getID()#_#local.obj.getID()#";

                  if( not local.alreadyHasValue and not structKeyExists( request.ormActions, local.ormAction ))
                  {
                    if( request.context.debug )
                    {
                      // DEBUG
                      writeOutput( local.ormAction );
                    }

                    local.inlineEntityParameters['add_#local.reverseField#'] = '{"id":"#getID()#"}';
                    request.ormActions[local.ormAction] = property.name;
                  }

                  if( structCount( local.inlineEntityParameters ))
                  {
                    if( request.context.debug )
                    {
                      // DEBUG
                      writeOutput( '<b>.save()</b>' );
                    }

                    try
                    {
                      local.obj.save(
                        depth = ( depth + 1 ),
                        calledBy = {
                          entity = entityName,
                          id = getID()
                        },
                        formData = local.inlineEntityParameters
                      );
                    }
                    catch( any cfcatch )
                    {
                      if( request.context.debug )
                      {
                        writeDump( local.inlineEntityParameters );
                        writeDump( cfcatch );
                        abort;
                      }
                      else
                      {
                        throw( cfcatch.message );
                      }
                    }
                  }

                  local.valueToLog = local.obj.getName();
                  local.value = local.obj;

                  structDelete( local, "obj" );
                  structDelete( local, "inlineEntityParameters" );
                }
                else
                {
                  local.valueToLog = "removed";
                  structDelete( local, "value" );
                }
              }
              else
              {
                // SIMPLE VALUE
                // make sure integers are saved as that:
                if( structKeyExists( property, "ORMType" ))
                {
                  if( property.ORMType eq "int" or property.ORMType eq "integer" )
                  {
                    local.value = int( val( local.value ));
                  }

                  if( property.ORMType eq "float" )
                  {
                    local.value = val( local.value );
                  }
                }
              }

              local.fn = "set" & property.name;
              local.exec = this[local.fn];

              if( not isNull( local.value ))
              {
                local.exec( local.value );

                if( request.context.debug )
                {
                  // DEBUG
                  writeOutput( '<p>set#property.name#( local.value )</p>' );
                }
              }
              else
              {
                local.exec( javaCast( 'null', 0 ));

                if( request.context.debug )
                {
                  // DEBUG
                  writeOutput( '<p>set#property.name#( NULL )</p>' );
                }
              }
            }
        }
      }

      if( len( trim( local.debugoutput )) and request.context.debug )
      {
        // DEBUG
        writeOutput( '
          <tr>
            <th width="15%" valign="top" align="right">#key#</th>
            <td width="85%">#local.debugoutput#</td>
          </tr>
        ' );
      }

      if( structKeyExists( local, "valueToLog" ))
      {
        savedState[property.name] = local.valueToLog;
        structDelete( local, "valueToLog" );
      }
    }

    if( request.context.debug )
    {
      // DEBUG
      writeOutput( '
            </td>
          </tr>
        </table>
      </table>
      ' );
    }

    if(
        depth eq 0 and
        canBeLogged and
        entityName neq "logentry"
      )
    {
      var tempLogentry = { "entity" = this, "deleted" = false };

      if( structKeyExists( form, "logentry_note" ))
      {
        tempLogentry["note"] = form.logentry_note;
      }

      if( structKeyExists( form, "logentry_attachment" ))
      {
        tempLogentry["attachment"] = form.logentry_attachment;
      }

      local.logentry = entityNew( "logentry", tempLogentry );

      entitySave( local.logentry );

      local.logaction = entityLoad( "logaction", { name = "changed" }, true );
      local.logentry.enterIntoLog( local.logaction, savedState );

      request.context.log = local.logentry;
    }

    return this;
  }

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  private any     function getReverseField( required string cfc, required string fkColumn, required string type, required string singular_or_plural="singular" )
  {
    var properties = structFindKey( getInheritedProperties(), "cfc", "all" );
    var field = 0;
    var fieldFound = false;

    if( not arrayLen( properties ))
    {
      // ERROR: not linked to any CFCs
      writeDump( arguments );
      abort;
    }

    for( property in properties )
    {
      field = property.owner;
      if(
          not (
            (
              structKeyExists( field, "fkcolumn" ) and
              field.fkColumn eq fkColumn
            ) or
            field.cfc eq cfc
          )
        )
      {
        continue;
      }

      if( field.cfc eq cfc )
      {
        fieldFound = true;
        break;
      }

      if( isInstanceOf( createObject( cfc ), field.cfc ))
      {
        fieldFound = true;
        break;
      }
    }

    var propertyWithFK = structFindValue({ 'search' = properties }, fkColumn, 'all' );

    if( arrayLen( propertyWithFK ) eq 1 )
    {
      field = propertyWithFK[1].owner;
      fieldFound = true;
    }

    if( not fieldFound )
    {
      // ERROR: no valid properties found in #listLast( local.meta.name, '.' )#
      writeDump( arguments );
      writeDump( getMetaData( this ));
      writeDump( properties );
      abort;
    }

    result = field.name;

    if( singular_or_plural eq "singular" and structKeyExists( field, 'singularName' ))
    {
      result = field['singularName'];
    }

    return result;
  }
}