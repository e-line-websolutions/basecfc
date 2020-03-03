/*
  ORM Base class used in Mustang

  The MIT License (MIT)

  Copyright (c) 2015-2020 Mingo Hagen

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

  this.version = "4.1.1";
  this.sanitizeDataTypes = listToArray( "date,datetime,double,float,int,integer,numeric,percentage,timestamp" );
  this.logLevels = listToArray( "debug,information,warning,error,fatal" );
  this.logFields = listToArray( "createcontact,createdate,createip,updatecontact,updatedate,updateip" );

  param request.appName="basecfc";
  param request.context.debug=false;

  // Constructor:

  /**
  * The constructor needs to be called in order to populate the instance
  * variables (like variables.instance.meta which is used by the other methods)
  */
  public component function init( ) {
    param variables.name="";
    param variables.deleted=false;
    param variables.sortorder=0;

    variables.instance = {
      'entities' = {},
      'config' = {},
      'meta' = getMetadata(),
      'sanitationReport' = [],
      'sessionFactory' = ormGetSessionFactory(),
      'validationReport' = []
    };

    if ( structKeyExists( url, "clear" ) ) {
      var allCacheIds = cacheGetAllIds( );
      if ( !arrayIsEmpty( allCacheIds ) ) {
        cacheRemove( arrayToList( allCacheIds ), false );
      }
    }

    param variables.instance.config.root="root";
    param variables.instance.properties.id.type='';

    variables.instance[ 'id' ] = getDefaultPK();
    variables.instance[ 'className' ] = getClassName();
    variables.instance[ 'properties' ] = getInheritedProperties();
    variables.instance[ 'entityName' ] = getEntityName();
    variables.instance[ 'settings' ] = getInheritedSettings();
    variables.instance[ 'defaultFields' ] = getDefaultFields();

    // check to see if object has all basic properties (like name, deleted, sortorder)
    validateBaseProperties( );

    // overwrite instance variables:
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

    // return me
    return this;
  }



  // Public manipulation functions:

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

    if ( structIsEmpty( formData ) ) {
      entitySave( this );
      return this;
    }

    if ( isNull( variables.deleted ) ) {
      formData.deleted = false;
    }

    if ( depth == 0 ) {
      request.basecfc = {
        "timers" = { },
        "instructionsOrder" = { },
        "queuedInstructions" = { },
        "queuedObjects" = { "#entityID()#" = this },
        "ormSession" = ormGetSession( )
      };

      if ( canBeLogged( ) ) {
        formData = populateLogFields( formData );
      }

      if ( structKeyExists( arguments, "validationService" ) ) {
        request.basecfc.validationService = validationService;
      }

      if ( structKeyExists( arguments, "sanitationService" ) ) {
        request.basecfc.sanitationService = sanitationService;
      }
    }

    if ( request.context.debug ) {
      var debugid = formatAsGUID( createUUID( ) );
      var collapse = "document.getElementById('#debugid#').style.display=(document.getElementById('#debugid#').style.display==''?'none':'');";
      var display = ' style="display:none;"';

      if ( !structKeyExists( request, "basecfc-save" ) ) {
        request[ "basecfc-save" ] = true;
        writeOutput( '
          <script src="http://helper.e-line.nl/prettify/run_prettify.js"></script>
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

      if ( depth == 0 ) {
        basecfcLog( "~~~ start basecfc.save() ~~~" );
        writeOutput( '<div class="basecfc-debug">' );
        display = '';
      }

      writeOutput( '
        <div class="call">
          <h2 onclick="#collapse#">#depth#:#variables.instance.entityName#:#getID( )#</h2>
          <table cellpadding="0" cellspacing="0" border="0" width="100%" id="#debugid#"#display#>
            <tr>
              <th colspan="2">Name: "#getName( )#"</th>
            </tr>
            <tr>
              <td colspan="2">Prep time: #getTickCount( ) - basecfctimer#ms</td>
            </tr>
      ' );
    }

    // This object can handle non-existing fields, so lets add those to the properties struct.
    if ( arrayLen( structFindValue( variables.instance.meta, "onMissingMethod" ) ) ) {
      var formDataKeys = structKeyArray( formData );
      for ( var key in formDataKeys ) {
        if ( !structKeyExists( inheritedProperties, key ) && !isDefaultField( key ) ) {
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
      var skipMatrix = getSkipMatrix( property, formData );

      if ( skipProperty( skipMatrix ) ) {
        if ( request.context.debug && !property.name == '__subclass' ) {
          writeOutput( '
            <tr style="color:dimgray">
              <th width="15%" valign="top" align="right">#property.name#</th>
              <td>Skipped (#serializeJSON( skipMatrix )#)</td>
            </tr>
          ' );
        }
        continue;
      }

      var reverseCFCLookup = arrayFindNoCase( this.logFields, key )
        ? "#variables.instance.config.root#.model.logged"
        : variables.instance.className;

      savecontent variable="local.debugoutput" {
        param string property.fieldtype="string";
        param string property.dataType="";

        switch ( property.fieldtype ) {
          case "one-to-many":
          case "many-to-many":
            var valueToLog = toMany( formData, property, reverseCFCLookup, depth );
            break;

          case "one-to-one":
            if ( structKeyExists( formData, property.name ) ) {
              var valueToLog = oneToOne( formData[ property.name ], property, reverseCFCLookup, depth );
            }
            break;

          default :
            if ( structKeyExists( formData, property.name ) ) {
              var valueToLog = toOne( formData[ property.name ], property, reverseCFCLookup, depth );
            }
        }

        if ( !isNull( valueToLog ) && !arrayFindNoCase( this.logFields, property.name ) ) {
          savedState[ property.name ] = valueToLog;
        }
      }

      if ( request.context.debug && len( trim( debugoutput ) ) && !key == '__subclass' ) {
        var colID = formatAsGUID( createUuid( ) );
        var collapseCol = "document.getElementById('#colID#').style.display=(document.getElementById('#colID#').style.display==''?'none':'');";
        writeOutput( '
          <tr>
            <th width="15%" valign="top" align="right" onclick="#collapseCol#">#key#</th>
            <td width="85%" id="#colID#">#debugoutput#<br/>#getTickCount( ) - propTimer#ms</td>
          </tr>
        ' );
      }
    }

    if ( request.context.debug ) {
      writeOutput( '
          </table>
          #getTickCount( )-basecfctimer# ms
          <br />
        </div>
      ' );
    }

    // Process queued instructions
    if ( depth == 0 ) {
      processQueue( );
      logChanges( savedState );
    }

    return this;
  }

  /**
  * Short-hand for entity.save( { "deleted" = true } );
  */
  public void function delete( ) {
    variables.deleted = true;
    basecfcLog( "Marked #variables.instance.entityName# as deleted" );
    logChanges( { "deleted" = true } );
  }

  /**
  * Short-hand for entity.save( { "deleted" = false } );
  */
  public void function restore( ) {
    variables.deleted = false;
    basecfcLog( "Unmarked #variables.instance.entityName# as deleted" );
    logChanges( { "deleted" = false } );
  }



  // Public settings functions:

  /**
  * TODO: function documentation
  */
  public component function enableDebug( ) {
    request.context.debug = true;
    return this;
  }

  /**
  * TODO: function documentation
  */
  public component function dontLog( ) {
    variables.instance.config.log = false;
    return this;
  }



  // Public utility functions:

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
    var allEntities = getAllEntities( );
    if ( structKeyExists( allEntities, basicEntityName ) ) {
      return allEntities[ basicEntityName ].name;
    }
    return basicEntityName;
  }

  /**
  * the database table name (as per CFML ORM standard)
  */
  public string function getTableName( string className = variables.instance.className ) {
    var basicEntityName = listLast( className, "." );
    var allEntities = getAllEntities( );
    if ( structKeyExists( allEntities, basicEntityName ) ) {
      return allEntities[ basicEntityName ].table;
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
  * Override default getter to generate a GUID to identify this object with.
  */
  public string function getID( ) {
    return isNew( ) ? variables.instance.id : variables.id;
  }

  public string function getShortId( numeric length = 10 ) {
    return left( hash( getId(), 'SHA-1' ), length );
  }

  /**
  * Returns a db wide unique id
  */
  public string function entityID( ) {
    return getEntityName() & '_' & getId();
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
    var field = 0;
    var fieldFound = 0;
    var propertiesWithCFC = structFindKey( variables.instance.properties, "cfc", "all" );

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

      if ( !structKeyExists( field, "fkColumn" ) ) {
        field[ "fkColumn" ] = "";
      }

      if ( field[ "fkColumn" ] != fkColumn || !( field[ "fkColumn" ] == fkColumn || field.cfc == cfc ) ) {
        continue;
      }

      if ( field.cfc == cfc && field[ "fkColumn" ] == fkColumn ) {
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

    var propertyWithFK = structFindValue( { "a" = propertiesWithCFC }, fkColumn, 'all' );

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

    param field.singularName='';

    if ( singular && field.singularName.len() ) {
      result = field.singularName;
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
    return ( isNull( variables.id ) || !isValidPK( variables.id ) );
  }

  /**
  * a serialized JSON object (a string) representation of this object
  * using Adam Tuttle's deORM() - see below
  */
  public string function toJson( any data = this ) {
    return serializeJSON( deORM( data ) );
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

  /**
  * TODO: function documentation
  */
  public struct function getInstanceVariables( ) {
    var result = duplicate( variables.instance );

    structDelete( result, "meta" );
    structDelete( result, "sessionFactory" );

    return result;
  }

  /**
  * TODO: function documentation
  */
  public array function getSubClasses( ) {
    var classMetaData = variables.instance.sessionFactory.getClassMetadata( variables.instance.entityName );

    if ( classMetaData.hasSubclasses( ) ) {
      try {
        return classMetaData.getSubclassClosure( );
      } catch ( any e ) { }
    }

    return [ ];
  }

  /**
  * TODO: function documentation
  */
  public array function getValidationReport( ) {
    return variables.instance.validationReport;
  }

  /**
  * TODO: function documentation
  */
  public array function getSanitationReport( ) {
    return variables.instance.sanitationReport;
  }



  // Fieldtype save functions (to-one, to-many, etc.):

  /**
  * TODO: function documentation
  */
  private array function toMany( struct formData, struct property, string reverseCFCLookup, numeric depth ) {
    var result = [ ];

    // Alias for set_ which overwrites linked data with new data
    if ( structKeyExists( formData, property.name ) ) {
      formData[ "set_#property.name#" ] = formData[ property.name ];
      structDelete( formData, property.name );
    }

    // REMOVE
    if ( structKeyExists( formData, "set_#property.name#" ) ||
         structKeyExists( formData, "remove_#property.name#" ) ) {
      result.addAll( toMany_remove( formData, property, reverseCFCLookup ) );
    }

    // SET
    formData = toMany_convertSetToAdd( formData, property );

    // ADD
    var key = "add_#propertyName( property )#";

    if ( structKeyExists( formData, key ) ) {
      result.addAll( toMany_add( formData[ key ], property, reverseCFCLookup, depth ) );
    }

    return result;
  }

  /**
  * TODO: function documentation
  */
  private any function toOne( any nestedData, struct property, string reverseCFCLookup, numeric depth ) {
    // save value and link objects together
    var fn = "set" & property.name;
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
            var updateStruct = parseUpdateStruct( nestedData, objectToLink );

            if ( !structCount( updateStruct ) ) {
              skipToNextPropery = true;
            }

            if ( !skipToNextPropery ) {
              if ( !objectToLink.isNew( ) ) {
                updateStruct[ "#propertyEntityName#id" ] = objectToLink.getID( );
                structDelete( updateStruct, "ID" );
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

        if ( structKeyExists( request.basecfc, "sanitationService" ) && arrayFindNoCase( this.sanitizeDataTypes, dataType ) ) {
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
        try {
          var dbugAttr = serializeJSON( nestedData );
        } catch( any e ) {
        }

        if ( !isNull( updateStruct ) ) {
          dbugAttr = serializeJSON( updateStruct );
        }

        if ( isJSON( dbugAttr ) && !isBoolean( dbugAttr ) && !isNumeric( dbugAttr ) ) {
          dbugAttr = '<code class="prettyprint">#replace( dbugAttr, ',', ',<br />', 'all' )#</code>';
        }

        writeOutput( '<p>#fn#( #dbugAttr# )</p>' );
      }
    }
  }

  /**
  * TODO: function documentation
  */
  private string function oneToOne( any nestedData, struct property, string reverseCFCLookup, numeric depth ) {
    var propertyEntityName = property.entityName;

    if ( isStruct( nestedData ) && structKeyExists( nestedData, "__subclass" ) ) {
      propertyEntityName = nestedData[ "__subclass" ];
    }

    var objectToLink = toComponent( nestedData, propertyEntityName, property.cfc );

    queueInstruction( this, "set#property.name#", objectToLink );

    var otherObjectMetaData = objectToLink.getInstanceVariables( );

    if ( structKeyExists( property, "mappedBy" ) ) {
      var reverseField = otherObjectMetaData.properties[ property.mappedBy ].name;
    } else {
      var propertiesMappedBy = structFindKey( otherObjectMetaData.properties, "mappedBy" );

      for ( var result in propertiesMappedBy ) {
        if ( result.value == property.name ) {
          var reverseField = result.owner.name;
          break;
        }
      }
    }

    if ( isNull( reverseField ) ) {
      throw( "Missing reverseField for #property.name# in #getEntityName( )#", "basecfc.getReverseField" );
    }


    if ( !evaluate( "objectToLink.has#reverseField#(this)" ) ) {
      queueInstruction( objectToLink, "set#reverseField#", this );
    }

    var formData = parseUpdateStruct( nestedData, objectToLink );

    objectToLink.save( formData, depth + 1 );

    return objectToLink.getName( );
  }

  /**
  * TODO: function documentation
  */
  private array function toMany_add( any workData, struct property, string reverseCFCLookup, numeric depth ) {
    var result = [ ];

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
        if ( isObjectActionInQueue( fn, objectToLink ) ) {
          continue;
        }

        queueInstruction( this, fn, objectToLink );

        var fkColumn = property.fieldtype == "many-to-many" ? property.inverseJoinColumn : property.fkcolumn;
        var reverseField = objectToLink.getReverseField( reverseCFCLookup, fkColumn );

        if ( evaluate( "has#propertyName( property )#(objectToLink)" ) &&
             evaluate( "objectToLink.has#reverseField#(this)" ) ) {
          continue; // already in object
        }

        var updateStruct = parseUpdateStruct( nestedData, objectToLink );

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
        var nextLayer = objectToLink.save( depth = depth + 1, formData = updateStruct );

        arrayAppend( result, nextLayer );
      }
    }

    return result;
  }

  /**
  * TODO: function documentation
  */
  private array function toMany_remove( struct formData, struct property, string reverseCFCLookup ) {
    var result = [ ];

    var objectsToOverride = getObjectsToOverride( formData, property.name );

    for ( var objectToOverride in objectsToOverride ) {
      if ( property.fieldType == "many-to-many" ) {
        var reverseField = objectToOverride.getReverseField( reverseCFCLookup, property.inverseJoinColumn );
        queueInstruction( objectToOverride, "remove#reverseField#", this );
        arrayAppend( result, "#objectToOverride.getName()#.remove#reverseField#(#this.getName()#)" );
      } else {
        var reverseField = objectToOverride.getReverseField( reverseCFCLookup, property.fkcolumn, false );
        queueInstruction( objectToOverride, "set#reverseField#", "null" );
      }

      queueInstruction( this, "remove#propertyName( property )#", objectToOverride );
      arrayAppend( result, "#this.getName()#.remove#propertyName( property )#(#objectToOverride.getName()#)" );
    }

    return result;
  }

  /**
  * TODO: function documentation
  */
  private struct function toMany_convertSetToAdd( struct formData, struct property ) {
    var key = "set_#property.name#";

    if ( structKeyExists( formData, key ) ) {
      var workData = formData[ key ];

      if ( isSimpleValue( workData ) ) {
        if ( isJSON( workData ) ) {
          workData = deserializeJSON( workData );
        } else if ( isJSON( '[' & workData & ']' ) ) {
          workData = deSerializeJSON( '[' & workData & ']' ); // for lucee
        } else if ( workData == 'null' ) {
          workData = [];
        } else {
          workData = listToArray( workData );
        }
      }

      if ( isNull( workData ) ) var workData = [];

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
        }

        formData[ "add_#propertyName( property )#" ] = entitiesToAdd;
      }

      structDelete( formData, "set_#property.name#" );
    }

    return formData;
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
  private boolean function isValidPK( required any potentialPK ) {
    param variables.instance.properties.id.type='';

    if ( variables.instance.properties.id.type == 'int' ) {
      return val( potentialPK ) > 0;
    }

    if ( !isSimpleValue( potentialPK ) ) {
      return false;
    }

    if ( len( potentialPK ) < 32 ) {
      return false;
    }

    if ( isValid( "guid", potentialPK ) ) {
      return true;
    }

    return isValid( "guid", formatAsGUID( potentialPK ) );
  }

  /**
  * Parses a JSON string into a struct (or passes through the given struct)
  */
  private struct function parseUpdateStruct( required any data, required component parseFor ) {
    var result = { };

    if ( isSimpleValue( data ) && len( trim( data ) ) ) {
      if ( isValidPK( data ) ) {
        data = {
          "#parseFor.getEntityName( )#id" = data
        };
      } else if ( isJSON( data ) ) {
        var tempValue = deserializeJSON( data );
        if ( isStruct( tempValue ) ) {
          data = tempValue;
        }
      }
    }

    if ( isStruct( data ) && !isObject( data ) ) {
      for ( var key in data ) {
        if ( !arrayFindNoCase( [ "VERSION", "LOGFIELDS", "LOGLEVELS", "SANITIZEDATATYPES" ], key ) ) {
          result[ key ] = data[ key ];
        }
      }
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
    var idx = 0;

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
          var logValue = isSimpleValue( value )
            ? value
            : isObject( value )
                ? value.getName( )
                : '';
          var logMessage = "called: [#objectid#] #object.getEntityName( )#.#command#";

          if ( !isNull( logValue ) ) {
            logMessage &= "(#logValue#)";
          }

          var instructionTimer = getTickCount( );

          try {
            var fieldName = getFieldNameFromCommand( command );
            invoke( object, command, [
              isSimpleValue( value ) && value == 'null'
                ? javaCast("null",0)
                : value
            ] );
          } catch ( any e ) {
            basecfcLog( logMessage & " FAILED", "fatal" );
            rethrow;
          }

          if ( request.context.debug ) {
            instructionTimer = getTickCount( ) - instructionTimer;
            var timerColor = instructionTimer > 50 ? ( instructionTimer > 250 ? 'red' : 'orange' ) : 'black';
            basecfcLog( logMessage & ' (t=#instructionTimer#, n=#++idx#)', 'fatal' );
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
      entitySave( object );
    }

    for ( var objectid in instructionsQueue ) {
      var object = request.basecfc.queuedObjects[ objectId ];
      ormEvictEntity( object.getEntityName( ), object.getId( ) );
    }

    if ( request.context.debug ) {
      basecfcLog( "~~ finished queue in " & instructionTimers & "ms. ~~" );
    }
  }

  /**
  * TODO: function documentation
  */
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

    if ( command == 'set__subclass' ) {
      return;
    }

    var entityID = entity.entityID();

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

      arrayAppend( request.basecfc.instructionsOrder[ entityID ][ command ], valueID );
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
        } else if ( isValidPK( parsedVar ) ) {
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

        if ( isValidPK( pk ) ) {
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

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // START PROPERTY SKIP FUNCTIONS
  // These 4 functions try to figure out if a field can and must be skipped:

  /**
  * This one is not yet in use; this is meant to work in combination with isEmptyText() to save a just cleared text field
  * TODO: make this work
  */
  private boolean function wasRemovedFromFormdata( required struct property ) {
    return structKeyExists( property, "removeFromFormData" ) && property.removeFromFormData;
  }

  /**
  * The default fields are created/updated using other methods or not at all (in case of CF form fields like 'fieldnames')
  */
  private boolean function isDefaultField( required string fieldName ) {
    return arrayFindNoCase( variables.instance.defaultFields, fieldName );
  }

  /**
  * A field gets ignored when it is a text field and is empty. This is a problem for when you want to clear a field.
  * There's a function above (wasRemovedFromFormdata) that's supposed to fix this somehow, but that's not yet in use.
  */
  private boolean function isEmptyText( required struct property, required struct formData ) {
    return ( structKeyExists( formData, property.name ) &&
             isSimpleValue( formData[ property.name ] ) &&
             !len( trim( formData[ property.name ] ) ) );
  }

  /**
  * field is not in form data (could be because its value is NULL)
  * where field is one of:
  *  - field
  *  - fieldId
  *  - add_field(s)
  *  - set_field
  *  - remove_field(s)
  */
  private boolean function notInFormdata( required struct property, required struct formData ) {
    param property.singularName='';
    return (
      !structKeyExists( formData, property.name ) &&
      !structKeyExists( formData, '#property.name#id' ) &&
      !structKeyExists( formData, 'set_#property.name#' ) &&
      !( structKeyExists( formData, 'add_#property.name#' ) || structKeyExists( formData, 'add_#property.singularName#' ) ) &&
      !( structKeyExists( formData, 'remove_#property.name#' ) || structKeyExists( formData, 'remove_#property.singularName#' ) )
    );
  }

  /**
  * TODO: function documentation
  */
  private array function getSkipMatrix( required struct property, required struct formData ) {
    var skipMatrix = [
      wasRemovedFromFormdata( property )  ? 1 : 0,
      isDefaultField( property.name )     ? 1 : 0,
      isEmptyText( property, formData )   ? 1 : 0,
      notInFormdata( property, formData ) ? 1 : 0
    ];

    return skipMatrix;
  }

  /**
  * TODO: function documentation
  */
  private boolean function skipProperty( skipMatrix ) {
    return arraySum( skipMatrix ) > 0;
  }

  //  /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\ /\
  //  END SKIP FUNCTIONS
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  /**
  * TODO: function documentation
  */
  private boolean function canBeLogged( ) {
    return variables.instance.config.log && variables.instance.settings.canBeLogged;
  }

  /**
  * TODO: function documentation
  */
  private void function logChanges( struct savedState ) {
    if ( structKeyExists( savedState, "logEntries" ) ) {
      return;
    }

    if ( !canBeLogged( ) ) {
      return;
    }

    if ( variables.instance.entityName == "logentry" ) {
      return;
    }

    var logAction = isNew( ) ? "created" : "changed";
    var logEntry = entityNew( "logentry" );
    entitySave( logEntry );
    var logResult = logEntry.enterIntoLog( logAction, savedState, this );
    basecfcLog( "Added log entry for #getName( )# (#logResult.getId( )#)." );
    request.context.log = logResult; // <- that's ugly, but I need the log entry in some controllers.
  }

  /**
  * TODO: function documentation
  */
  private struct function getInheritedSettings( ) {
    var cachedSettingsKey = "settings-#request.appName#_#variables.instance.className#";
    var cachedSettings = cacheGet( cachedSettingsKey );

    if ( isNull( cachedSettings ) ) {
      var md = variables.instance.meta;
      var cachedSettings = { "canBeLogged" = false };

      do {
        for ( var key in md ) {
          if ( isSimpleValue( md[ key ] ) && !structKeyExists( cachedSettings, key ) ) {
            cachedSettings[ key ] = md[ key ];
          }
        }

        if ( md.name contains "logged" ) {
          cachedSettings.canBeLogged = true;
        }

        md = md.extends;
      } while ( structKeyExists( md, "extends" ) );

      cachePut( cachedSettingsKey, cachedSettings );
    }

    return cachedSettings;
  }

  /**
  * TODO: function documentation
  */
  private array function getObjectsToOverride( formData, fieldName ) {
    var hql = '
      SELECT    otherTable
      FROM      #variables.instance.entityName# thisTable
                  JOIN thisTable.#fieldName# otherTable
      WHERE     thisTable.id = :thisTablePK
    ';
    var params = { 'thisTablePK' = getId() };

    if ( structKeyExists( formData, 'remove_#fieldName#' ) ) {
      var entitiesToRemove = formData[ 'remove_#fieldName#' ];

      if ( !isArray( entitiesToRemove ) ) {
        entitiesToRemove = [ entitiesToRemove ];
      }

      var entitiesToRemoveAsIds = [];

      for ( var entityToRemove in entitiesToRemove ) {
        var asEntityId = entityToRemove;

        if ( isObject( entityToRemove ) && structKeyExists( entityToRemove, 'getId' ) ) {
          asEntityId = entityToRemove.getId();
        }

        if ( isValidPK( asEntityId ) ) {
          arrayAppend( entitiesToRemoveAsIds, asEntityId );
        }
      }

      if ( !entitiesToRemoveAsIds.isEmpty() ) {
        params[ 'otherTableIds' ] = entitiesToRemoveAsIds;
        hql &= ' AND otherTable.id IN ( :otherTableIds )';
      }
    }

    try {
      return ormExecuteQuery( hql, params );
    } catch ( any e ) {
      throw( 'Error in query', 'basecfc.global', '#e.message# #e.detail# - SQL: #hql#, Params: #serializeJSON( params )#' );
    }
  }

  /**
  * All ORM entities in this app are stored in cache using this function
  */
  private struct function getAllEntities() {
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

    return cachedEntities;
  }

  /**
  * Check if an ORM function call was already placed in the queue, no need to do that twice
  */
  private boolean function isObjectActionInQueue( fn, objectToLink ) {
    var result = (
      structKeyExists( request.basecfc.queuedInstructions, entityID() ) &&
      structKeyExists( request.basecfc.queuedInstructions[ entityID() ], fn )
    );

    if ( !isNull( objectToLink ) ) {
      result = ( result && structKeyExists( request.basecfc.queuedInstructions[ entityID() ][ fn ], objectToLink.getID( ) ) );
    }

    return result;
  }

  /**
  * Basic presence check on the basecfc mandatory fields
  *  - name      every basecfc-entity has a name, so getName() can always be used (what you do with it is up to you)
  *  - deleted   basecfc-entities are not deleted, only marked as such
  *  - sortorder basecfc-entities always have a sortkey, if you don't use it, set it to 0.
  */
  private void function validateBaseProperties( ) {
    if ( variables.instance.className == "basecfc.base" ) {
      return;
    }

    if ( !structKeyExists( variables.instance.properties, "name" ) ||
         !structKeyExists( variables.instance.properties, "deleted" ) ||
         !structKeyExists( variables.instance.properties, "sortorder" ) ) {
      throw(
        "Missing essential properties",
        "basecfc.init.invalidPropertiesError",
        "Objects extending basecfc must have a name, deleted and sortorder property."
      );
    }
  }

  /**
  * Returns either a numeric or guid primary key
  */
  private string function getDefaultPK() {
    return variables.instance.properties.id.type == 'int' ? 0 : formatAsGUID( createUUID() );
  }

  /**
  * Returns an array of field names used in forms that need to be ignored
  *
  */
  private array function getDefaultFields( ) {
    return listToArray( "log,id,fieldnames,submitbutton,#variables.instance.entityName#id" );
  }

  /**
  * Figures out the fieldname from a get/set/remove function call
  */
  private string function getFieldNameFromCommand( required string input ) {
    var commands = [ 'set', 'add', 'remove' ];
    for ( command in commands ) {
      if ( left( input, len( command ) ) == command ) {
        return replaceNoCase( input, command, '' );
      }
    }
    return input;
  }

  /**
  * Populates metadata fields with findable information
  * - like: date, IP address and contact
  */
  private struct function populateLogFields( required struct formData ) {
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
            structKeyExists( variables.instance, "auth" ) &&
            structKeyExists( variables.instance.auth, "userID" ) &&
            isValidPK( variables.instance.auth.userID ) ) {
          formData.createContact = variables.instance.auth.userID;
        }
      }

      if ( !structKeyExists( formData, "updateContact" ) &&
          structKeyExists( variables.instance, "auth" ) &&
          structKeyExists( variables.instance.auth, "userID" ) &&
            isValidPK( variables.instance.auth.userID ) ) {
        formData.updateContact = variables.instance.auth.userID;
      }
    }

    return formData;
  }
}