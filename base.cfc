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

  this.version = "3.5.5";
  this.sanitizeDataTypes = listToArray( "date,datetime,double,float,int,integer,numeric,percentage,timestamp" );
  this.logLevels = listToArray( "debug,information,warning,error,fatal" );
  this.logFields = listToArray( "createcontact,createdate,createip,updatecontact,updatedate,updateip" );

  param request.appName="basecfc";
  param request.context.debug=false;

  /**
    * The constructor needs to be called in order to populate the instance
    * variables (like variables.instance.meta which is used by the other methods)
    */
  public component function init( ) {
    param variables.name="";
    param variables.deleted=false;
    param variables.sortorder=0;

    variables.instance = {
      "entities" = { },
      "id" = formatAsGUID( createUUID( ) ),
      "meta" = getMetaData( ),
      "sanitationReport" = [ ],
      "sessionFactory" = ORMGetSessionFactory( ),
      "validationReport" = [ ]
    };

    if ( structKeyExists( url, "reload" ) ) {
      var allCacheIds = cacheGetAllIds( );
      if ( !arrayIsEmpty( allCacheIds ) ) {
        cacheRemove( arrayToList( allCacheIds ), false );
      }
    }

    if ( !structKeyExists( request, "allEntities" ) ) {
      var cachedEntities = cacheGet( "allEntities_#request.appName#" );
      if ( isNull( cachedEntities ) ) {
        var cachedEntities = { };
        var allEntities = variables.instance.sessionFactory.getAllClassMetadata( );
        for ( var key in allEntities ) {
          var entity = allEntities[ key ];
          cachedEntities[ key ] = { "name" = entity.getEntityName( ), "table" = entity.getTableName( ) };
        }
        cachePut( "allEntities_#request.appName#", cachedEntities );
      }
      request.allEntities = cachedEntities;
    }

    if ( structKeyExists( request, "context" ) && isStruct( request.context ) ) {
      param request.context.config={};
      param request.context.config.log=false;
      param request.context.config.root="root";
      param request.context.config.disableSecurity=true;
      param request.context.config.logLevel="fatal";

      var appendRcToInstance = {
        "config" = {
          "log" = request.context.config.log,
          "root" = request.context.config.root,
          "disableSecurity" = request.context.config.disableSecurity,
          "logLevel" = request.context.config.logLevel
        }
      };

      structAppend( variables.instance, appendRcToInstance, true );
    }

    structAppend( variables.instance, arguments, true );

    param variables.instance.config.root="root";

    variables.instance[ "className" ] = getClassName( );
    variables.instance[ "entityName" ] = getEntityName( );
    variables.instance[ "properties" ] = getInheritedProperties( );
    variables.instance[ "defaultFields" ] = "log,id,fieldnames,submitbutton,#variables.instance.entityName#id";

    if ( (
        !structKeyExists( variables.instance.properties, "name" ) ||
        !structKeyExists( variables.instance.properties, "deleted" ) ||
        !structKeyExists( variables.instance.properties, "sortorder" )
      ) && variables.instance.className != "basecfc.base" ) {
      throw(
        "Missing essential properties",
        "basecfc.init",
        "Objects extending basecfc must have a name, deleted and sortorder property."
      );
    }

    return this;
  }

  /**
    * This persists objects extending this base cfc into a database using ORM
    * It goes through all passed fields and updates all linked objects recursively
    *
    * @formData The data structure containing the new data to be saved
    * @depth Used to prevent inv. loops (don't keep going infinitely)
    * @validationService provide a service that can validate objects
    * @sanitationService provide a service that tries to make sense of slightly off data
    */
  public component function save( required struct formData = { }, numeric depth = 0, component validationService, component sanitationService ) {
    var basecfctimer = getTickCount( );

    // objects using .save() must be initialised using the constructor
    if ( !structKeyExists( variables, "instance" ) ) {
      var logMessage = "Basecfc not initialised";
      basecfcLog( logMessage, "fatal" );
      throw( logMessage, "basecfc.global" );
    }

    // Hard coded depth limit
    if ( depth > 10 ) {
      var logMessage = "Infinite loop fail safe triggered";
      basecfcLog( logMessage, "fatal" );
      throw( logMessage, "basecfc.global" );
    }

    var inheritedProperties = variables.instance.properties;
    var savedState = { };

    for ( var logField in this.logFields ) {
      structDelete( formData, logField );
    }

    if ( isNull( variables.deleted ) ) {
      formData.deleted = false;
    }

    if ( depth == 0 ) {
      request.basecfc = {
        "timers" = { },
        "instructionsOrder" = { },
        "queuedInstructions" = { },
        "queuedObjects" = { "#getId( )#" = this },
        "ormSession" = ormGetSession( )
      };

      if ( canBeLogged( ) ) {
        if ( !len( trim( getCreateDate( ) ) ) ) {
          formData.createdate = now( );
        }

        if ( !len( trim( getCreateIP( ) ) ) ) {
          formData.createIP = cgi.remote_host;
        }

        formData.updateDate = now( );
        formData.updateIP = cgi.remote_host;

        if ( !variables.instance.config.disableSecurity ) {
          if ( !hasCreateContact( ) ) {
            if ( !structKeyExists( formData, "createContact" ) &&
                structKeyExists( instance, "auth" ) &&
                structKeyExists( variables.instance.auth, "userID" ) &&
                isValidGUID( variables.instance.auth.userID ) ) {
              formData.createContact = variables.instance.auth.userID;
            }
          }

          if ( !structKeyExists( formData, "updateContact" ) &&
              structKeyExists( instance, "auth" ) &&
              structKeyExists( variables.instance.auth, "userID" ) &&
                isValidGUID( variables.instance.auth.userID ) ) {
            formData.updateContact = variables.instance.auth.userID;
          }
        }
      }

      if ( structKeyExists( arguments, "validationService" ) ) {
        request.basecfc.validationService = validationService;
      }

      if ( structKeyExists( arguments, "sanitationService" ) ) {
        request.basecfc.sanitationService = sanitationService;
      }
    }

    var useValidation = structKeyExists( request.basecfc, "validationService" );
    var useSanitation = structKeyExists( request.basecfc, "sanitationService" );

    if ( request.context.debug ) {
      var debugid = formatAsGUID( createUUID( ) );
      var collapse = "document.getElementById('#debugid#').style.display=(document.getElementById('#debugid#').style.display==''?'none':'');";
      var display = ' style="display:none;"';

      if ( !structKeyExists( request, "basecfc-save" ) ) {
        request[ "basecfc-save" ] = true;
        writeOutput( '<script src="http://helper.e-line.nl/prettify/run_prettify.js"></script><style>td,th,h2{padding:3px;}table,td,th{border:1px solid ##8091A4}td,th{padding:3px;border-top:0;border-left:0;background-color:##B5BFCB}.basecfc-debug{width:900px;margin:0 auto}.basecfc-debug .call{font-family:monospace;border:2px solid ##264160; padding:5px; margin-bottom:15px}.basecfc-debug h2{background:##3D5774;cursor:pointer;color:white;margin:0}.basecfc-debug table{border-color:##8091A4;border-right:0;border-bottom:0}.result{color:red}</style>' );
      }

      if ( depth == 0 ) {
        basecfcLog( "~~~ start basecfc.save() ~~~" );
        writeOutput( '<div class="basecfc-debug">' );
        display = '';
      }

      writeOutput( '<div class="call"><h2 onclick="#collapse#">#depth#:#variables.instance.entityName#:#getID( )#</h2><table cellpadding="0" cellspacing="0" border="0" width="100%" id="#debugid#"#display#><tr><th colspan="2">Name: "#getName( )#"</th></tr><tr><td colspan="2">Prep time: #getTickCount( ) - basecfctimer#ms</td></tr>' );
    }

    // This object can handle non-existing fields, so lets add those to the properties struct.
    if ( arrayLen( structFindValue( variables.instance.meta, "onMissingMethod" ) ) ) {
      var formDataKeys = structKeyArray( formData );
      for ( var key in formDataKeys ) {
        if ( !structKeyExists( inheritedProperties, key ) && !listFindNoCase( variables.instance.defaultFields, key ) ) {
          inheritedProperties[ key ] = { "name" = key, "jsonData" = true };
        }
      }
    }

    var sortedPropertyKeys = structKeyArray( inheritedProperties );

    arraySort( sortedPropertyKeys, "text" );

    // SAVE VALUES PASSED VIA FORM
    for ( var key in sortedPropertyKeys ) {
      var propTimer = getTickCount( );
      var property = inheritedProperties[ key ];

      savecontent variable="local.debugoutput" {
        if ( !skipProperty( property, formData ) ) {
          var valueToLog = "";

          if ( structKeyExists( property, "cfc" ) ) {
            var reverseCFCLookup = arrayFindNoCase( this.logFields, key ) ? "#variables.instance.config.root#.model.logged" : variables.instance.className;
          }

          param string property.fieldtype="string";
          param string property.dataType="";

          switch ( property.fieldtype ) {
            case "one-to-many":
            case "many-to-many":
            //  _____           __  __
            // |_   _|___  ___ |  \/  | __ _  _ _  _  _
            // | | | / _ \|___|| |\/| |/ _` || ' \| || |
            //   |_| \___/     |_|  |_|\__,_||_||_|\_, |
            //                                     |__/
              valueToLog = [ ];

              // Alias for set_ which overwrites linked data with new data
              if ( structKeyExists( formData, property.name ) ) {
                formData[ "set_#property.name#" ] = formData[ property.name ];
              }

              // REMOVE
              if ( structKeyExists( formData, "set_#property.name#" ) || structKeyExists( formData, "remove_#property.name#" ) ) {
                var tableName = getTableName( );
                var otherTable = getTableName( property.cfc );
                var sqlparams = { "id" = getID( ) };

                try {
                  if ( structKeyExists( server, "lucee" ) ) {
                    // temporary solution for Lucee 5 bug I get with HQL queries:
                    var sql = " SELECT b. * FROM #tableName# a ";
                    if ( property.fieldType == "one-to-many" ) {
                      sql &= "INNER JOIN #otherTable# b ON a.id = b.#property.fkcolumn# ";
                    } else if ( property.fieldType == "many-to-many" ) {
                      sql &= " INNER JOIN #property.linkTable# c ON a.id = c.#property.fkcolumn# INNER JOIN #otherTable# b ON c.#property.inversejoincolumn# = b.id ";
                    }
                    sql &= " WHERE a.id = :id ";
                    if ( structKeyExists( formData, "remove_#property.name#" ) ) {
                      sql &= " AND b.id IN ( :list )";
                      sqlparams[ "list" ] = listToArray( formData[ "remove_#property.name#" ] );
                      arrayAppend( valueToLog, "removed #property.name#" );
                    }
                    var sqlQuery = request.basecfc.ormSession.createSQLQuery( sql ).addEntity( property.entityName );
                    for ( var key in sqlparams ) {
                      var sqlvalue = sqlparams[ key ];
                      if ( isArray( sqlvalue ) ) {
                        sqlQuery = sqlQuery.setParameterList( key, sqlvalue );
                      } else if ( isSimpleValue( sqlvalue ) ) {
                        sqlQuery = sqlQuery.setString( key, sqlvalue );
                      }
                    }
                    var objectsToOverride = sqlQuery.list( );
                  } else {
                    var sql = "SELECT b FROM #variables.instance.entityName# a JOIN a.#property.name# b WHERE a.id = :id ";
                    var params = { "id" = getID( ) };
                    if ( structKeyExists( formData, "remove_#property.name#" ) ) {
                      var entitiesToRemove = formData[ "remove_#property.name#" ];

                      if ( !isArray( entitiesToRemove ) ) {
                        entitiesToRemove = [ entitiesToRemove ];
                      }

                      var entitiesToRemoveAsIds = [ ];

                      for ( var entityToRemove in entitiesToRemove ) {
                        var asEntityId = entityToRemove;

                        if ( isObject( entityToRemove ) && structKeyExists( entityToRemove, "getId" ) ) {
                          asEntityId = entityToRemove.getId( );
                        }

                        if ( isValidGUID( asEntityId ) ) {
                          arrayAppend( entitiesToRemoveAsIds, asEntityId );
                        }
                      }

                      params[ "list" ] = entitiesToRemoveAsIds;

                      arrayAppend( valueToLog, "removed #property.name#" );

                      sql &= " AND b.id IN ( :list )";
                    }
                    var objectsToOverride = ORMExecuteQuery( sql, params );
                  }
                } catch ( any e ) {
                  throw(
                    "Error in query",
                    "basecfc.global",
                    "#e.message# #e.detail# - SQL: #sql#, Params: #serializeJSON( sqlparams )#"
                  );
                }

                for ( var objectToOverride in objectsToOverride ) {
                  if ( property.fieldType == "many-to-many" ) {
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
              if ( structKeyExists( formData, "set_#property.name#" ) ) {
                var workData = formData[ "set_#property.name#" ];

                if ( isSimpleValue( workData ) ) {
                  if ( isJSON( workData ) ) {
                    workData = deserializeJSON( workData );
                  } else if ( isJSON( '[' & workData & ']' ) ) {
                    workData = deSerializeJSON( '[' & workData & ']' ); // for lucee
                  } else {
                    workData = listToArray( workData );
                  }
                }

                if ( !isArray( workData ) ) {
                  workData = [ workData ];
                }

                if ( arrayLen( workData ) ) {
                  var entitiesToAdd = [ ];

                  for ( var toAdd in workData ) {
                    if ( !isJSON( toAdd ) && !isObject( toAdd ) && !isSimpleValue( toAdd ) && !isStruct( toAdd ) ) {
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
              if ( structKeyExists( formData, "add_#propertyName( property )#" ) ) {
                var workData = formData[ "add_#propertyName( property )#" ];

                if ( isSimpleValue( workData ) ) {
                  if ( isJSON( workData ) ) {
                    workData = deSerializeJSON( workData );
                  } else if ( isJSON( '[' & workData & ']' ) ) {
                    workData = deSerializeJSON( '[' & workData & ']' ); // for lucee
                  } else {
                    var itemList = listToArray( workData );
                    workData = [ ];
                    for ( var itemID in itemList ) {
                      arrayAppend( workData, { "id" = itemID } );
                    }
                  }
                }

                if ( !isArray( workData ) ) {
                  workData = [ workData ];
                }

                var fn = "add#propertyName( property )#";

                for ( var nestedData in workData ) {
                  var propertyEntityName = property.entityName;

                  if ( isStruct( nestedData ) && structKeyExists( nestedData, "__subclass" ) ) {
                    propertyEntityName = nestedData[ "__subclass" ];
                  }

                  var objectToLink = toComponent( nestedData, propertyEntityName, property.cfc );

                  if ( !isNull( objectToLink ) ) {
                    if ( structKeyExists( request.basecfc.queuedInstructions, getID( ) ) &&
                        structKeyExists( request.basecfc.queuedInstructions[ getID( ) ], fn ) &&
                        structKeyExists( request.basecfc.queuedInstructions[ getID( ) ][ fn ], objectToLink.getID( ) ) ) {
                      continue; // already queued
                    }

                    queueInstruction( this, fn, objectToLink );

                    var fkColumn = property.fieldtype == "many-to-many" ? property.inverseJoinColumn : property.fkcolumn;
                    var reverseField = objectToLink.getReverseField( reverseCFCLookup, fkColumn );

                    if ( evaluate( "has#propertyName( property )#(objectToLink)" ) &&
                        evaluate( "objectToLink.has#reverseField#(this)" ) ) {
                      continue; // already in object
                    }

                    var updateStruct = parseUpdateStruct( nestedData );

                    if ( !structCount( updateStruct ) ) {
                      continue;
                    }

                    if ( !objectToLink.isNew( ) ) {
                      updateStruct[ "#propertyEntityName#id" ] = objectToLink.getID( );
                    }

                    if ( property.fieldtype == "many-to-many" ) {
                      reverseField = "add_#reverseField#";
                    }

                    updateStruct[ reverseField ] = this;

                    if ( request.context.debug ) {
                      basecfcLog( "called: #propertyEntityName#.save(#depth + 1#)" );
                    }

                    // Go down the rabbit hole:
                    var nestedData = objectToLink.save( depth = depth + 1, formData = updateStruct );

                    arrayAppend( valueToLog, nestedData );
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
              throw( "Not implemented", "basecfc.save", "One-to-one relations are not yet supported." );

            default :
            //  _____            ___
            // |_   _|___  ___  / _ \  _ _   ___
            // | | | / _ \|___|| (_) || ' \ / -_)
            //   |_| \___/      \___/ |_||_|\___|
            //
              if ( structKeyExists( formData, property.name ) ) {
                // save value and link objects together
                var fn = "set" & property.name;
                var nestedData = formData[ property.name ];
                var skipToNextPropery = false;

                if ( structKeyExists( property, "cfc" ) ) {
                  var propertyEntityName = property.entityName;

                  if ( isStruct( nestedData ) && structKeyExists( nestedData, "__subclass" ) ) {
                    propertyEntityName = nestedData[ "__subclass" ];
                  }

                  var objectToLink = toComponent( nestedData, propertyEntityName, property.cfc );

                  if ( !isNull( objectToLink ) ) {
                    if ( structKeyExists( request.basecfc.queuedInstructions, getID( ) ) &&
                         structKeyExists( request.basecfc.queuedInstructions[ getID( ) ], fn ) ) {
                      skipToNextPropery = true;
                    }

                    if ( !skipToNextPropery ) {
                      queueInstruction( this, fn, objectToLink );

                      var reverseField = objectToLink.getReverseField( reverseCFCLookup, property.fkcolumn );

                      if ( !skipToNextPropery ) {
                        var updateStruct = parseUpdateStruct( nestedData );

                        if ( !structCount( updateStruct ) ) {
                          skipToNextPropery = true;
                        }

                        if ( !skipToNextPropery ) {
                          if ( !objectToLink.isNew( ) ) {
                            updateStruct[ "#propertyEntityName#id" ] = objectToLink.getID( );
                          }

                          updateStruct[ "add_#reverseField#" ] = this;

                          if ( request.context.debug ) {
                            basecfcLog( "called: #propertyEntityName#.save(#depth + 1#)" );
                          }

                          // Go down the rabbit hole:
                          nestedData = objectToLink.save( depth = depth + 1, formData = updateStruct );

                          valueToLog = nestedData.getName( );
                        } else if ( request.context.debug ) {
                          writeOutput( "nothing to update" );
                        }
                      } else if ( request.context.debug ) {
                        writeOutput( "already in object" );
                      }
                    } else if ( request.context.debug ) {
                      writeOutput( "already queued" );
                    }
                  } else {
                    valueToLog = "removed";
                  }
                } else {
                  if ( property.dataType == "json" && !isSimpleValue( nestedData ) ) {
                    nestedData = serializeJSON( nestedData );
                  }

                  if ( isSimpleValue( nestedData ) ) {
                    var dataType = getDatatype( property );

                    // check inside json obj to see if an ID was passed in
                    try {
                      var testForJSON = deserializeJSON( nestedData );
                      if ( isStruct( testForJSON ) && structKeyExists( testForJSON, "id" ) ) {
                        nestedData = testForJSON.id;
                      }
                    } catch ( any e ) {
                    }

                    if ( useSanitation && arrayFindNoCase( this.sanitizeDataTypes, dataType ) ) {
                      var dirtyValue = duplicate( nestedData );
                      var sanitationResult = request.basecfc.sanitationService.sanitize( nestedData, dataType );

                      nestedData = sanitationResult.value;

                      var sanitationFailed = structKeyExists( sanitationResult, "error" );

                      if ( sanitationFailed ) {
                        var sanitationError = sanitationResult.error;

                        arrayAppend( variables.instance.sanitationReport, {
                          "type" = "sanitation",
                          "object" = variables.instance.className,
                          "field" = property.name,
                          "value" = nestedData,
                          "datatype" = dataType,
                          "message" = sanitationError.message,
                          "detail" = sanitationError.detail,
                          "errortype" = sanitationError.type
                        } );

                        basecfcLog( "sanitation of '#dirtyValue#' to '#dataType#' FAILED", "error" );

                        skipToNextPropery = true; // break off trying to set this value, as it won't work anyway.
                      } else if ( request.context.debug ) {
                        basecfcLog( "value '#dirtyValue#' sanitized to '#nestedData#'" );
                      }
                    }

                    if ( !skipToNextPropery ) {
                      // fix data types:
                      if ( listFindNoCase( "int,integer", dataType ) ) {
                        nestedData = javaCast( "int", val( nestedData ) );
                      } else if ( dataType == "float" ) {
                        nestedData = javaCast( "float", val( nestedData ) );
                      } else if ( listFindNoCase( "timestamp,date,datetime", dataType ) ) {
                        if ( isDate( nestedData ) ) {
                          nestedData = createODBCDateTime( nestedData );
                        } else {
                          throw( "Invalid date/time", "basecfc.save", nestedData );
                        }
                      }

                      queueInstruction( this, fn, nestedData );

                      valueToLog = left( nestedData, 255 );
                    }
                  }
                }

                if ( !skipToNextPropery ) {
                  // remove data if nestedData is empty
                  if ( isNull( nestedData ) ) {
                    queueInstruction( this, fn, "null" );

                    if ( request.context.debug ) {
                      writeOutput( '<p>#fn#( null )</p>' );
                    }
                  }

                  // debug output to show which function call was queued:
                  if ( request.context.debug && !isNull( nestedData ) ) {
                    var dbugAttr = nestedData.toString( );

                    if ( structKeyExists( local, "updateStruct" ) ) {
                      dbugAttr = serializeJSON( updateStruct );
                    }

                    if ( isJSON( dbugAttr ) && !isBoolean( dbugAttr ) && !isNumeric( dbugAttr ) ) {
                      dbugAttr = '<code class="prettyprint">#replace( dbugAttr, ',', ',<br />', 'all' )#</code>';
                    }

                    writeOutput( '<p>#fn#( #dbugAttr# )</p>' );
                  }
                }
              }
          }

          if ( structKeyExists( local, "valueToLog" ) ) {
            if ( !arrayFindNoCase( this.logFields, property.name ) ) {
              savedState[ property.name ] = valueToLog;
            }
            structDelete( local, "valueToLog" );
          }
        } else {
          writeOutput( "Skipped #property.name#" );
        }
      }

      if ( request.context.debug && len( trim( debugoutput ) ) ) {
        var colID = formatAsGUID( createUuid( ) );
        var collapseCol = "document.getElementById('#colID#').style.display=(document.getElementById('#colID#').style.display==''?'none':'');";
        writeOutput( '<tr><th width="15%" valign="top" align="right" onclick="#collapseCol#">#key#</th><td width="85%" id="#colID#">#len( trim( debugoutput ) ) ? debugoutput : 'no action'#<br/>#getTickCount( ) - propTimer#ms</td></tr>' );
      }

      if ( structKeyExists( local, "updateStruct" ) ) {
        structDelete( local, "updateStruct" );
      }
    }

    if ( request.context.debug ) {
      writeOutput( '</table>' );
      writeOutput( getTickCount( ) - basecfctimer & "ms<br />" );
      writeOutput( '</div>' );
    }

    // Process queued instructions
    if ( depth == 0 ) {
      processQueue( );
      logChanges( savedState );
    }

    return this;
  }

  public void function delete( ) {
    variables.deleted = true;
    basecfcLog( "Marked #variables.instance.entityName# as deleted" );
    logChanges( { "deleted" = true } );
  }

  public void function restore( ) {
    variables.deleted = false;
    basecfcLog( "Unmarked #variables.instance.entityName# as deleted" );
    logChanges( { "deleted" = false } );
  }

  // Utility functions:

  /**
    * the full cfc path
    */
  public string function getClassName( string filePath = variables.instance.meta.path ) {
    var result = variables.instance.meta.fullname;
    var sep = server.os.name contains "Windows" ? "\" : "/";
    var start = findNoCase( "#sep#model#sep#", filePath );

    if ( start > 0 ) {
      result = variables.instance.config.root & replace(
        replace( mid( filePath, start, len( filePath ) ), ".cfc", "", "one" ),
        sep,
        ".",
        "all"
      );
    }

    return result;
  }

  /**
    * the entity name (as per CFML ORM standard)
    */
  public string function getEntityName( string className = variables.instance.className ) {
    var basicEntityName = listLast( className, '.' );
    if ( structKeyExists( request.allEntities, basicEntityName ) ) {
      return request.allEntities[ basicEntityName ].name;
    }
    return basicEntityName;
  }

  /**
    * the database table name (as per CFML ORM standard)
    */
  public string function getTableName( string className = variables.instance.className ) {
    var basicEntityName = listLast( className, "." );
    if ( structKeyExists( request.allEntities, basicEntityName ) ) {
      return request.allEntities[ basicEntityName ].table;
    }
    return basicEntityName;
  }

  /**
    *
    * This method needs to be moved to a controller, since it has to do with output.
    */
  public array function getFieldsToDisplay( string type = "inlineedit-line", struct formData = { } ) {
    var result = [ ];

    switch ( type ) {
      case "inlineedit-line":
        var propertiesInInline = structFindKey( variables.instance.properties, "ininline", "all" );
        var tempProperties = { };

        for ( var property in propertiesInInline ) {
          tempProperties[ property.owner.name ] = property.owner;

          if ( !structKeyExists( tempProperties[ property.owner.name ], "orderininline" ) ) {
            tempProperties[ property.owner.name ].orderininline = 9001;
          }
        }

        var sortKey = structSort( tempProperties, 'numeric', 'asc', 'orderininline' );

        for ( var key in sortKey ) {
          var currentField = tempProperties[ key ].name;

          if ( structKeyExists( variables, currentField ) ) {
            if ( isObject( variables[ currentField ] ) ) {
              arrayAppend( result, variables[ currentField ].getName( ) );
              continue;
            } else if ( isSimpleValue( variables[ currentField ] ) && len( variables[ currentField ] ) ) {
              arrayAppend( result, variables[ currentField ] );
              continue;
            }
          }

          if ( structKeyExists( formData, currentField ) ) {
            arrayAppend( result, formData[ currentField ] );
            continue;
          }
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
  public string function getID( ) {
    return isNew( ) ? variables.instance.id : variables.id;
  }

  /**
    * a struct containing this objects and its ancestors properties
    */
  public struct function getInheritedProperties( ) {
    var cachedPropertiesKey = "props-#request.appName#_#variables.instance.className#";
    var cachedProperties = cacheGet( cachedPropertiesKey );

    if ( !isNull( cachedProperties ) ) {
      return cachedProperties;
    }

    var md = variables.instance.meta;
    var result = { };

    do {
      if ( structKeyExists( md, "properties" ) && isArray( md.properties ) ) {
        var numberOfProperties = arrayLen( md.properties );

        for ( var i = 1; i <= numberOfProperties; i++ ) {
          var property = md.properties[ i ];

          if ( !structKeyExists( result, property.name ) ) {
            result[ property.name ] = { };
          }

          if ( structKeyExists( property, "cfc" ) ) {
            property.entityName = getEntityName( property.cfc );
            property.tableName = getTableName( property.cfc );
          }

          structAppend( result[ property.name ], property, false );
        }
      }
      md = md.extends;
    } while ( structKeyExists( md, "extends" ) );

    cachePut( cachedPropertiesKey, result );

    return result;
  }

  /**
    * Find the corresponding field in the joined object (using the FKColumn)
    */
  public string function getReverseField( required string cfc, required string fkColumn, boolean singular = true ) {
    var propertiesWithCFC = structFindKey( variables.instance.properties, "cfc", "all" );
    var field = 0;
    var fieldFound = 0;

    if ( arrayIsEmpty( propertiesWithCFC ) ) {
      var logMessage = "getReverseField() ERROR: nothing linked to #cfc#.";
      basecfcLog( logMessage, "fatal" );

      try {
        var expectedPropertyName = listLast( cfc, '.' );
        var expectedCode = 'property name="#expectedPropertyName#s" singularName="#expectedPropertyName#" fieldType="one-to-many" cfc="#cfc#" fkColumn="#fkColumn#";';
        var errorDetail = "Expected something like: #expectedCode#";

        if ( len( fkColumn ) > 2 ) {
          errorDetail &= chr( 10 ) & "In template: #left( fkColumn, len( fkColumn ) - 2 )#.cfc";
        }
      } catch ( any e ) {
        basecfcLog( e.message, "fatal" );
        var errorDetail = "";
      }

      throw( logMessage, "basecfc.getReverseField", errorDetail );
    }

    for ( var property in propertiesWithCFC ) {
      field = property.owner;

      if ( structKeyExists( field, "fkColumn" ) && field.fkColumn != fkColumn ) {
        continue;
      }

      if ( !( ( structKeyExists( field, "fkColumn" ) && field.fkColumn == fkColumn ) || field.cfc == cfc ) ) {
        continue;
      }

      if ( field.cfc == cfc && field.fkColumn == fkColumn ) {
        fieldFound = 1;
        break;
      }

      var testObj = createObject( cfc ).init( );

      if ( isInstanceOf( testObj, field.cfc ) ) {
        fieldFound = 2;
        break;
      }

      if ( testObj.getClassName( ) == field.cfc ) {
        fieldFound = 3;
        break;
      }
    }

    var propertyWithFK = structFindValue( { a = propertiesWithCFC }, fkColumn, 'all' );

    if ( arrayLen( propertyWithFK ) == 1 ) {
      field = propertyWithFK[ 1 ].owner;
      fieldFound = 4;
    }

    if ( fieldFound == 0 ) {
      var logMessage = "getReverseField() ERROR: no reverse field found for fk #fkColumn# in cfc #cfc#.";
      basecfcLog( logMessage, "fatal" );
      throw( logMessage, "basecfc.getReverseField" );
    }

    var result = field.name;

    if ( singular && structKeyExists( field, 'singularName' ) ) {
      result = field[ 'singularName' ];
    }

    return result;
  }

  /**
    * true if propertyToCheck is found in this object or its ancestors
    */
  public boolean function propertyExists( required string propertyToCheck ) {
    return structKeyExists( variables.instance.properties, propertyToCheck );
  }

  /**
    * Determines whether this is a new object (without an ID) or an existing one
    */
  public boolean function isNew( ) {
    return ( isNull( variables.id ) || !isValidGUID( variables.id ) );
  }

  /**
    * a serialized JSON object (a string) representation of this object
    * using Adam Tuttle's deORM() - see below
    */
  public string function toString( ) {
    return serializeJSON( deORM( this ) );
  }

  /**
    * a simplified representation of the object
    * By Adam Tuttle ( http://fusiongrokker.com/post/deorm ).
    * @data One or more entities to be converted to a less complex representation
    */
  public any function deORM( any data = this ) {
    var deWormed = { };

    if ( isSimpleValue( data ) ) {
      deWormed = data;
    } else if ( isObject( data ) ) {
      var properties = data.getInheritedProperties( );
      for ( var key in properties ) {
        var prop = properties[ key ];
        if ( !structKeyExists( data, 'get' & prop.name ) || ( structKeyExists( prop, 'fieldtype' ) && findNoCase(
          "-to-",
          prop.fieldtype
        ) ) ) {
          continue;
        }
        deWormed[ prop.name ] = evaluate( "data.get#prop.name#()" );
      }
    } else if ( isStruct( data ) ) {
      for ( var key in data ) {
        if ( structKeyExists( data, key ) ) {
          deWormed[ key ] = deORM( data[ key ] );
        }
      }
    } else if ( isArray( data ) ) {
      var deWormed = [ ];

      for ( var el in data ) {
        arrayAppend( deWormed, deORM( el ) );
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

      if ( isObject( result ) ) {
        return result.getName( );
      }

      if ( isArray( result ) ) {
        return "#arrayLen( result )# item(s)";
      }

      return result;
    } catch ( any e ) {
      return "";
    }
  }

  public struct function getInstanceVariables( ) {
    var result = duplicate( variables.instance );
    structDelete( result, "meta" );
    structDelete( result, "sessionFactory" );

    return result;
  }

  public array function getSubClasses( ) {
    var classMetaData = variables.instance.sessionFactory.getClassMetadata( variables.instance.entityName );

    if ( classMetaData.hasSubclasses( ) ) {
      return classMetaData.getSubclassClosure( );
    }

    return [ ];
  }

  public void function enableDebug( ) {
    request.context.debug = true;
  }

  public array function getValidationReport( ) {
    return variables.instance.validationReport;
  }

  public array function getSanitationReport( ) {
    return variables.instance.sanitationReport;
  }

  // Private functions:

  /**
    * Compares two component instances by ID or by using Java's equals()
    */
  private boolean function compareObjects( required component objA, required component objB ) {
    var idA = objA.getID( );
    var idB = objB.getID( );

    if ( !isNull( idA ) && !isNull( idB ) ) {
      return idA == idB;
    }

    if ( !isNull( idA ) || !isNull( idB ) ) {
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

    if ( len( massagedText ) < 32 ) {
      return text; // return original (not my problem)
    }

    massagedText = insert( '-', massagedText, 20 );
    massagedText = insert( '-', massagedText, 16 );
    massagedText = insert( '-', massagedText, 12 );
    massagedText = insert( '-', massagedText, 8 );

    return trim( uCase( massagedText ) );
  }

  /**
    * Tests a string to be a valid GUID by using the built-in isValid method and
    * falling back on reformatting the string and rechecking
    */
  private boolean function isValidGUID( required any potentialGuid ) {
    if ( !isSimpleValue( potentialGuid ) ) {
      return false;
    }

    if ( len( potentialGuid ) < 32 ) {
      return false;
    }

    if ( isValid( "guid", potentialGuid ) ) {
      return true;
    }

    return isValid( "guid", formatAsGUID( potentialGuid ) );
  }

  /**
    * Parses a JSON string into a struct (or passes through the given struct)
    */
  private struct function parseUpdateStruct( required any data ) {
    var result = { };

    if ( isSimpleValue( data ) && len( trim( data ) ) && isJSON( data ) ) {
      var tempValue = deserializeJSON( data );
      if ( isStruct( tempValue ) ) {
        data = tempValue;
      }
    }

    if ( isStruct( data ) && !isObject( data ) ) {
      result = data;
    }

    return result;
  }

  /**
    * Processes the queued instructions in one batch
    */
  private void function processQueue( ) {
    if ( request.context.debug ) {
      var instructionTimers = 0;
      basecfcLog( "~~ start processing queue for #variables.instance.meta.name# ~~" );
    }

    var instructionsQueue = request.basecfc.queuedInstructions;

    // per object
    for ( var objectid in instructionsQueue ) {
      var instructionOrder = request.basecfc.instructionsOrder[ objectid ];
      var object = request.basecfc.queuedObjects[ objectid ];
      var objectInstructions = instructionsQueue[ objectid ];
      var sortedCommands = sortCommands( structKeyArray( instructionOrder ) );

      // per command
      for ( var command in sortedCommands ) {
        var values = instructionOrder[ command ];

        // per value
        for ( var valueKey in values ) {
          var value = objectInstructions[ command ][ valueKey ];
          var finalInstruction = "object." & command & "(" & ( isSimpleValue( value ) && value == "null" ? "javaCast('null',0)" : "value" ) & ")";
          var logValue = isSimpleValue( value ) ? value : ( isObject( value ) ? value.getName( ) : '' );
          var logMessage = "called: [#objectid#] #object.getEntityName( )#.#command#";

          if ( !isNull( logValue ) ) {
            logMessage &= "(#logValue#)";
          }

          if ( request.context.debug ) {
            var instructionTimer = getTickCount( );
          }

          try {
            evaluate( finalInstruction );
          } catch ( any e ) {
            basecfcLog( logMessage & " FAILED", "fatal" );
            rethrow;
          }

          if ( request.context.debug ) {
            instructionTimer = getTickCount( ) - instructionTimer;
            basecfcLog( logMessage & " (t=#instructionTimer#)" );
            instructionTimers += instructionTimer;
          }
        }
      }

      if ( structKeyExists( request.basecfc, "validationService" ) ) {
        try {
          var validated = request.basecfc.validationService.validate( object );
        } catch ( any e ) {
          throw(
            "An unexpected error occured in the validationService",
            "basecfc.processQueue.validationServiceError",
            e.message & ", " & e.detail,
            500,
            e.StackTrace
          );
        }

        if ( validated.hasErrors( ) ) {
          var errorsInValidation = validated.getErrors( );

          basecfcLog( "#object.getEntityName( )# has #arrayLen( errorsInValidation )# error(s)." );

          for ( var err in errorsInValidation ) {
            var prop = err.getProperty( );
            var obj = err.getClass( );
            var errorMessage = "Invalid value";
            var problemValue = object.safeGet( prop );
            if ( len( trim( problemValue ) ) ) {
              errorMessage &= " (#problemValue#)";
            }
            errorMessage &= " for #prop# in #obj#: #err.getMessage( )#";

            arrayAppend( variables.instance.validationReport, {
              "type" = "validation",
              "object" = obj,
              "field" = prop,
              "value" = problemValue,
              "datatype" = "",
              "message" = errorMessage,
              "detail" = "",
              "errortype" = "validationServiceError.#err.getProperty( )#"
            } );

            basecfcLog( errorMessage );
          }
        }
      }
    }

    for ( var objectid in instructionsQueue ) {
      var object = request.basecfc.queuedObjects[ objectId ];
      basecfcLog( "Saving #object.getEntityName( )# - #object.getName( )# - #object.getId( )#" );
      entitySave( object );
    }

    if ( request.context.debug ) {
      basecfcLog( "~~ finished queue in " & instructionTimers & "ms. ~~" );
    }
  }

  private array function sortCommands( required array commands ) {
    var remCommands = [ ];
    var setCommands = [ ];
    var addCommands = [ ];

    for ( var command in commands ) {
      var keyword = left( command, 3 );
      var commandArray = keyword & "Commands";
      arrayAppend( local[ commandArray ], command );
    }

    arraySort( remCommands, "textnocase" );
    arraySort( setCommands, "textnocase" );
    arraySort( addCommands, "textnocase" );

    var result = [ ];

    result.addAll( remCommands );
    result.addAll( setCommands );
    result.addAll( addCommands );

    return result;
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

    var entityID = entity.getID( );

    if ( !structKeyExists( request.basecfc.queuedObjects, entityID ) ) {
      request.basecfc.queuedObjects[ entityID ] = entity;
    }

    if ( !structKeyExists( request.basecfc.instructionsOrder, entityID ) ) {
      request.basecfc.instructionsOrder[ entityID ] = { };
    }

    if ( !structKeyExists( request.basecfc.queuedInstructions, entityID ) ) {
      request.basecfc.queuedInstructions[ entityID ] = { };
    }

    if ( !structKeyExists( request.basecfc.queuedInstructions[ entityID ], command ) ) {
      request.basecfc.queuedInstructions[ entityID ][ command ] = { };
    }

    if ( isObject( value ) ) {
      var valueID = value.getID( );

      if ( isNull( valueID ) ) {
        var logMessage = "No ID set on entity #value.getName( )#";
        basecfcLog( logMessage, "fatal" );
        throw( logMessage, "basecfc.queueInstruction" );
      }

      // Adds multiple values:
      request.basecfc.queuedInstructions[ entityID ][ command ][ valueID ] = value;

      if ( !structKeyExists( request.basecfc.instructionsOrder[ entityID ], command ) ) {
        request.basecfc.instructionsOrder[ entityID ][ command ] = [ ];
      }

      var existingInstructionIndex = arrayFindNoCase( request.basecfc.instructionsOrder[ entityID ][ command ], valueID );

      if ( existingInstructionIndex && left( command, 3 ) != "add" ) {
        arrayDeleteAt( request.basecfc.instructionsOrder[ entityID ][ command ], existingInstructionIndex );
      }

      if ( left( command, 6 ) == "remove" ) {
        arrayPrepend( request.basecfc.instructionsOrder[ entityID ][ command ], valueID );
      } else {
        arrayAppend( request.basecfc.instructionsOrder[ entityID ][ command ], valueID );
      }
    } else {
      // Adds single value:
      request.basecfc.queuedInstructions[ entityID ][ command ].value = value;
      request.basecfc.instructionsOrder[ entityID ][ command ] = [ "value" ];
    }
  }

  /**
    * Takes a GUID or struct containing one and an entity name to construct a
    * component (or passes along the given component)
    */
  private any function toComponent( required any variable, required string entityName, required string cfc ) {
    try {
      var parsedVar = variable;

      if ( isObject( parsedVar ) && isInstanceOf( parsedVar, cfc ) ) {
        return parsedVar;
      }

      if ( isSimpleValue( parsedVar ) && len( trim( parsedVar ) ) ) {
        if ( isJSON( parsedVar ) ) {
          parsedVar = deserializeJSON( parsedVar );
        } else if ( isValidGUID( parsedVar ) ) {
          parsedVar = { "id" = parsedVar };
        } else {
          parsedVar = { "name" = parsedVar };
        }
      }

      if ( isStruct( parsedVar ) ) {
        if ( structIsEmpty( parsedVar ) ) {
          return;
        }

        var pk = "";

        if ( structKeyExists( parsedVar, "#entityName#id" ) ) {
          pk = parsedVar[ "#entityName#id" ];
        } else if ( structKeyExists( parsedVar, "id" ) ) {
          pk = parsedVar[ "id" ];
        }

        if ( isValidGUID( pk ) ) {
          var objectToLink = entityLoadByPK( entityName, pk );
        }
      }

      if ( isNull( objectToLink ) ) {
        if ( request.context.debug ) {
          basecfcLog( "Creating new #entityName#." );
        }
        var objectToLink = entityNew( entityName );
        entitySave( objectToLink );
        var objectId = objectToLink.getId( );
        if ( !structKeyExists( request.basecfc.queuedObjects, objectId ) ) {
          request.basecfc.queuedObjects[ objectId ] = objectToLink;
        }
      }

      if ( isObject( objectToLink ) && isInstanceOf( objectToLink, "basecfc.base" ) ) {
        return objectToLink;
      }

      var logMessage = "Variable could not be translated to component of type #entityName#";
      basecfcLog( logMessage, "fatal" );
      throw( logMessage, "basecfc.toComponent" );
    } catch ( basecfc.toComponent e ) {
      if ( request.context.debug ) {
        try {
          writeDump( arguments );
          writeDump( e );
          abort;
        } catch ( any e ) {
          rethrow;
        }
      }

      rethrow;
    } catch ( any e ) {
      var logMessage = "While creating object #entityName#, an unexpected error occured: #e.message# (#e.detail#)";
      basecfcLog( logMessage, "fatal" );

      if ( request.context.debug ) {
        try {
          writeDump( arguments );
          writeDump( e );
          abort;
        } catch ( any e ) {
          throw( logMessage, "basecfc.toComponent" );
        }
      }

      throw( logMessage, "basecfc.toComponent" );
    }
  }

  /**
    * Route all logging through this method so it can be changed to some
    * external tool some day (as well as shown as debug output)
    */
  public void function basecfcLog( required string text, string level = "debug", string file = request.appName & "-basecfc", string type = "" ) {
    if ( len( type ) && arrayFindNoCase( this.logLevels, type ) ) {
      level = type;
    }

    var requestedLevel = arrayFindNoCase( this.logLevels, level );

    if ( !requestedLevel ) {
      return;
    }

    var levelThreshold = arrayFindNoCase( this.logLevels, variables.instance.config.logLevel );

    if ( requestedLevel >= levelThreshold ) {
      writeLog( text = text, type = level, file = file );
    }

    if ( request.context.debug ) {
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
    if ( structKeyExists( property, "type" ) ) {
      if ( structKeyExists( property, "percentage" ) &&
          isBoolean( property.percentage ) &&
          property.percentage ) {
        return "percentage";
      }
      return property.type;
    }
    if ( structKeyExists( property, "ormtype" ) ) {
      return property.ormtype;
    }
    if ( structKeyExists( property, "sqltype" ) ) {
      return property.sqltype;
    }
    if ( structKeyExists( property, "datatype" ) ) {
      return property.datatype;
    }
    if ( structKeyExists( property, "fieldType" ) ) {
      return property.fieldType;
    }

    return "string";
  }

  private boolean function wasRemovedFromFormdata( required struct property ) {
    return structKeyExists( property, "removeFromFormData" ) && property.removeFromFormData;
  }

  private boolean function isDefaultField( required struct property ) {
    return listFindNoCase( variables.instance.defaultFields, property.name );
  }

  private boolean function isEmptyText( required struct property, required struct formData ) {
    return ( structKeyExists( formData, property.name ) &&
             isSimpleValue( formData[ property.name ] ) &&
             !len( trim( formData[ property.name ] ) ) );
  }

  private boolean function notInFormdata( required struct property, required struct formData ) {
    return ( !structKeyExists( formData, property.name ) &&
             !structKeyExists( formData, "#property.name#id" ) &&
             !structKeyExists( formData, "set_#property.name#" ) &&
             !( structKeyExists( formData, "add_#property.name#" ) || ( structKeyExists( property, "singularName" ) && structKeyExists(
               formData,
               "add_#property.singularName#"
             ) ) ) &&
             !( structKeyExists( formData, "remove_#property.name#" ) || ( structKeyExists( property, "singularName" ) && structKeyExists(
               formData,
               "remove_#property.singularName#"
             ) ) )
           );
  }

  private boolean function skipProperty( required struct property, required struct formData ) {
    return  wasRemovedFromFormdata( property ) ||
            isDefaultField( property ) ||
            isEmptyText( property, formData ) ||
            notInFormdata( property, formData );
  }

  private boolean function canBeLogged( ) {
    return ( variables.instance.config.log && isInstanceOf( this, "#variables.instance.config.root#.model.logged" ) );
  }

  private void function logChanges( struct savedState ) {
    if ( canBeLogged( ) && variables.instance.entityName != "logentry" ) {
      var logAction = isNew( ) ? "created" : "changed";
      var logEntry = entityNew( "logentry" );
      entitySave( logEntry );
      var logResult = logEntry.enterIntoLog( logAction, savedState, this );
      basecfcLog( "Added log entry for #getName( )# (#logResult.getId( )#)." );
      request.context.log = logResult; // <- that's ugly, but I need the log entry in some controllers.
    }
  }
}