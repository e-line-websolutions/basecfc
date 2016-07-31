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
  property name="id" type="string" fieldType="id" generator="uuid";
  property persistent=false inapi=false name="version" default="3.2.0" type="string";

  param request.appName="basecfc";

  /**
    * The constructor needs to be called in order to populate the instance
    * variables (like instance.meta which is used by the other methods)
    */
  public component function init() {
    param variables.name="";
    param variables.deleted=false;
    param variables.sortorder=0;

    variables.instance = {
      "config" = { "log" = false, "disableSecurity" = true },
      "debug" = false,
      "entities" = {},
      "id" = createUUID(),
      "meta" = getMetaData(),
      "sanitizeDataTypes" = [
        "date",
        "datetime",
        "double",
        "float",
        "int",
        "integer",
        "numeric",
        "percentage",
        "timestamp"
      ]
    };

    if( structKeyExists( url, "reload" )) {
      var allCacheIds = cacheGetAllIds();
      if( !arrayIsEmpty( allCacheIds )) {
        cacheRemove( arrayToList( allCacheIds ), false );
      }
    }

    if( !structKeyExists( request, "allEntities" )) {
      var cachedEntities = cacheGet( "#request.appName#-allEntities" );
      if( isNull( cachedEntities )) {
        var cachedEntities = {};
        var allEntities = ORMGetSessionFactory().getAllClassMetadata();
        for( var key in allEntities ) {
          var entity = allEntities[ key ];
          structInsert( cachedEntities, key, {
            "name" = entity.getEntityName(),
            "table" = entity.getTableName()
          });
        }
        cachePut( "#request.appName#-allEntities", cachedEntities );
      }
      request.allEntities = cachedEntities;
    }

    if( structKeyExists( request, "context" ) && isStruct( request.context )) {
      structAppend( variables.instance, request.context, true );
    }

    structAppend( variables.instance, arguments, true );

    param variables.instance.config.root="root";

    variables.instance.className = getClassName();
    variables.instance.properties = getInheritedProperties();

    if((
        !structKeyExists( instance.properties, "name" ) ||
        !structKeyExists( instance.properties, "deleted" ) ||
        !structKeyExists( instance.properties, "sortorder" )
      ) && instance.className != "basecfc.base" ) {
      throw( "basecfc.init", "Missing essential properties", "Objects extending basecfc must have a name, deleted and sortorder property." );
    }

    return this;
  }

  /**
    * This persists objects extending this base cfc into a database using ORM
    * It goes through all passed fields and updates all linked objects recursively
    *
    * @formData The data structure containing the new data to be saved
    * @depth Used to prevent inv. loops (don't keep going infinitely)
    */
  public component function save( required struct formData={}, numeric depth=0, component validationService, component sanitationService ) {
    if( depth == 0 ) {
      request.basecfc = {};
    }

    // objects using .save() must be initialised using the constructor
    if( not structKeyExists( variables, "instance" )) {
      var logMessage = "Basecfc not initialised";
      basecfcLog( text = logMessage, type = "fatal", file = request.appName );
      throw( type = "basecfc.global", message = logMessage );
    }

    // Hard coded depth limit
    if( depth > 10 ) {
      var logMessage = "Infinite loop fail safe triggered";
      basecfcLog( text = logMessage, type = "fatal", file = request.appName );

      if( instance.debug ) {
        try {
          writeDump( request.basecfc.queuedInstructions );
          abort;
        } catch ( any e ) {
          throw( type = "basecfc.global", message = logMessage );
        }
      }

      throw( type = "basecfc.global", message = logMessage );
    }

    var timer = getTickCount();
    var entityName = getEntityName();
    var canBeLogged = ( instance.config.log && isInstanceOf( this, "#instance.config.root#.model.logged" ));
    var defaultFields = "log,id,fieldnames,submitbutton,#entityName#id";
    var inheritedProperties = instance.properties;
    var logFields = "createContact,createDate,createIP,updateContact,updateDate,updateIP";
    var savedState = {};

    var logFieldsAsArray = listToArray( logFields );
    for( var logField in logFieldsAsArray ) {
      structDelete( formData, logField );
    }

    if( isNull( deleted )) {
      formData.deleted=false;
    }

    if( depth == 0 ) {
      request.basecfc.instructionsOrder = {};
      request.basecfc.queuedInstructions = {};
      request.basecfc.queuedObjects = { "#instance.id#" = this };
      request.basecfc.ormSession = ormGetSession();

      if( canBeLogged ) {
        if( !len( trim( getCreateDate()))) {
          formData.createDate = now();
        }

        if( !len( trim( getCreateIP()))) {
          formData.createIP = cgi.remote_host;
        }

        formData.updateDate = now();
        formData.updateIP = cgi.remote_host;

        if( !instance.config.disableSecurity ) {
          if( !hasCreateContact()) {
            if( !structKeyExists( formData, "createContact" ) &&
                structKeyExists( instance, "auth" ) &&
                structKeyExists( instance.auth, "userID" ) &&
                isValidGUID( instance.auth.userID )) {
              formData.createContact = instance.auth.userID;
            }
          }

          if( !structKeyExists( formData, "updateContact" ) &&
              structKeyExists( instance, "auth" ) &&
              structKeyExists( instance.auth, "userID" ) &&
                isValidGUID( instance.auth.userID )) {
            formData.updateContact = instance.auth.userID;
          }
        }
      }

      if( structKeyExists( arguments, "validationService" )) {
        request.basecfc.validationService = validationService;
      }

      if( structKeyExists( arguments, "sanitationService" )) {
        request.basecfc.sanitationService = sanitationService;
      }
    }

    var useSanitation = structKeyExists( request.basecfc, "sanitationService" );

    if( useSanitation ) {
      var sanitationInstance = request.basecfc.sanitationService;
    }

    if( instance.debug ) {
      var debugid = createUUID();
      var collapse = "document.getElementById('#debugid#').style.display=(document.getElementById('#debugid#').style.display==''?'none':'');";
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
        basecfcLog( text = "~~~ start basecfc.save() ~~~", file = request.appName );
        writeOutput( '<div class="basecfc-debug">' );
        display = '';
      }

      writeOutput( '
        <div class="call">
          <h2 onclick="#collapse#">#depth#:#entityName#:#getID()#</h2>
          <table cellpadding="0" cellspacing="0" border="0" width="100%" id="#debugid#"#display#>
            <tr>
              <th colspan="2">Name: "#getName()#"</th>
            </tr>
      ' );
    }

    // This object can handle non-existing fields, so lets add those to the properties struct.
    if( arrayLen( structFindValue( instance.meta, "onMissingMethod" ))) {
      var formDataKeys = structKeyArray( formData );
      for( var key in formDataKeys ) {
        if( !structKeyExists( inheritedProperties, key ) && !listFindNoCase( defaultFields, key )) {
          structInsert( inheritedProperties, key, { "name" = key, "jsonData" = true }, true );
        }
      }
    }

    // SAVE VALUES PASSED VIA FORM
    for( var key in inheritedProperties ) {
      var property = inheritedProperties[key];
      var valueToLog = "";

      if( structKeyExists( property, "removeFromformData" ) && property.removeFromformData ) {
        continue;
      }

      // WARNING UGLY IF STATEMENT COMING UP
      // Skip default fields (like buttons and PKs) and property not found in form or internal update fields
      if(
          // default field:
          listFindNoCase( defaultFields, key ) || (

            // not in form
            !structKeyExists( formData, property.name ) &&

            // not added:
            !(
              structKeyExists( formData, "add_#property.name#" ) || (
                structKeyExists( property, "singularName" ) &&
                structKeyExists( formData, "add_#property.singularName#" )
              )
            ) &&

            // not set (replaced):
            !structKeyExists( formData, "set_#property.name#" ) &&

            // not removed:
            !(
              structKeyExists( formData, "remove_#property.name#" ) || (
                structKeyExists( property, "singularName" ) &&
                structKeyExists( formData, "remove_#property.singularName#" )
              )
            )
          ) || (
            structKeyExists( formData, property.name ) &&
            isSimpleValue( formData[property.name] ) &&
            !len( trim( formData[property.name] ))
          )
        ) {
        continue;
      }

      var debugoutput = "";

      savecontent variable="debugoutput" {
        param string property.fieldtype="string";

        if( structKeyExists( property, "cfc" )) {
          var reverseCFCLookup = listFindNoCase( logFields, key ) ? "#instance.config.root#.model.logged" : instance.className;
        }

        switch( property.fieldtype ) {
          case "one-to-many":
          case "many-to-many":
          //  _____           __  __
          // |_   _|___  ___ |  \/  | __ _  _ _  _  _
          // | | | / _ \|___|| |\/| |/ _` || ' \| || |
          //   |_| \___/     |_|  |_|\__,_||_||_|\_, |
          //                                     |__/
            valueToLog = [];

            // Alias for set_ which overwrites linked data with new data
            if( structKeyExists( formData, property.name )) {
              formData[ "set_#property.name#" ] = formData[ property.name ];
            }

            // REMOVE
            if( structKeyExists( formData, "set_#property.name#" ) || structKeyExists( formData, "remove_#property.name#" )) {
              var tableName = getTableName();
              var otherTable = getTableName( property.cfc );
              var sqlparams = { "id" = getID()};

              try {
                if( structKeyExists( server, "lucee" )) {
                  // temporary solution for Lucee 5 bug I get with HQL queries:
                  var sql = " SELECT b.* FROM #tableName# a ";
                  if( property.fieldType == "one-to-many" ) {
                    sql &= "INNER JOIN #otherTable# b ON a.id = b.#property.fkcolumn# ";
                  } else if( property.fieldType == "many-to-many" ) {
                    sql &= " INNER JOIN #property.linkTable# c ON a.id = c.#property.fkcolumn# INNER JOIN #otherTable# b ON c.#property.inversejoincolumn# = b.id ";
                  }
                  sql &= " WHERE a.id = :id ";
                  if( structKeyExists( formData, "remove_#property.name#" )) {
                    sql &= " AND b.id IN ( :list )";
                    sqlparams[ "list" ] = listToArray( formData[ "remove_#property.name#" ]);
                    arrayAppend( valueToLog, "removed #property.name#" );
                  }
                  var sqlQuery = request.basecfc.ormSession.createSQLQuery( sql ).addEntity( property.entityName );
                  for( var key in sqlparams ) {
                    var sqlvalue = sqlparams[ key ];
                    if( isArray( sqlvalue )) {
                      sqlQuery = sqlQuery.setParameterList( key, sqlvalue );
                    } else if( isSimpleValue( sqlvalue )) {
                      sqlQuery = sqlQuery.setString( key, sqlvalue );
                    }
                  }
                  var objectsToOverride = sqlQuery.list();
                } else {
                  var sql = "SELECT b FROM #entityName# a JOIN a.#property.name# b WHERE a.id = :id ";
                  var params = { "id" = getID()};
                  if( structKeyExists( formData, "remove_#property.name#" )) {
                    sql &= " AND b.id IN ( :list )";
                    params[ "list" ] = listToArray( formData[ "remove_#property.name#" ]);
                    arrayAppend( valueToLog, "removed #property.name#" );
                  }
                  var objectsToOverride = ORMExecuteQuery( sql, params );
                }
              } catch( any e ) {
                throw( type = "basecfc.global",
                       message = "Error in query: " & sql,
                       detail = "Params: #serializeJSON( sqlparams )#" );
              }

              for( var objectToOverride in objectsToOverride ) {
                if( property.fieldType == "many-to-many" ) {
                  var reverseField = objectToOverride.getReverseField( reverseCFCLookup, property.inverseJoinColumn );
                  queueInstruction( objectToOverride, "remove#reverseField#", this );
                } else {
                  var reverseField = objectToOverride.getReverseField( reverseCFCLookup, property.fkcolumn, false );
                  queueInstruction( objectToOverride, "set#reverseField#", "null" );
                }

                queueInstruction( this, "remove#propertyName( property )#", objectToOverride );
              }
            }

            // SET
            if( structKeyExists( formData, "set_#property.name#" )) {
              var workData = formData[ "set_#property.name#" ];

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
                  if( !isJSON( toAdd ) && !isObject( toAdd ) && !isSimpleValue( toAdd )) {
                    toAdd = serializeJSON( toAdd );
                  }

                  arrayAppend( entitiesToAdd, toAdd );
                  structDelete( local, "toAdd" );
                }

                formData[ "add_#propertyName( property )#" ] = entitiesToAdd;
                structDelete( local, "entitiesToAdd" );
              }

              structDelete( formData, "set_#property.name#" );
              structDelete( local, "workData" );
            }

            // ADD
            if( structKeyExists( formData, "add_#propertyName( property )#" )) {
              var workData = formData[ "add_#propertyName( property )#" ];

              if( isSimpleValue( workData )) {
                if( isJSON( workData )) {
                  workData = deSerializeJSON( workData );
                } else if( isJSON( '[' & workData & ']' )) {
                  workData = deSerializeJSON( '[' & workData & ']' ); // for lucee
                } else {
                  var itemList = listToArray( workData );
                  workData = [];
                  for( var itemID in itemList ) {
                    arrayAppend( workData, { "id" = itemID });
                  }
                }
              }

              if( !isArray( workData )) {
                workData = [ workData ];
              }

              var fn = "add#propertyName( property )#";

              for( var nestedData in workData ) {
                var objectToLink = toComponent( nestedData, property );

                if( !isNull( objectToLink )) {
                  if( structKeyExists( request.basecfc.queuedInstructions, getID()) &&
                      structKeyExists( request.basecfc.queuedInstructions[ getID() ], fn ) &&
                      structKeyExists( request.basecfc.queuedInstructions[ getID() ][ fn ], objectToLink.getID())) {
                    structDelete( local, "objectToLink" );
                    continue; // already queued
                  }

                  queueInstruction( this, fn, objectToLink );

                  var fkColumn = property.fieldtype == "many-to-many" ? property.inverseJoinColumn : property.fkcolumn;
                  var reverseField = objectToLink.getReverseField( reverseCFCLookup, fkColumn );

                  if( evaluate( "has#propertyName( property )#(objectToLink)" ) &&
                      evaluate( "objectToLink.has#reverseField#(this)" )) {
                    structDelete( local, "objectToLink" );
                    continue; // already in object
                  }

                  var updateStruct = parseUpdateStruct( nestedData );

                  if( !structCount( updateStruct )) {
                    structDelete( local, "objectToLink" );
                    structDelete( local, "updateStruct" );
                    continue;
                  }

                  if( !objectToLink.isNew()) {
                    updateStruct["#property.entityName#id"] = objectToLink.getID();
                  }

                  if( property.fieldtype == "many-to-many" ) {
                    reverseField = "add_#reverseField#";
                  }

                  updateStruct[reverseField] = this;

                  if( instance.debug ) {
                    basecfcLog( text = "called: #property.entityName#.save(#depth+1#)", file = request.appName );
                  }

                  // Go down the rabbit hole:
                  var nestedData = objectToLink.save(
                    depth = depth+1,
                    formData = updateStruct
                  );

                  arrayAppend( valueToLog, nestedData );

                  structDelete( local, "objectToLink" );
                  structDelete( local, "updateStruct" );
                }
              }

              structDelete( formData, "add_#propertyName( property )#" );
              structDelete( local, "workData" );
            }

            break;

          case "one-to-one":
          //   ___                  _____            ___
          //  / _ \  _ _   ___  ___|_   _|___  ___  / _ \  _ _   ___
          // | (_) || ' \ / -_)|___| | | / _ \|___|| (_) || ' \ / -_)
          //  \___/ |_||_|\___|      |_| \___/      \___/ |_||_|\___|
          //
            throw( message="Not implemented", detail="One-to-one relations are not yet supported.", type="basecfc.save" );

          default:
          //  _____            ___
          // |_   _|___  ___  / _ \  _ _   ___
          // | | | / _ \|___|| (_) || ' \ / -_)
          //   |_| \___/      \___/ |_||_|\___|
          //
            if( structKeyExists( formData, property.name )) {
              // save value and link objects together
              var fn = "set" & property.name;
              var nestedData = formData[property.name];

              if( structKeyExists( property, "cfc" )) {
                var objectToLink = toComponent( nestedData, property );

                if( !isNull( objectToLink )) {
                  if( structKeyExists( request.basecfc.queuedInstructions, getID()) &&
                      structKeyExists( request.basecfc.queuedInstructions[getID()], fn )) {
                    structDelete( local, "objectToLink" );
                    continue; // already queued
                  }

                  queueInstruction( this, fn, objectToLink );

                  var reverseField = objectToLink.getReverseField( reverseCFCLookup, property.fkcolumn );

                  if( evaluate( "objectToLink.has#reverseField#(this)" )) {
                    structDelete( local, "objectToLink" );
                    continue; // already in object
                  }

                  var updateStruct = parseUpdateStruct( nestedData );

                  if( !structCount( updateStruct )) {
                    structDelete( local, "objectToLink" );
                    structDelete( local, "updateStruct" );
                    continue;
                  }

                  if( !objectToLink.isNew()) {
                    updateStruct["#property.entityName#id"] = objectToLink.getID();
                  }

                  updateStruct["add_#reverseField#"] = this;

                  if( instance.debug ) {
                    basecfcLog( text = "called: #property.entityName#.save(#depth+1#)", file = request.appName );
                  }

                  // Go down the rabbit hole:
                  nestedData = objectToLink.save(
                    depth = depth+1,
                    formData = updateStruct
                  );

                  valueToLog = nestedData.getName();
                  structDelete( local, "objectToLink" );
                  structDelete( local, "updateStruct" );
                } else {
                  valueToLog = "removed";
                }
              } else if( isSimpleValue( nestedData )) {
                // check inside json obj to see if an ID was passed in
                try {
                  var testForJSON = deserializeJSON( nestedData );
                  if( isStruct( testForJSON ) && structKeyExists( testForJSON, "id" )) {
                    nestedData = testForJSON.id;
                  }
                } catch ( any e ) {}

                var skipThisField = false;
                var dataType = getDatatype( property );

                if( useSanitation && arrayFindNoCase( instance.sanitizeDataTypes, dataType )) {
                  var dirtyValue = duplicate( nestedData );

                  nestedData = sanitationInstance.sanitize( nestedData, dataType );

                  var sanitationFailed = sanitationInstance.hasErrors();

                  if( sanitationFailed ) {
                    var sanitationReport = sanitationInstance.getReport();
                    var sanitationError = sanitationInstance.getError();

                    arrayAppend( sanitationReport, {
                      "type" = "sanitation",
                      "object" = instance.className,
                      "field" = property.name,
                      "value" = nestedData,
                      "datatype" = dataType,
                      "message" = sanitationError.message,
                      "detail" = sanitationError.detail
                    });

                    sanitationInstance.setReport( sanitationReport );

                    basecfcLog( text = "sanitation of '#dirtyValue#' to '#dataType#' FAILED", file = request.appName );

                    skipThisField = true; // break off trying to set this value, as it won't work anyway.
                  } else if( instance.debug ) {
                    basecfcLog( text = "value '#dirtyValue#' sanitized to '#nestedData#'", file = request.appName );
                  }
                }

                // make sure integers are saved as that:
                if( structKeyExists( property, "ORMType" )) {
                  if( property.ORMType == "int" || property.ORMType == "integer" ) {
                    nestedData = javaCast( "int", val( nestedData ));
                  } else if( property.ORMType == "float" ) {
                    nestedData = javaCast( "float", val( nestedData ));
                  }
                }

                if( !skipThisField ) {
                  queueInstruction( this, fn, nestedData );
                }

                valueToLog = left( nestedData, 255 );
              }

              // remove data if nestedData is empty
              if( isNull( nestedData )) {
                queueInstruction( this, fn, "null" );

                if( instance.debug ) {
                  writeOutput( '<p>#fn#( null )</p>' );
                }
              }

              // debug output to show which function call was queued:
              if( instance.debug && !isNull( nestedData )) {
                var dbugAttr = nestedData.toString();

                if( structKeyExists( local, "updateStruct" )) {
                  dbugAttr = serializeJSON( updateStruct );
                }

                if( isJSON( dbugAttr ) && !isBoolean( dbugAttr ) && !isNumeric( dbugAttr )) {
                  dbugAttr = '<code class="prettyprint">#replace( dbugAttr, ',', ',<br />', 'all' )#</code>';
                }

                writeOutput( '<p>#fn#( #dbugAttr# )</p>' );
              }

              // cleanup for the next loop:
              structDelete( local, "objectToLink" );
              structDelete( local, "updateStruct" );
              structDelete( local, "nestedData" );
            }
        }
      }

      if( instance.debug ) {
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

    if( instance.debug ) {
      writeOutput( '</table>' );
      writeOutput( getTickCount() - timer & "ms<br />" );
      writeOutput( '</div>' );
    }

    // Process queued instructions
    if( depth == 0 ) {
      if( structKeyExists( request.basecfc, "validationService" )) {
        processQueue( request.basecfc.validationService );
      } else {
        processQueue();
      }

      if( canBeLogged && entityName != "logentry" ) {
        var logAction = isNew() ? "created" : "changed";
        var logentry = entityNew( "logentry" );
        entitySave( logentry );
        basecfcLog( text = "Creating new log entry.", file = request.appName );
        logentry.enterIntoLog( logAction, savedState, this );
      }
    }

    return this;
  }

  // Utility functions:

  /**
    * the full cfc path
    */
  public string function getClassName() {
    var sep = server.os.name contains 'Windows' ? '\' : '/';
    var start = findNoCase( '#sep#model#sep#', instance.meta.path );
    if( start > 0 ) {
      return instance.config.root & replace( replace( mid( instance.meta.path, start, len( instance.meta.path )), '.cfc', '', 'one' ), sep, '.', 'all' );
    }
    return instance.meta.fullname;
  }

  /**
    * the entity name (as per CFML ORM standard)
    */
  public string function getEntityName( string className=instance.className ) {
    var basicEntityName = listLast( className, '.' );
    if( structKeyExists( request.allEntities, basicEntityName )) {
      return request.allEntities[ basicEntityName ].name;
    }
    return basicEntityName;
  }

  /**
    * the database table name (as per CFML ORM standard)
    */
  public string function getTableName( string className=instance.className ) {
    var basicEntityName = listLast( className, '.' );
    if( structKeyExists( request.allEntities, basicEntityName )) {
      return request.allEntities[ basicEntityName ].table;
    }
    return basicEntityName;
  }

  /**
    *
    * This method needs to be moved to a controller, since it has to do with output.
    */
  public array function getFieldsToDisplay( string type="inlineedit-line", struct formData={} ) {
    var result = [];

    switch( type ) {
      case "inlineedit-line":
        var propertiesInInline = structFindKey( instance.properties, "ininline", "all" );
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

          if( structKeyExists( formData, currentField )) {
            valueToDisplay = formData[currentField];
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

  /**
    * Overrid default getter to generate a GUID to identify this object with.
    */
  public string function getID() {
    return isNew() ? instance.id : id;
  }

  /**
    * a struct containing this objects and its ancestors properties
    */
  public struct function getInheritedProperties() {
    var cachedPropertiesKey = "#request.appName#-#instance.className#-props";
    var cachedProperties = cacheGet( cachedPropertiesKey );

    if( !isNull( cachedProperties )) {
      return cachedProperties;
    }

    var md = instance.meta;
    var result = {};

    do {
      if( structKeyExists( md, "properties" ) && isArray( md.properties )) {
        var numberOfProperties = arrayLen( md.properties );
        for( var i=1; i<=numberOfProperties; i++ ) {
          var property = md.properties[ i ];
          if( structKeyExists( property, "cfc" )) {
            result[ property.name ][ "entityName" ] = getEntityName( property.cfc );
          }
          for( var field in property ) {
            result[ property.name ][ field ] = property[ field ];
          }
        }
      }
      md = md.extends;
    } while( structKeyExists( md, "extends" ));

    cachePut( cachedPropertiesKey, result );

    return result;
  }

  /**
    * Find the corresponding field in the joined object (using the FKColumn)
    */
  public string function getReverseField( required string cfc, required string fkColumn, boolean singular=true ) {
    var propertiesWithCFC = structFindKey( instance.properties, "cfc", "all" );
    var field = 0;
    var fieldFound = 0;

    if( !arrayLen( propertiesWithCFC )) {
      var logMessage = "getReverseField() ERROR: nothing linked to #cfc#.";
      basecfcLog( text = logMessage, type = "fatal", file = request.appName );

      try {
        var expectedPropertyName = listLast( cfc, '.' );
        var expectedCode = 'property name="#expectedPropertyName#s" singularName="#expectedPropertyName#" fieldType="one-to-many" cfc="#cfc#" fkColumn="#fkcolumn#";';
        var errorDetail = "Expected something like: #expectedCode#";

        if( len( fkcolumn ) > 2 ) {
          errorDetail &= chr( 10 ) & "In template: #left( fkcolumn, len( fkcolumn ) - 2 )#.cfc";
        }
      } catch ( any e ) {
        var errorDetail = "";
      }

      throw( type="basecfc.getReverseField", message=logMessage, detail=errorDetail );
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
      basecfcLog( text = logMessage, type = "fatal", file = request.appName );
      throw( type = "basecfc.getReverseField", message = logMessage );
    }

    var result = field.name;

    if( singular && structKeyExists( field, 'singularName' )) {
      result = field['singularName'];
    }

    return result;
  }

  /**
    * true if propertyToCheck is found in this object or its ancestors
    */
  public boolean function propertyExists( required string propertyToCheck ) {
    return structKeyExists( instance.properties, propertyToCheck );
  }

  /**
    * Determines whether this is a new object (without an ID) or an existing one
    */
  public boolean function isNew() {
    return ( isNull( id ) || !isValidGUID( id ));
  }

  /**
    * a serialized JSON object (a string) representation of this object
    * using Adam Tuttle's deORM() - see below
    */
  public string function toString() {
    return serializeJSON( deORM( this ));
  }

  /**
    * a simplified representation of the object
    * By Adam Tuttle ( http://fusiongrokker.com/post/deorm ).
    * @data One or more entities to be converted to a less complex representation
    */
  public any function deORM( any data=this ) {
    var deWormed = {};

    if( isSimpleValue( data )) {
      deWormed = data;
    } else if( isObject( data )) {
      var md = getMetadata( data );

      do {
        if( structKeyExists( md, 'properties' )) {
          var numberOfProperties = arrayLen( md.properties );
          for( var i=1; i<=numberOfProperties; i++ ) {
            var prop = md.properties[i];
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
      for( var key in data ) {
        if( structKeyExists( data, key )) {
          deWormed[key] = deORM( data[key] );
        }
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

  /**
    * Safe get
    */
  public any function safeGet( prop ) {
    try {
      var result = evaluate( "get#prop#()" );

      if( isObject( result )) {
        return result.getName();
      }

      if( isArray( result )) {
        return "#arrayLen( result )# item(s)";
      }

      return result;
    } catch ( any e ) {
      return "";
    }
  }

  public struct function getInstanceVariables() {
    return instance;
  }

  // Private functions:

  /**
    * Compares two component instances wither by ID or by using Java's equals()
    */
  private boolean function compareObjects( required component objA, required component objB ) {
    var idA = objA.getID();
    var idB = objB.getID();

    if( !isNull( idA ) && !isNull( idB )) {
      return idA == idB;
    }

    if( !isNull( idA ) || !isNull( idB )) {
      return false;
    }

    var comparisonA = { obj = objA };
    var comparisonB = { obj = objB };

    return comparisonA.equals( comparisonB );
  }

  /**
    * Preps string before validating it as GUID
    */
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

  /**
    * Tests a string to be a valid GUID by using the built-in isValid method and
    * falling back on reformatting the string and rechecking
    */
  private boolean function isValidGUID( required string text ) {
    if( len( text ) < 32 ) {
      return false;
    }

    if( isValid( "guid", text )) {
      return true;
    }

    return isValid( "guid", formatAsGUID( text ));
  }

  /**
    * Parses a JSON string into a struct (or passes through the given struct)
    */
  private struct function parseUpdateStruct( required any data ) {
    var result = {};

    if( isSimpleValue( data ) && len( trim( data )) && isJSON( data )) {
      var tempValue = deserializeJSON( data );
      if( isStruct( tempValue )) {
        data = tempValue;
      }
    }

    if( isStruct( data ) && !isObject( data )) {
      result = data;
    }

    return result;
  }

  /**
    * Processes the queued instructions in one batch
    */
  private void function processQueue( validationInstance ) {
    if( instance.debug ) {
      var instructionTimers = 0;
      basecfcLog( text="~~ start processing queue for #instance.meta.name# ~~", file=request.appName );
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
          var finalInstruction = ( isSimpleValue( value ) && value == "null" ) ?
                "object." & command & "(javaCast('null',0))" :
                "object." & command & "(value)";
          var logMessage = "called: [#objectid#] #finalInstruction##isSimpleValue( value )?' (value=#value#)':''#";

          if( instance.debug ) {
            var instructionTimer = getTickCount();
          }

          try {
            evaluate( finalInstruction );
          } catch( any e ) {
            basecfcLog( text=logMessage & " FAILED", file=request.appName, type="fatal" );
            rethrow;
          }

          if( instance.debug ) {
            instructionTimer = getTickCount()-instructionTimer;
            basecfcLog( text=logMessage & " (t=#instructionTimer#)", file=request.appName );
            instructionTimers += instructionTimer;
          }
        }
      }

      if( !isNull( validationInstance )) {
        var validated = validationInstance.validate( object );

        if( validated.hasErrors()) {
          var validationReport = validationInstance.getReport();
          var errorsInValidation = validated.getErrors();

          basecfcLog( text="#object.getEntityName()# has #arrayLen( errorsInValidation )# error(s).", file=request.appName );

          for( var err in errorsInValidation ) {
            var prop = err.getProperty();
            var obj = err.getClass();
            var errorMessage = "Invalid value";
            var problemValue = object.safeGet( prop );
            if( len( trim( problemValue ))) { errorMessage &= " (#problemValue#)"; }
            errorMessage &= " for #prop# in #obj#: #err.getMessage()#";

            arrayAppend( validationReport, {
              "type" = "validation",
              "object" = obj,
              "field" = prop,
              "value" = problemValue,
              "datatype" = "",
              "message" = errorMessage,
              "detail" = ""
            });

            basecfcLog( text = errorMessage, file = request.appName );
          }

          validationInstance.setReport( validationReport );
        }
      }
    }

    if( instance.debug ) {
      basecfcLog( text = "~~ finished queue in " & instructionTimers & "ms. ~~", file = request.appName );
    }
  }

  /**
    * Method to add instructions to the queue, which is later processed using
    * processQueue() overwriting previous instructions so no duplicate actions
    * are taking place
    */
  private void function queueInstruction( required component entity, required string command, required any value ) {
    param struct request.basecfc.instructionsOrder={};
    param struct request.basecfc.queuedInstructions={};
    param struct request.basecfc.queuedObjects={};

    var entityID = entity.getID();

    request.basecfc.queuedObjects[entityID] = entity;

    if( !structKeyExists( request.basecfc.instructionsOrder, entityID )) {
      request.basecfc.instructionsOrder[entityID] = {};
    }

    if( !structKeyExists( request.basecfc.queuedInstructions, entityID )) {
      request.basecfc.queuedInstructions[entityID] = {};
    }

    if( !structKeyExists( request.basecfc.queuedInstructions[entityID], command )) {
      request.basecfc.queuedInstructions[entityID][command] = {};
    }

    if( isObject( value )) {
      var valueID = value.getID();

      if( isNull( valueID )) {
        var logMessage = "No ID set on entity #value.getName()#";
        basecfcLog( text = logMessage, type = "fatal", file = request.appName );
        throw( type = "basecfc.queueInstruction", message = logMessage );
      }

      // Adds multiple values:
      request.basecfc.queuedInstructions[entityID][command][valueID] = value;

      if( !structKeyExists( request.basecfc.instructionsOrder[entityID], command )) {
        request.basecfc.instructionsOrder[entityID][command] = [];
      }

      var existingInstructionIndex = arrayFindNoCase( request.basecfc.instructionsOrder[entityID][command], valueID);

      if( existingInstructionIndex && left( command, 3 ) != "add" ) {
        arrayDeleteAt( request.basecfc.instructionsOrder[entityID][command], existingInstructionIndex );
      }

      if( left( command, 6 ) == "remove" ) {
        arrayPrepend( request.basecfc.instructionsOrder[entityID][command], valueID);
      } else {
        arrayAppend( request.basecfc.instructionsOrder[entityID][command], valueID);
      }
    } else {
      // Adds single value:
      request.basecfc.queuedInstructions[entityID][command].value = value;
      request.basecfc.instructionsOrder[entityID][command] = ["value"];
    }
  }

  /**
    * Takes a GUID or struct containing one and an entity name to construct a
    * component (or passes along the given component)
    */
  private any function toComponent( required any variable, required struct property ) {
    try {
      var parsedVar = variable;

      if( isObject( parsedVar ) && isInstanceOf( parsedVar, property.cfc )) {
        return parsedVar;
      }

      if( isSimpleValue( parsedVar ) && len( trim( parsedVar ))) {
        if( isValidGUID( parsedVar )) {
          parsedVar = { "id" = parsedVar };
        } else if( isJSON( parsedVar )) {
          parsedVar = deserializeJSON( parsedVar );
        }
      }

      if( isStruct( parsedVar )) {
        if( structIsEmpty( parsedVar )) {
          return javaCast( "null", 0 );
        }

        var pk = "";

        if( structKeyExists( parsedVar, "#property.entityName#id" )) {
          pk = parsedVar[ "#property.entityName#id" ];
        } else if( structKeyExists( parsedVar, "id" )) {
          pk = parsedVar[ "id" ];
        }

        if( isValidGUID( pk )) {
          var objectToLink = entityLoadByPK( property.entityName, pk );
        }
      }

      if( isNull( objectToLink )) {
        if( instance.debug ) {
          basecfcLog( text = "Creating new #property.entityName#.", file = request.appName );
        }
        var objectToLink = entityNew( property.entityName );
        entitySave( objectToLink );
      }

      if( isObject( objectToLink )) {
        return objectToLink;
      }

      var logMessage = "Variable could not be translated to component of type #property.entityName#";
      basecfcLog( text = logMessage, type = "fatal", file = request.appName );
      throw( type = "basecfc.toComponent", message = logMessage );
    } catch( basecfc.toComponent e ) {
      if( instance.debug ) {
        try {
          writeDump( arguments );
          writeDump( e );
          abort;
        } catch ( any e ) {
          rethrow;
        }
      }

      rethrow;
    } catch( any e ) {
      var logMessage = "While creating object #property.entityName#, an unexpected error occured: #e.detail#";
      basecfcLog( text = logMessage, type = "fatal", file = request.appName );

      if( instance.debug ) {
        try {
          writeDump( arguments );
          writeDump( e );
          abort;
        } catch ( any e ) {
          throw( type = "basecfc.toComponent", message = logMessage );
        }
      }

      throw( type = "basecfc.toComponent", message = logMessage );
    }
  }

  /**
    * Route all logging through this method so it can be changed to some
    * external tool some day (as well as shown as debug output)
    */
  private void function basecfcLog( text, file="#request.appName#", type="information" ) {
    writeLog( text = text, file = file, type = type );

    if( instance.debug ) {
      writeOutput( "<br />" & text );
    }
  }

  /**
    * the singular property name, if that exists, otherwise it returns
    * the default name
    */
  private string function propertyName( property ) {
    return structKeyExists( property, 'singularName' ) ? property.singularName : property.name;
  }

  /**
    * the data type of a property.
    */
  private string function getDatatype( property ) {
    if( structKeyExists( property, "type" )) {
      if( structKeyExists( property, "percentage" ) &&
          isBoolean( property.percentage ) &&
          property.percentage ) {
        return "percentage";
      }
      return property.type;
    }
    if( structKeyExists( property, "ormtype" )) { return property.ormtype; }
    if( structKeyExists( property, "sqltype" )) { return property.sqltype; }
    if( structKeyExists( property, "datatype" )) { return property.datatype; }
    if( structKeyExists( property, "fieldType" )) { return property.fieldType; }

    return "string";
  }
}