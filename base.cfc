/*
  ORM Base class used in Mustang

  The MIT License (MIT)

  Copyright (c) 2015 Mingo Hagen

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
*/

component mappedSuperClass=true cacheuse="transactional" defaultSort="sortorder" hide=true {
  property name="id" fieldType="id" generator="uuid";
  property name="name" fieldType="column" type="string" length=128;
  property name="deleted" fieldType="column" ORMType="boolean" default=false;
  property name="sortorder" fieldType="column" ORMType="integer";

  param request.appName=hash( getBaseTemplatePath());

  public any function init() hint="Initializes the object" {
    variables.instance = {
      ormActions = {},
      debug = false,
      config = {
        log = false,
        disableSecurity = true
      }
    };

    variables.instance.meta = getMetaData();
    variables.instance.inheritedProperties = getInheritedProperties();

    if( structKeyExists( request, "context" ) && isStruct( request.context )) {
      structAppend( variables.instance, request.context, true );
    }

    return this;
  }

  // By Adam Tuttle (http://fusiongrokker.com/post/deorm).
  public string function toString( any obj = this ) hint="Returns a JSON representation of the object" {
    var deWormed = {};

    if( isSimpleValue( obj )){
      deWormed = obj;

    } else if( isObject( obj )){
      var md = getMetadata( obj );

      do {
        if( md.keyExists( 'properties' )){
          for( var prop in md.properties){
            if( structKeyExists( obj, 'get' & prop.name )){
              if( !prop.keyExists( 'fieldtype' ) || prop.fieldtype == "id" || ( prop.keyExists( 'fieldtype' ) && !( listFindNoCase( "one-to-many,many-to-one,one-to-one,many-to-many", prop.fieldtype )))){
                deWormed[ prop.name ] = evaluate( "obj.get#prop.name#()" );
              }
            }
          }
        }

        if( md.keyExists( 'extends' )){
          md = md.extends;
        }
      } while( md.keyExists( 'extends' ));

    } else if( isStruct( obj )){
      for( var key in obj ){
        deWormed[ key ] = toString( obj[key] );
      }

    } else if( isArray( obj )){
      var deWormed = [];
      for( var el in obj ){
        deWormed.append( toString( el ) );
      }

    } else {
      deWormed = getMetadata( obj );
    }

    return serializeJSON( deWormed );

    // var jsonified = deserializeJSON( serializeJSON( this ));
    // structDelete( jsonified, "password" );
    // return serializeJSON( jsonified );
  }

  public boolean function hasProperty( required string propertyToCheck ) {
    return structKeyExists( variables.instance.inheritedProperties, propertyToCheck );
  }

  public struct function getInheritedProperties() {
    var meta = variables.instance.meta;
    var result = {};
    var extends = true;

    while( extends ){
      if(!(
        structKeyExists( meta, "extends" ) &&
        !meta.extends.fullname == 'WEB-INF.cftags.component' &&
        !meta.extends.fullname == 'railo.Component' &&
        !meta.extends.fullname == 'lucee.Component'
      )){
        extends = false;
      }

      if( structKeyExists( meta, "properties" )){
        for( var i=1; i <= arrayLen( meta.properties ); i++ ){
          var property = meta.properties[i];

          for( var field in property ){
            result[property.name][field] = property[field];

            if( structKeyExists( property, "cfc" )){
              result[property.name]["entityName"] = getEntityName( property.cfc );
            }
          }
        }
      }

      meta = meta.extends;
    }

    return result;
  }

  public string function getEntityName( string className = getClassName()) {
    var sessionFactory = ORMGetSessionFactory();
    var metaData = sessionFactory.getClassMetadata( listLast( className, '.' ));

    return metaData.getEntityName();
  }

  public string function getClassName() {
    return variables.instance.meta.fullname;
  }

  public string function getReverseField( required string cfc,
                                          required string fkColumn,
                                          boolean singular=true ){
    var propertiesWithCFC = structFindKey( variables.instance.inheritedProperties, "cfc", "all" );
    var field = 0;
    var fieldFound = 0;

    if( !arrayLen( propertiesWithCFC )){
      var logMessage = "getReverseField() ERROR: nothing linked to #cfc#.";
      writeLog( text = logMessage, type = "fatal", file = request.appName );
      throw( type = "basecfc.getReverseField", message = logMessage );
    }

    for( var property in propertiesWithCFC ){
      field = property.owner;

      if( structKeyExists( field, "fkcolumn" ) && field.fkColumn != fkColumn ) {
        continue;
      }

      if(!(( structKeyExists( field, "fkcolumn" ) && field.fkColumn == fkColumn ) || field.cfc == cfc )) {
        continue;
      }

      if( field.cfc == cfc && field.fkColumn == fkColumn ){
        fieldFound = 1;
        break;
      }

      var testObj = createObject( cfc ).init();

      if( isInstanceOf( testObj, field.cfc )){
        fieldFound = 2;
        break;
      }

      if( testObj.getClassName() == field.cfc ){
        fieldFound = 3;
        break;
      }
    }

    var propertyWithFK = structFindValue({ a = propertiesWithCFC }, fkColumn, 'all' );

    if( arrayLen( propertyWithFK ) == 1 ){
      field = propertyWithFK[1].owner;
      fieldFound = 4;
    }

    if( fieldFound == 0 ){
      var logMessage = "getReverseField() ERROR: no reverse field found for fk #fkColumn# in cfc #cfc#.";
      writeLog( text = logMessage, type = "fatal", file = request.appName );
      throw( type = "basecfc.getReverseField", message = logMessage );
    }

    var result = field.name;

    if( singular && structKeyExists( field, 'singularName' )){
      result = field['singularName'];
    }

    return result;
  }

  /**
   * Base Save Method
   * This persists objects extending this base cfc into a database using ORM
   * It goes through all passed fields and updates all linked objects recursively
   * @formData  Struct    The data structure containing the new data to be saved
   * @calledBy  Struct    Used to prevent inv. loops (don't keep adding the caller to the callee and vice versa)
   * @depth     Numeric   Used to prevent inv. loops (don't keep going infinitely)
   */
  public any function save( struct formData = {},
                            struct calledBy = { entity = '', id = '' },
                            numeric depth = 0 ) {
    var timer = getTickCount();
    var savedState = {};

    if( not structKeyExists( variables, "instance" )) {
      var logMessage = "Basecfc not initialised";
      writeLog( text = logMessage, type = "fatal", file = request.appName );
      throw( type = "basecfc.global", message = logMessage );
    }

    var meta = variables.instance.meta;
    var entityName = getEntityName();
    var properties = variables.instance.inheritedProperties;
    var canBeLogged = ( variables.instance.config.log && isInstanceOf( this, "root.model.logged" ));
    var uuid = createUUID();
    var defaultFields = "log,id,fieldnames,submitbutton,#entityName#id";
    var logFields = "createContact,createDate,createIP,updateContact,updateDate,updateIP";

    if( isNull( getDeleted())) {
      formData.deleted=false;
    }

    if( !structKeyExists( request, "basecfc-save" )) {
      request["basecfc-save"] = true;
      if( variables.instance.debug ){
        writeOutput( '
          <script src="https://cdn.rawgit.com/google/code-prettify/master/loader/run_prettify.js"></script>
          <style>
            td,th{ padding:5px; border:1px solid gray;border-top:0;border-left:0; }
            .basecfc-debug{width:900px;margin:0 auto;}
            .basecfc-debug .call{font-family:sans-serif;font-size:12px;border:2px solid black;}
            .basecfc-debug h2{background:teal;cursor:pointer;color:white;padding:5px;margin:0}
            .basecfc-debug table{border-color:silver;font-size:12px;}
            .result{color:red;}
          </style>
        ' );
      }
    }

    if( variables.instance.debug ) {
      if( depth == 0 ){
        writeLog( text="~~~ start basecfc.save() ~~~", file=request.appName );
        writeOutput( '<div class="basecfc-debug">' );
      }
      writeOutput( '<p>#depth# - #entityName#</p>' );
    }

    // Hard coded depth limit
    if( depth > 10 ) {
      return;
    }

    if( canBeLogged && !( depth > 0 && isInstanceOf( this, "root.model.contact" ))) {
      if( !len( trim( getCreateDate()))){
        formData.createDate = now();
      }

      if( !len( trim( getCreateIP()))){
        formData.createIP = cgi.remote_host;
      }

      formData.updateDate = now();
      formData.updateIP = cgi.remote_host;

      if( !variables.instance.config.disableSecurity ){
        if( !hasCreateContact()){
          if( !structKeyExists( formData, "createContact" ) && structKeyExists( variables.instance, "auth" ) && structKeyExists( variables.instance.auth, "userID" )){
            formData.createContact = variables.instance.auth.userID;
          }
        }

        if( !structKeyExists( formData, "updateContact" ) && structKeyExists( variables.instance, "auth" ) && structKeyExists( variables.instance.auth, "userID" )){
          formData.updateContact = variables.instance.auth.userID;
        }
      }
    } else {
      for( var logField in listToArray( logFields )){
        structDelete( formData, logField );
      }
    }

    if( variables.instance.debug ) {
      var collapse = "document.getElementById('#uuid#').style.display=(document.getElementById('#uuid#').style.display==''?'none':'');";
      var display = depth > 0 ? ' style="display:none;"' : '';

      writeOutput( '
        <div class="call">
          <h2 onclick="#collapse#">#entityName# #getID()#</h2>
          <table cellpadding="0" cellspacing="0" border="0" width="100%" id="#uuid#"#display#>
            <tr>
              <th colspan="2">Name: "#getName()#"</th>
            </tr>
      ' );
    }

    if( arrayLen( structFindValue( meta, "onMissingMethod" ))) {
      // this object can handle non-existing fields, so lets add those to the properties struct.
      var formDataKeys = structKeyArray( formData );
      for( var key in formDataKeys ){
        if( !structKeyExists( properties, key )){
          properties[key] = {
            "name" = key,
            "jsonData" = true
          };
        }
      }
    }

    // SAVE VALUES PASSED VIA FORM
    for( var key in properties ) {
      var property = properties[key];

      // Skip default fields (like buttons and PKs) and property not found in form or internal update fields
      if( // default field:
          listFindNoCase( defaultFields, key ) ||
          (
            // not in form
            !( structKeyExists( formdata, property.name )) &&
            // not added:
            !( structKeyExists( formData, "add_#property.name#" ) || ( structKeyExists( property, "singularName" ) && structKeyExists( formData, "add_#property.singularName#" ))) &&
            // not set (replaced):
            !( structKeyExists( formData, "set_#property.name#" )) &&
            // not removed:
            !( structKeyExists( formData, "remove_#property.name#" ) || ( structKeyExists( property, "singularName" ) && structKeyExists( formData, "remove_#property.singularName#" )))
          )
        ) {
        continue;
      }

      var reverseCFCLookup = meta.name;

      if( listFindNoCase( logFields, key )) {
        reverseCFCLookup = "root.model.logged";
      }

      param string property.fieldtype="string";

      var propertyEntityName = "";

      if( structKeyExists( property, "cfc" )) {
        propertyEntityName = getEntityName( property.cfc );
      }

      savecontent variable="debugoutput" {
        switch( property.fieldtype ) {
          case "one-to-many":
          case "many-to-many":
            // ████████╗ ██████╗       ███╗   ███╗ █████╗ ███╗   ██╗██╗   ██╗
            // ╚══██╔══╝██╔═══██╗      ████╗ ████║██╔══██╗████╗  ██║╚██╗ ██╔╝
            //    ██║   ██║   ██║█████╗██╔████╔██║███████║██╔██╗ ██║ ╚████╔╝
            //    ██║   ██║   ██║╚════╝██║╚██╔╝██║██╔══██║██║╚██╗██║  ╚██╔╝
            //    ██║   ╚██████╔╝      ██║ ╚═╝ ██║██║  ██║██║ ╚████║   ██║
            //    ╚═╝    ╚═════╝       ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝

            // Alias for set_ which overwrites linked data with new data
            if( structKeyExists( formdata, property.name )) {
              formdata["set_#property.name#"] = formdata[property.name];
            }

            // REMOVE
            if( structKeyExists( formdata, "set_#property.name#" ) || structKeyExists( formdata, "remove_#property.name#" )) {
              query = "SELECT b FROM #entityName# a JOIN a.#property.name# b WHERE a.id = :id ";
              params = { "id" = getID() };

              if( structKeyExists( formdata, "remove_#property.name#" )) {
                query &= " AND b.id IN ( :list )";
                params['list'] = listToArray( formdata['remove_#property.name#'] );
              }

              try {
                objectsToOverride = ORMExecuteQuery( query, params );
              } catch( any e ) {
                throw( type = "basecfc.global",
                       message = "Error in query: " & query,
                       detail = "Params: #serializeJSON( params )#" );
              }

              for( var objectToOverride in objectsToOverride ) {
                if( property.fieldType == "many-to-many" ) {
                  reverseField = objectToOverride.getReverseField( reverseCFCLookup, property.inverseJoinColumn );

                  evaluate( "remove#reverseField#(this)" );

                  if( variables.instance.debug ) {
                    writeOutput( '<p>objectToOverride.remove#reverseField#(this)</p>' );
                  }
                } else {
                  reverseField = objectToOverride.getReverseField( reverseCFCLookup, property.fkcolumn, false );

                  evaluate( "objectToOverride.set#reverseField#(javaCast('null',0))" );

                  if( variables.instance.debug ) {
                    writeOutput( '<p>objectToOverride.set#reverseField#(javaCast(''null'',0))</p>' );
                  }
                }

                evaluate( "remove#property.singularName#(objectToOverride)" );

                if( variables.instance.debug ) {
                  writeOutput( '<p>remove#property.singularName#(objectToOverride)</p>' );
                }
              }
            }

            // SET
            if( structKeyExists( formdata, "set_#property.name#" )) {
              var workData = formdata["set_#property.name#"];

              if( isSimpleValue( workData )) {
                if( isJSON( workData )) {
                  workData = deserializeJSON( workData );
                } else if( isJSON( '[' & workData & ']' )) {
                  workData = deSerializeJSON( '[' & workData & ']' ); // for lucee
                } else {
                  workData = listToArray( workData );
                }
              }

              if( !isArray( workData )) {
                workData = [ workData ];
              }

              if( arrayLen( workData )) {
                formdata["add_#property.singularName#"] = "";
              }

              for( var toAdd in workData ) {
                if( !isJSON( toAdd )) {
                  toAdd = serializeJSON( toAdd );
                }

                formdata["add_#property.singularName#"] = listAppend( formdata["add_#property.singularName#"], toAdd );
              }

              structDelete( formdata, "set_#property.name#" );
            }

            // ADD
            if( structKeyExists( formdata, "add_#property.singularName#" )) {
              workData = formdata["add_#property.singularName#"];

              if( isSimpleValue( workData )) {
                if( isJSON( workData )) {
                  workData = deSerializeJSON( workData );
                } else if( isJSON( '[' & workData & ']' )) {
                  workData = deSerializeJSON( '[' & workData & ']' ); // for lucee
                } else {
                  var itemList = workData;
                  workData = [];
                  for( var itemID in itemList ) {
                    arrayAppend( workData, { "id" = itemID });
                  }
                }
              }

              if( !isArray( workData )) {
                workData = [ workData ];
              }

              for( var updatedStruct in workData ) {
                if( isObject( updatedStruct )) {
                  objectToLink = updatedStruct;
                } else {
                  if( isJSON( updatedStruct )) {
                    updatedStruct = deSerializeJSON( updatedStruct );
                  }

                  if( isStruct( updatedStruct ) && structKeyExists( updatedStruct, "id" )) {
                    objectToLink = entityLoadByPK( propertyEntityName, updatedStruct.id );
                    structDelete( updatedStruct, "id" );
                  }

                  if( isNull( objectToLink )) {
                    objectToLink = entityNew( propertyEntityName );
                    entitySave( objectToLink );
                  }
                }

                // must init object so meta data is set:
                objectToLink = objectToLink.init();

                alreadyHasValue = evaluate( "has#property.singularName#(objectToLink)" );

                if( variables.instance.debug ) {
                  writeOutput( '<p>has#property.singularName#( #objectToLink.getName()# #objectToLink.getID()# ) -> #alreadyHasValue#</p>' );
                }

                ormAction = "#getID()#_#objectToLink.getID()#";

                if( !alreadyHasValue && !structKeyExists( variables.instance.ormActions, ormAction )) {
                  evaluate( "add#property.singularName#(objectToLink)" );

                  if( variables.instance.debug ) {
                    writeOutput( '<p>add#property.singularName#(objectToLink)</p>' );
                    writeOutput( ormAction );
                  }

                  reverseField = objectToLink.getReverseField( reverseCFCLookup, property.fkcolumn );

                  if( property.fieldtype == "many-to-many" ) {
                    updatedStruct['add_#reverseField#'] = '{"id":"#getID()#"}';
                    variables.instance.ormActions[ormAction] = property.name;
                  } else {
                    updatedStruct[reverseField] = getID();
                    variables.instance.ormActions[ormAction] = property.name;
                  }
                } else if( variables.instance.debug ) {
                  writeOutput( '<p>skipped add#property.singularName#(objectToLink) - already did that once</p>' );
                }

                // Go down the rabbit hole:
                if( structCount( updatedStruct )) {
                  if( variables.instance.debug ) {
                    writeOutput( '<b>ADD .save()</b>' );
                  }

                  objectToLink = objectToLink.save(
                    formData = updatedStruct,
                    depth= depth + 1,
                    calledBy = { entity = entityName, id = getID()}
                  );
                }

                // CLEANUP
                structDelete( local, "objectToLink" );
              }
            }

            // CLEANUP
            if( structKeyExists( local, "workData" )) {
              structDelete( local, "workData" );
            }

            break;
          default:
            // ████████╗ ██████╗        ██████╗ ███╗   ██╗███████╗
            // ╚══██╔══╝██╔═══██╗      ██╔═══██╗████╗  ██║██╔════╝
            //    ██║   ██║   ██║█████╗██║   ██║██╔██╗ ██║█████╗
            //    ██║   ██║   ██║╚════╝██║   ██║██║╚██╗██║██╔══╝
            //    ██║   ╚██████╔╝      ╚██████╔╝██║ ╚████║███████╗
            //    ╚═╝    ╚═════╝        ╚═════╝ ╚═╝  ╚═══╝╚══════╝

            // add new item (either through a struct or through inlineedit)
            // TODO: move inlineedit to crud.cfc
            if( len( trim( propertyEntityName )) && ((
                  structKeyExists( formData, property.name ) && (
                    isStruct( formData[property.name] ) &&
                    !isObject( formData[property.name] )
                  )
                ) || (
                  structKeyExists( property, "inlineedit" ) && (
                    structKeyExists( formdata, property.name ) ||
                    structKeyList( formdata ) contains '#property.name#_' ||
                    structKeyExists( formdata, "#property.name#id" )
                  )
                )
              )
            ) {
              if( propertyEntityName == calledBy.entity ) {
                // this prevents invinite loops
                var inlineEntity = entityLoadByPK( calledBy.entity, calledBy.id );
              } else {
                var inlineEntity = evaluate( "get#property.name#()" );

                if( isNull( inlineEntity )) {
                  if( structKeyExists( formData, "#property.name#id" )) {
                    var inlineEntity = entityLoadByPK( propertyEntityName, formData["#property.name#id"] );
                  }

                  if( isNull( inlineEntity ) &&
                      structKeyExists( formData, property.name ) &&
                      isStruct( formData[property.name] ) &&
                      structKeyExists( formData[property.name], "id" )) {
                    var inlineEntity = entityLoadByPK( propertyEntityName, formData[property.name].id );
                  }

                  if( isNull( inlineEntity )) {
                    var inlineEntity = entityNew( propertyEntityName );
                    entitySave( inlineEntity );
                  }
                }

                var inlineEntityParameters = {};

                // using struct to insert new values
                if( structKeyExists( formData, property.name ) && isStruct( formData[property.name] )) {
                  structAppend( inlineEntityParameters, formData[property.name] );
                }

                for( var formField in formData ) {
                  if( listLen( formField, '_' ) >= 2 && listFirst( formField, "_" ) == property.name ) {
                    inlineEntityParameters[listRest( formField, "_" )] = formData[formField];
                  }
                }

                if( structKeyExists( formdata, property.name ) &&
                    isJSON( formdata[property.name] ) &&
                    !structCount( inlineEntityParameters )) {
                  inlineEntityParameters = deSerializeJSON( formdata[property.name] );
                }
              }

              // must init object so meta data is set:
              inlineEntity = inlineEntity.init();

              formdata[property.name] = inlineEntity.getID();
            }

            // save value and link objects together
            if( structKeyExists( formdata, property.name )) {
              var valueToLog = "";
              var value = formdata[property.name];

              if( structKeyExists( property, "cfc" )) {
                // LINK TO OTHER OBJECT (USING PROVIDED ID)
                if( !isNull( inlineEntity )) {
                  var obj = inlineEntity;
                  structDelete( local, "inlineEntity" );
                } else if( isSimpleValue( value ) && len( trim( value )) && isJSON( value )) {
                  var valueFromJson = deserializeJSON( value );
                  if( isStruct( valueFromJson ) && structKeyExists( valueFromJson, "id" )) {
                    var obj = entityLoadByPK( propertyEntityName, valueFromJson.id );
                  }
                } else if( isSimpleValue( value ) && len( trim( value ))) {
                  var obj = entityLoadByPK( propertyEntityName, value );
                } else if( isObject( value )) {
                  var obj = value;
                }

                if( !isNull( obj )) {
                  // must init object so meta data is set:
                  obj = obj.init();

                  if( isNull( inlineEntityParameters)) {
                    var inlineEntityParameters = {};
                  }

                  inlineEntityParameters["#propertyEntityName#id"] = obj.getID();
                  var reverseField = obj.getReverseField( reverseCFCLookup, property.fkcolumn );
                  var alreadyHasValue = evaluate( "obj.has#reverseField#(this)" );

                  if( variables.instance.debug ) {
                    writeOutput( '<p>obj.has#reverseField#( #getID()# ) -> #alreadyHasValue#</p>' );
                  }

                  var ormAction = "#getID()#_#obj.getID()#";

                  if( !alreadyHasValue && !structKeyExists( variables.instance.ormActions, ormAction )) {
                    if( variables.instance.debug ) {
                      writeOutput( ormAction );
                    }

                    inlineEntityParameters['add_#reverseField#'] = '{"id":"#getID()#"}';
                    variables.instance.ormActions[ormAction] = property.name;
                  } else if( variables.instance.debug ) {
                    writeOutput( '<p>skipped add_#reverseField# - already did that once</p>' );
                  }

                  if( structCount( inlineEntityParameters )) {
                    if( variables.instance.debug ) {
                      writeOutput( '<b>.save()</b>' );
                    }

                    try{
                      obj.save(
                        depth = ( depth + 1 ),
                        calledBy = {
                          entity = entityName,
                          id = getID()
                        },
                        formData = inlineEntityParameters
                      );
                    } catch( any cfcatch ) {
                      if( variables.instance.debug ) {
                        writeDump( inlineEntityParameters );
                        writeDump( cfcatch );
                        abort;
                      } else {
                        var logMessage = cfcatch.message;
                        writeLog( text = logMessage, type = "fatal", file = request.appName );
                        rethrow;
                      }
                    }
                  }

                  valueToLog = obj.getName();
                  value = obj;

                  structDelete( local, "obj" );
                  structDelete( local, "inlineEntityParameters" );
                } else {
                  valueToLog = "removed";
                  structDelete( local, "value" );
                }
              } else if( isSimpleValue( value )) {
                // check inside json obj to see if an ID was passed in
                if( isJSON( value )) {
                  tmpValue = deserializeJSON( value );

                  if( isStruct( tmpValue ) && structKeyExists( tmpValue, "id" )) {
                    value = tmpValue.id;
                  }
                }

                // make sure integers are saved as that:
                if( structKeyExists( property, "ORMType" )) {
                  if( property.ORMType == "int" || property.ORMType == "integer" ) {
                    value = int( val( value ));
                  } else if( property.ORMType == "float" ) {
                    value = val( value );
                  }
                }

                valueToLog = left( value, 255 );
              }

              fn = "set" & property.name;

              if( !isNull( value )) {
                if( variables.instance.debug ) {
                  var dbugAttr = value.toString();
                  if( isJSON( dbugAttr ) && !isBoolean( dbugAttr ) && !isNumeric( dbugAttr )) {
                    writeOutput( '<p>#fn#() with:</p>' );
                    writeOutput( '<code class="prettyprint">#replace( dbugAttr, ',', ', ', 'all' )#</code>' );
                  } else {
                    writeOutput( '<p>#fn#( #dbugAttr# )</p>' );
                  }
                }

                try {
                  evaluate( "#fn#(value)" );
                } catch( any e ) {
                  writeLog( type = "error", text = "#entityName#.#fn#(?) failed", file = request.appName );
                }

                structDelete( local, "value" );
                structDelete( variables, "value" );

                var valueSetTo = "no value";

                if( !isNull( valueToLog )) {
                  valueSetTo = valueToLog;
                }

                writeLog( text = "called: #entityName#.#fn#(#valueSetTo#)", file = request.appName );
              } else {
                if( variables.instance.debug ) {
                  writeOutput( '<p>#fn#( NULL )</p>' );
                }

                evaluate( "#fn#(javaCast('null',0))" );
                writeLog( text = "called: #entityName#.#fn#( null )", file = request.appName );
              }
            }
        }
      }

      if( variables.instance.debug ) {
        var colID = createUuid();
        var collapseCol = "document.getElementById('#colID#').style.display=(document.getElementById('#colID#').style.display==''?'none':'');";
        writeOutput( '
          <tr>
            <th width="15%" valign="top" align="right" onclick="#collapseCol#">#key#</th>
            <td width="85%" id="#colID#">#len( trim( debugoutput )) ? debugoutput : 'no action'#</td>
          </tr>
        ' );
      }

      if( structKeyExists( local, "valueToLog" )) {
        if( !listFindNoCase( logFields, property.name )) {
          savedState[property.name] = valueToLog;
        }
        structDelete( local, "valueToLog" );
      }
    }

    if( variables.instance.debug ) {
      writeOutput( '
        </table>
      </div>
      ' );
    }

    if( depth == 0 &&
        canBeLogged &&
        entityName != "logentry" ) {
      // ormFlush();
      // entityReload( this );
      var entityToLog = this;
      var logFormData = {
        entity = entityToLog,
        deleted = false
      };

      if( structKeyExists( form, "logentry_note" )) {
        logFormData.note = form.logentry_note;
      }

      if( structKeyExists( form, "logentry_attachment" )) {
        logFormData.attachment = form.logentry_attachment;
      }

      var logentry = entityNew( "logentry" );
      entitySave( logentry );

      // must init object so meta data is set:
      logentry = logentry.init();

      variables.instance.log = logentry
        .save( logFormData )
        .enterIntoLog( "changed", savedState );
    }

    if( variables.instance.debug ) {
      writeOutput( getTickCount() - timer & "ms" );
    }

    if( depth == 0 && variables.instance.debug ) {
      writeOutput( '<code class="prettyprint">#replace( serializeJSON( variables.instance.ormActions ), ',', ', ', 'all' )#</code></div>' );
    }

    return this;
  }

  public array function getFieldsToDisplay( string type="inlineedit-line", struct formdata={} ) {
    var properties = variables.instance.inheritedProperties;
    var key = "";
    var result = [];

    switch( type ){
      case "inlineedit-line":
        var propertiesInInline = structFindKey( properties, "ininline", "all" );
        var tempProperties = {};

        for( var property in propertiesInInline ){
          tempProperties[property.owner.name] = property.owner;

          if( !structKeyExists( tempProperties[property.owner.name], "orderininline" )){
            tempProperties[property.owner.name].orderininline = 9001;
          }
        }

        var sortKey = structSort( tempProperties, 'numeric', 'asc', 'orderininline' );
        var currentField = "";

        for( var key in sortKey ){
          currentField = tempProperties[key].name;

          if( structKeyExists( formdata, currentField )){
            valueToDisplay = formdata[currentField];
          }

          if( !structKeyExists( local, "valueToDisplay" )){
            try{
              valueToDisplay = evaluate( "get" & currentField );
            }
            catch( any cfcatch ){}
          }

          if( structKeyExists( local, "valueToDisplay" ) && isObject( valueToDisplay )){
            valueToDisplay = valueToDisplay.getName();
          }

          param valueToDisplay="";

          arrayAppend( result, valueToDisplay );
          structDelete( local, "valueToDisplay" );
        }
        break;
      case "api":

        break;
    }

    return result;
  }
}