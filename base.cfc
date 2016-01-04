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

  param request.appName="basecfc"; // hash( getBaseTemplatePath())

  /** The constructor needs to be called in order to populate the instance
    * variables (like instance.meta which is used by the other methods)
    */
  public any function init() hint="Initializes the object" {
    variables.instance = {
      "config" = { "log" = false, "disableSecurity" = true },
      "debug" = false,
      "meta" = getMetaData(),
      "properties" = {}
    };

    variables.instance.properties = getInheritedProperties();

    if( structKeyExists( request, "context" ) && isStruct( request.context )) {
      structAppend( variables.instance, request.context, true );
    }

    structAppend( variables.instance, arguments, true );

    return this;
  }

  /** Returns a serialized JSON object (a string) representation of this object
    * using Adam Tuttle's deORM() - see below
    */
  public string function toString() {
    return serializeJSON( deORM( this ));
  }

  /** returns true if propertyToCheck is found in this object or its ancestors
    */
  public boolean function hasProperty( required string propertyToCheck ) {
    return structKeyExists( variables.instance.properties, propertyToCheck );
  }

  /** returns a struct containing this objects and its ancestors properties
    */
  public struct function getInheritedProperties() {
    var meta = variables.instance.meta;

    if( !structKeyExists( meta, "extends" )) {
      meta = { "extends" = meta };
    }

    var result = {};

    do {
      if( structKeyExists( meta, "properties" )) {
        for( var i=1; i <= arrayLen( meta.properties ); i++ ) {
          var property = meta.properties[i];

          for( var field in property ) {
            result[property.name][field] = property[field];

            if( structKeyExists( property, "cfc" )) {
              result[property.name]["entityName"] = getEntityName( property.cfc );
            }
          }
        }
      }

      if( structKeyExists( meta, "extends" )) {
        meta = meta.extends;
      }
    } while( structKeyExists( meta, "extends" ));

    return result;
  }

  /** returns the entity name (as per CFML ORM standard)
    */
  public string function getEntityName( string className=getClassName()) {
    var sessionFactory = ORMGetSessionFactory();
    var metaData = sessionFactory.getClassMetadata( listLast( className, '.' ));

    return metaData.getEntityName();
  }

  /** returns the full cfc path
    */
  public string function getClassName() {
    return variables.instance.meta.fullname;
  }

  /** find the corresponding field in the joined object (using the FKColumn)
    */
  public string function getReverseField( required string cfc,
                                          required string fkColumn,
                                          boolean singular=true ) {
    var propertiesWithCFC = structFindKey( variables.instance.properties, "cfc", "all" );
    var field = 0;
    var fieldFound = 0;

    if( !arrayLen( propertiesWithCFC )) {
      var logMessage = "getReverseField() ERROR: nothing linked to #cfc#.";
      writeLog( text = logMessage, type = "fatal", file = request.appName );
      throw( type = "basecfc.getReverseField", message = logMessage );
    }

    for( var property in propertiesWithCFC ) {
      field = property.owner;

      if( structKeyExists( field, "fkcolumn" ) && field.fkColumn != fkColumn ) {
        continue;
      }

      if(!(( structKeyExists( field, "fkcolumn" ) && field.fkColumn == fkColumn ) || field.cfc == cfc )) {
        continue;
      }

      if( field.cfc == cfc && field.fkColumn == fkColumn ) {
        fieldFound = 1;
        break;
      }

      var testObj = createObject( cfc ).init();

      if( isInstanceOf( testObj, field.cfc )) {
        fieldFound = 2;
        break;
      }

      if( testObj.getClassName() == field.cfc ) {
        fieldFound = 3;
        break;
      }
    }

    var propertyWithFK = structFindValue({ a = propertiesWithCFC }, fkColumn, 'all' );

    if( arrayLen( propertyWithFK ) == 1 ) {
      field = propertyWithFK[1].owner;
      fieldFound = 4;
    }

    if( fieldFound == 0 ) {
      var logMessage = "getReverseField() ERROR: no reverse field found for fk #fkColumn# in cfc #cfc#.";
      writeLog( text = logMessage, type = "fatal", file = request.appName );
      throw( type = "basecfc.getReverseField", message = logMessage );
    }

    var result = field.name;

    if( singular && structKeyExists( field, 'singularName' )) {
      result = field['singularName'];
    }

    return result;
  }

  /** This persists objects extending this base cfc into a database using ORM
    * It goes through all passed fields and updates all linked objects recursively
    */
  public any function save( required struct formData={}
                              hint="The data structure containing the new data to be saved",
                            struct calledBy={entity='',id=''}
                              hint="Used to prevent inv. loops (don't keep adding the caller to the callee and vice versa)",
                            numeric depth=0
                              hint="Used to prevent inv. loops (don't keep going infinitely)" ) {
    // Hard coded depth limit
    if( depth > 10 ) {
      var logMessage = "Infinite loop fail safe triggered";
      writeLog( text = logMessage, type = "fatal", file = request.appName );
      throw( type = "basecfc.global", message = logMessage );
    }

    // objects using .save() must be initialised using the constructor
    if( not structKeyExists( variables, "instance" )) {
      var logMessage = "Basecfc not initialised";
      writeLog( text = logMessage, type = "fatal", file = request.appName );
      throw( type = "basecfc.global", message = logMessage );
    }

    var timer = getTickCount();
    var entityName = getEntityName();
    var canBeLogged = ( variables.instance.config.log && isInstanceOf( this, "root.model.logged" ));
    var debugoutput = "";
    var defaultFields = "log,id,fieldnames,submitbutton,#entityName#id";
    var inheritedProperties = variables.instance.properties;
    var logFields = "createContact,createDate,createIP,updateContact,updateDate,updateIP";
    var savedState = {};

    if( isNull( getDeleted())) {
      formData.deleted=false;
    }

    if( depth == 0 ) {
      request.basecfc.instructionsOrder = {};
      request.basecfc.queuedInstructions = {};
      request.basecfc.queuedObjects = { "0" = this };

      if( canBeLogged && !isInstanceOf( this, "root.model.contact" )) {
        if( !len( trim( getCreateDate()))) {
          formData.createDate = now();
        }

        if( !len( trim( getCreateIP()))) {
          formData.createIP = cgi.remote_host;
        }

        formData.updateDate = now();
        formData.updateIP = cgi.remote_host;

        if( !variables.instance.config.disableSecurity ) {
          if( !hasCreateContact()) {
            if( !structKeyExists( formData, "createContact" ) &&
                structKeyExists( variables.instance, "auth" ) &&
                structKeyExists( variables.instance.auth, "userID" )) {
              formData.createContact = variables.instance.auth.userID;
            }
          }

          if( !structKeyExists( formData, "updateContact" ) &&
              structKeyExists( variables.instance, "auth" ) &&
              structKeyExists( variables.instance.auth, "userID" )) {
            formData.updateContact = variables.instance.auth.userID;
          }
        }
      } else {
        for( var logField in listToArray( logFields )) {
          structDelete( formData, logField );
        }
      }
    }

    if( variables.instance.debug ) {
      var uuid = createUUID();
      var collapse = "document.getElementById('#uuid#').style.display=(document.getElementById('#uuid#').style.display==''?'none':'');";
      var display = ' style="display:none;"';

      if( !structKeyExists( request, "basecfc-save" )) {
        request["basecfc-save"] = true;
        writeOutput( '
          <script src="https://cdn.rawgit.com/google/code-prettify/master/loader/run_prettify.js"></script>
          <style>
            td,th,h2{padding:3px;}
            table,td,th{border:1px solid ##8091A4}
            td,th{padding:3px;border-top:0;border-left:0;background-color:##B5BFCB}
            .basecfc-debug{width:900px;margin:0 auto}
            .basecfc-debug .call{font-family:monospace;border:2px solid ##264160; padding:5px; margin-bottom:15px}
            .basecfc-debug h2{background:##3D5774;cursor:pointer;color:white;margin:0}
            .basecfc-debug table{border-color:##8091A4;border-right:0;border-bottom:0}
            .result{color:red}
          </style>
        ' );
      }

      if( depth == 0 ) {
        writeLog( text = "~~~ start basecfc.save() ~~~", file = request.appName );
        writeOutput( '<div class="basecfc-debug">' );
        display = '';
      }

      writeOutput( '
        <div class="call">
          <h2 onclick="#collapse#">#depth#:#entityName#:#getID()#</h2>
          <table cellpadding="0" cellspacing="0" border="0" width="100%" id="#uuid#"#display#>
            <tr>
              <th colspan="2">Name: "#getName()#"</th>
            </tr>
      ' );
    }

    // This object can handle non-existing fields, so lets add those to the properties struct.
    if( arrayLen( structFindValue( variables.instance.meta, "onMissingMethod" ))) {
      for( var key in structKeyArray( formData )) {
        if( !structKeyExists( inheritedProperties, key )) {
          structInsert( inheritedProperties, key, {
            "name" = key,
            "jsonData" = true
          }, true );
        }
      }
    }

    // SAVE VALUES PASSED VIA FORM
    for( var key in inheritedProperties ) {
      var property = inheritedProperties[key];

      // WARNING UGLY IF STATEMENT COMING UP
      // Skip default fields (like buttons and PKs) and property not found in form or internal update fields
      if(
          // default field:
          listFindNoCase( defaultFields, key ) ||
          (

            // not in form
            !structKeyExists( formdata, property.name ) &&

            // not added:
            !(
              structKeyExists( formData, "add_#property.name#" ) ||
              (
                structKeyExists( property, "singularName" ) &&
                structKeyExists( formData, "add_#property.singularName#" )
              )
            ) &&

            // not set (replaced):
            !structKeyExists( formData, "set_#property.name#" ) &&

            // not removed:
            !(
              structKeyExists( formData, "remove_#property.name#" ) ||
              (
                structKeyExists( property, "singularName" ) &&
                structKeyExists( formData, "remove_#property.singularName#" )
              )
            )
          )
        ) {
        continue;
      }

      param string property.fieldtype="string";

      var reverseCFCLookup = listFindNoCase( logFields, key ) ? "root.model.logged" : variables.instance.meta.name;
      var propertyEntityName = structKeyExists( property, "cfc" ) ? getEntityName( property.cfc ) : "";

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
                params['list'] = listToArray( formdata["remove_#property.name#"] );
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
                  queueInstruction( objectToOverride, objectToOverride.getID(), "remove#reverseField#", this );
                } else {
                  reverseField = objectToOverride.getReverseField( reverseCFCLookup, property.fkcolumn, false );
                  queueInstruction( objectToOverride, objectToOverride.getID(), "set#reverseField#", "null" );
                }

                queueInstruction( this, getID(), "remove#property.singularName#", objectToOverride );
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
                var entitiesToAdd = [];

                for( var toAdd in workData ) {
                  if( !isJSON( toAdd )) {
                    toAdd = serializeJSON( toAdd );
                  }

                  arrayAppend( entitiesToAdd, toAdd );
                }

                formdata["add_#property.singularName#"] = arrayToList( entitiesToAdd );
              }

              structDelete( formdata, "set_#property.name#" );
            }

            // ADD
            if( structKeyExists( formdata, "add_#property.singularName#" )) {
              var workData = formdata["add_#property.singularName#"];

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

              var addInstructions = [];

              for( var updateStruct in workData ) {
                structDelete( local, "objectToLink" );

                if( isObject( updateStruct )) {
                  var objectToLink = updateStruct;
                } else {
                  if( isSimpleValue( updateStruct ) && isGUID( updateStruct )) {
                    updateStruct = '{"id":"#updateStruct#"}';
                  }

                  if( isJSON( updateStruct )) {
                    updateStruct = deSerializeJSON( updateStruct );
                  }

                  if( isStruct( updateStruct ) && structKeyExists( updateStruct, "id" )) {
                    var objectToLink = entityLoadByPK( propertyEntityName, updateStruct.id );
                    structDelete( updateStruct, "id" );
                  }

                  if( isNull( objectToLink )) {
                    var objectToLink = entityNew( propertyEntityName );
                    entitySave( objectToLink );
                  }
                }

                // must init object so meta data is set:
                objectToLink = objectToLink.init();

                if( structKeyExists( objectToLink, "getID" ) && structKeyExists( objectToLink, "getEntityName" )) {
                  // trigger update
                  updateStruct["#objectToLink.getEntityName()#id"] = objectToLink.getID();
                }

                var alreadyHasValue = false;

                if( structKeyExists( request.basecfc.queuedInstructions, getID()) && structKeyExists( request.basecfc.queuedInstructions[getID()], "add#property.singularName#" )) {
                  alreadyHasValue = structKeyExists( request.basecfc.queuedInstructions[getID()]["add#property.singularName#"], objectToLink.getID());
                }

                if( !alreadyHasValue ) {
                  alreadyHasValue = evaluate( "has#property.singularName#(objectToLink)" );

                  if( !alreadyHasValue ) {
                    queueInstruction( this, getID(), "add#property.singularName#", objectToLink );

                    reverseField = objectToLink.getReverseField( reverseCFCLookup, property.fkcolumn );

                    if( property.fieldtype == "many-to-many" ) {
                      updateStruct["add_#reverseField#"] = getID();
                    } else {
                      updateStruct[reverseField] = getID();
                    }

                    if( variables.instance.debug ) {
                      writeLog( text = "called: #objectToLink.getID()#.save(#depth+1#)", file = request.appName );
                    }

                    // Go down the rabbit hole:
                    objectToLink.save(
                      depth = ( depth + 1 ),
                      formData = updateStruct,
                      calledBy = {
                        entity = entityName,
                        id = getID()
                      }
                    );
                  }
                }
              }

              structDelete( formdata, "add_#property.singularName#" );
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
            var passedInStructure = ( structKeyExists( formData, property.name ) &&
                  isStruct( formData[property.name] ) &&
                  !isObject( formData[property.name] ));
            var validInlineEditForm = ( structKeyExists( property, "inlineedit" ) && (
                  structKeyExists( formdata, property.name ) ||
                  structKeyExists( formdata, "#property.name#id" ) ||
                  structKeyList( formdata ) contains '#property.name#_' ));

            if( passedInStructure || validInlineEditForm ) {
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

                var updateStruct = {};

                // using struct to insert new values
                if( structKeyExists( formData, property.name ) && isStruct( formData[property.name] )) {
                  structAppend( updateStruct, formData[property.name] );
                }

                for( var formField in formData ) {
                  if( listLen( formField, '_' ) >= 2 && listFirst( formField, "_" ) == property.name ) {
                    updateStruct[listRest( formField, "_" )] = formData[formField];
                  }
                }

                if( structKeyExists( formdata, property.name ) &&
                    isJSON( formdata[property.name] ) &&
                    !structCount( updateStruct )) {
                  updateStruct = deSerializeJSON( formdata[property.name] );
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
                if( isNull( updateStruct)) {
                  var updateStruct = {};
                }

                // LINK TO OTHER OBJECT (USING PROVIDED ID)
                if( !isNull( inlineEntity )) {
                  var obj = inlineEntity;
                  structDelete( local, "inlineEntity" );
                } else if( isObject( value )) {
                  var obj = value;
                } else {
                  if( isSimpleValue( value ) && isGUID( value )) {
                    value = '{"id":"#value#"}';
                  }

                  if( isSimpleValue( value ) && len( trim( value )) && isJSON( value )) {
                    value = deserializeJSON( value );
                  }

                  if( isStruct( value ) && structKeyExists( value, "id" )) {
                    var obj = entityLoadByPK( propertyEntityName, value.id );
                  }
                }

                if( !isNull( obj )) {
                  // must init object so meta data is set:
                  obj = obj.init();

                  var reverseField = obj.getReverseField( reverseCFCLookup, property.fkcolumn );
                  var alreadyHasValue = evaluate( "obj.has#reverseField#(this)" );

                  if( !alreadyHasValue ) {
                    updateStruct["add_#reverseField#"] = getID();
                  }

                  if( structCount( updateStruct )) {
                    // provide entityID so an update triggers (instead of an insert)
                    if( !isNull( obj.getID())) {
                      updateStruct["#propertyEntityName#id"] = obj.getID();
                    }

                    if( variables.instance.debug ) {
                      writeLog( text = "called: #obj.getID()#.save(#depth+1#)", file = request.appName );
                    }

                    try{
                      obj.save(
                        depth = ( depth + 1 ),
                        formData = updateStruct,
                        calledBy = {
                          entity = entityName,
                          id = getID()
                        }
                      );
                    } catch( any cfcatch ) {
                      if( variables.instance.debug ) {
                        writeDump( entityName );
                        writeDump( updateStruct );
                        writeDump( cfcatch );
                        abort;
                      } else {
                        var logMessage = cfcatch.message;
                        rethrow;
                        writeLog( text = logMessage, type = "fatal", file = request.appName );
                      }
                    }
                  }

                  valueToLog = obj.getName();
                  value = obj;

                  structDelete( local, "obj" );
                  structDelete( local, "updateStruct" );
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

              var fn = "set" & property.name;

              if( !isNull( value )) {
                if( variables.instance.debug ) {
                  var dbugAttr = value.toString();
                  if( isJSON( dbugAttr ) && !isBoolean( dbugAttr ) && !isNumeric( dbugAttr )) {
                    writeOutput( '<p>#fn#( <code class="prettyprint">#replace( dbugAttr, ',', ',<br />', 'all' )#</code> )</p>' );
                  } else {
                    writeOutput( '<p>#fn#( #dbugAttr# )</p>' );
                  }
                }

                queueInstruction( this, getID(), fn, value );

                structDelete( local, "value" );
                structDelete( variables, "value" );
              } else {
                queueInstruction( this, getID(), fn, "null" );
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
      writeOutput( '</table>' );
      writeOutput( getTickCount() - timer & "ms<br />" );
      writeOutput( '</div>' );
    }

    // Process queued instructions
    if( depth == 0 ) {
      if( canBeLogged && entityName != "logentry" ) {
        var logentry = entityNew( "logentry" ).init();

        entitySave( logentry );

        logentry.enterIntoLog( "changed", savedState, this );
      }

      processQueue();
    }

    return this;
  }

  /** Processes the queued instructions in one batch
    */
  private void function processQueue() {
    var instructionsTimer = 0;

    if( variables.instance.debug ) {
      writeLog( text = "~~ start processing queue ~~", file = request.appName );
    }

    var queuedInstructions = request.basecfc.queuedInstructions;

    // per object
    for( var objectid in queuedInstructions ) {
      var instructionOrder = request.basecfc.instructionsOrder[objectid];
      var object = request.basecfc.queuedObjects[objectid];
      var objectInstructions = queuedInstructions[objectid];

      var sortedCommands = structKeyArray( instructionOrder );
      arraySort( sortedCommands, "textNoCase", "asc" );

      // per command
      for( var command in sortedCommands ) {
        var values = instructionOrder[command];

        // per value
        for( var valueKey in values ) {
          var value = objectInstructions[command][valueKey];

          // if( variables.instance.debug ) {
          //   writeOutput("<br />#objectid#.#command#(#serializeJSON(deORM(value))#)");
          // }

          var finalInstruction = ( isSimpleValue( value ) && value == "null" ) ?
                "object." & command & "(javaCast('null',0))" :
                "object." & command & "(value)";
          var logMessage = "called: [#objectid#] #finalInstruction#";
          var instructionTimer = getTickCount();

          try {
            evaluate( finalInstruction );
            if( variables.instance.debug ) {
              writeLog( text = logMessage, file = request.appName );
            }
          } catch( any e ) {
            logMessage &= " FAILED";
            writeLog( text = logMessage, file = request.appName, type = "fatal" );
            if( variables.instance.debug ) {
              rethrow;
            }
          }

          instructionsTimer += ( getTickCount() - instructionTimer );
        }
      }
    }

    if( variables.instance.debug ) {
      writeLog( text = "~~ finished queue in " & instructionsTimer & "ms. ~~", file = request.appName );
    }
  }

  /** Method to add instructions to the queue, which is later processed using
    * processQueue() overwriting previous instructions so no duplicate actions
    * are taking place
    */
  private void function queueInstruction( required component entity, string id="0", required string command, required any value ) {
    param struct request.basecfc.instructionsOrder={};
    param struct request.basecfc.queuedInstructions={};
    param struct request.basecfc.queuedObjects={};

    request.basecfc.queuedObjects[id] = entity;

    if( !structKeyExists( request.basecfc.instructionsOrder, id )) {
      request.basecfc.instructionsOrder[id] = {};
    }

    if( !structKeyExists( request.basecfc.queuedInstructions, id )) {
      request.basecfc.queuedInstructions[id] = {};
    }

    if( !structKeyExists( request.basecfc.queuedInstructions[id], command )) {
      request.basecfc.queuedInstructions[id][command] = {};
    }

    if( isObject( value ) && structKeyExists( value, "getID" )) {
      // Adds multiple values:
      request.basecfc.queuedInstructions[id][command][value.getID()] = value;

      if( !structKeyExists( request.basecfc.instructionsOrder[id], command )) {
        request.basecfc.instructionsOrder[id][command] = [];
      }

      var existingInstructionIndex = arrayFindNoCase( request.basecfc.instructionsOrder[id][command], value.getID());

      if( existingInstructionIndex && left( command, 3 ) != "add" ) {
        arrayDeleteAt( request.basecfc.instructionsOrder[id][command], existingInstructionIndex );
      }

      if( left( command, 6 ) == "remove" ) {
        arrayPrepend( request.basecfc.instructionsOrder[id][command], value.getID());
      } else {
        arrayAppend( request.basecfc.instructionsOrder[id][command], value.getID());
      }
    } else {
      // Adds single value:
      request.basecfc.queuedInstructions[id][command].value = value;
      request.basecfc.instructionsOrder[id][command] = ["value"];
    }
  }

  /** Tests a string to be a valid GUID by using the built-in isValid method and
    * falling back on reformatting the string and rechecking
    */
  private boolean function isGUID( required string text ) {
    if( len( text ) < 32 ) {
      return false;
    }

    var validGUID = isValid( "guid", text );

    if( validGUID ) {
      return true;
    }

    return isValid( "guid", formatAsGUID( text ));
  }

  private string function formatAsGUID( required string text ) {
    var massagedText = reReplace( text, '\W', '', 'all' );

    if( len( massagedText ) < 32 ) {
      return text; // return original (not my problem)
    }

    massagedText = insert( '-', massagedText, 20 );
    massagedText = insert( '-', massagedText, 16 );
    massagedText = insert( '-', massagedText, 12 );
    massagedText = insert( '-', massagedText, 8 );

    return massagedText;
  }

  private component function toComponent( required any variable, required string entityName ) {
    var obj = 0;

    if( isObject( variable )) {
      var obj = variable;
    } else {
      if( isSimpleValue( variable ) && isGUID( variable )) {
        variable = '{"id":"#variable#"}';
      }

      if( isJSON( variable )) {
        variable = deSerializeJSON( variable );
      }

      if( isStruct( variable ) && structKeyExists( variable, "id" )) {
        var obj = entityLoadByPK( entityName, variable.id );
        structDelete( variable, "id" );
      }

      if( isNull( obj )) {
        var obj = entityNew( entityName );
        entitySave( obj );
      }
    }

    // must init object so meta data is set:
    if( isObject( obj ) && structKeyExists( obj, "init" )) {
      return obj.init();
    }

    var logMessage = "Variable could not be translated to component of type #entityName#";
    writeLog( text = logMessage, type = "fatal", file = request.appName );
    throw( type = "basecfc.toComponent", message = logMessage );
  }

  /** Returns a simplified representation of the object
    * By Adam Tuttle ( http://fusiongrokker.com/post/deorm ).
    */
  private any function deORM( required any data hint="One or more entities to be converted to a less complex representation" ) {
    var deWormed = {};

    if( isSimpleValue( data )) {
      deWormed = data;

    } else if( isObject( data )) {
      var md = getMetadata( data );

      do {
        if( structKeyExists( md, 'properties' )) {
          for( var prop in md.properties) {
            if( !structKeyExists( data, 'get' & prop.name) || ( structKeyExists( prop, 'fieldtype' ) && findNoCase( "-to-", prop.fieldtype ))) {
              continue;
            }

            deWormed[prop.name] = evaluate( "data.get#prop.name#()" );
          }
        }

        if( structKeyExists( md, 'extends' )) {
          md = md.extends;
        }

      } while( structKeyExists( md, 'extends' ));

    } else if( isStruct( data )) {
      for (var key in data) {
        deWormed[ key ] = deORM( data[key] );
      }

    } else if( isArray( data )) {
      var deWormed = [];

      for( var el in data ) {
        arrayAppend( deWormed, deORM( el ));
      }

    } else {
      deWormed = getMetadata( data );
    }

    return deWormed;
  }

  /** This method needs to be moved to a controller, since it has to do with output.
    */
  public array function getFieldsToDisplay( string type="inlineedit-line", struct formdata={} ) {
    var result = [];

    switch( type ) {
      case "inlineedit-line":
        var propertiesInInline = structFindKey( variables.instance.properties, "ininline", "all" );
        var tempProperties = {};

        for( var property in propertiesInInline ) {
          tempProperties[property.owner.name] = property.owner;

          if( !structKeyExists( tempProperties[property.owner.name], "orderininline" )) {
            tempProperties[property.owner.name].orderininline = 9001;
          }
        }

        var sortKey = structSort( tempProperties, 'numeric', 'asc', 'orderininline' );
        var currentField = "";

        for( var key in sortKey ) {
          currentField = tempProperties[key].name;

          if( structKeyExists( formdata, currentField )) {
            valueToDisplay = formdata[currentField];
          }

          if( !structKeyExists( local, "valueToDisplay" )) {
            try{
              valueToDisplay = evaluate( "get" & currentField );
            }
            catch( any cfcatch ) {}
          }

          if( structKeyExists( local, "valueToDisplay" ) && isObject( valueToDisplay )) {
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