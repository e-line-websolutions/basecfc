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

  this.version = "4.4.1";
  this.sanitizeDataTypes = listToArray( "date,datetime,double,float,int,integer,numeric,percentage,timestamp" );
  this.logLevels = listToArray( "debug,information,warning,error,fatal" );
  this.logFields = listToArray( "createcontact,createdate,createip,updatecontact,updatedate,updateip" );

  // Constructor:
  public component function init() {
    setup();
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
  public any function save( required struct formData = { }, numeric depth = 0, component validationService, component sanitationService ) {
    var basecfctimer = getTickCount( );

    // objects using .save() must be initialised using the constructor
    verifySetup();

    // Hard coded depth limit
    if ( depth > 10 ) {
      var logMessage = 'Infinite loop fail safe triggered';
      basecfcLog( logMessage, 'fatal' );
      throw( logMessage, 'basecfc.global' );
    }

    var savedState = { };

    for ( var logField in this.logFields ) {
      formData.delete( logField );
    }

    if ( formData.isEmpty() ) {
      entitySave( this );
      return this;
    }

    if ( isNull( variables.deleted ) ) {
      formData.deleted = false;
    }

    if ( depth == 0 ) {
      request.basecfc = {
        'name' = '_basecfc_#hash(createUuid())#',
        'timers' = {},
        'instructionsOrder' = {}, // should be ordered, but cf11 doesn't have this feature.
        'queuedInstructions' = {}, // should be ordered, but cf11 doesn't have this feature.
        'queuedObjects' = { '#getEntityGUID()#' = this }
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

    if ( isDebugEnabled() ) {
      var debugid = formatAsGUID( createUUID( ) );
      var collapse = "document.getElementById('#debugid#').style.display=(document.getElementById('#debugid#').style.display==''?'none':'');";
      var display = ' style="display:none;"';

      if ( !structKeyExists( request, "basecfc-save" ) ) {
        request[ "basecfc-save" ] = true;
        writeOutput( '
          <script src="//helper.e-line.nl/prettify/run_prettify.js"></script>
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
          <h2 onclick="#collapse#">#depth#:#variables.instance.entityName#:#getId()#</h2>
          <table cellpadding="0" cellspacing="0" border="0" width="100%" id="#debugid#"#display#>
            <tr>
              <th colspan="2">Name: "#getName()#"</th>
            </tr>
            <tr>
              <td colspan="2">Prep time: #getTickCount() - basecfctimer#ms.</td>
            </tr>
      ' );
    }

    // setup object properties to loop over:

    var inheritedProperties = variables.instance.properties;

    // This object can handle non-existing fields, so lets add those to the properties struct.
    //  - ignore fields ending in ID
    //  - ignore actual object properties
    //  - ignore default fields
    if ( variables.instance.meta.findValue( "onMissingMethod" ).len() ) {
      formData.keyArray()
        .filter( function( key ){ return right( key, 2 ) != 'id'; } )
        .filter( function( key ){ return !inheritedProperties.keyExists( key ); } )
        .each( function( key ) { inheritedProperties[ key ] = { 'name' = key, 'jsonData' = true }; } );
    }

    var sortedPropertyKeys = inheritedProperties.keyArray();
    sortedPropertyKeys.sort( 'textNoCase' );

    // SAVE VALUES PASSED VIA FORM
    for ( var key in sortedPropertyKeys ) {
      lock timeout=30 name='_lock_#request.basecfc.name#' throwontimeout=true {
        if ( isDefaultField( key ) ) continue;

        var propTimer = getTickCount( );
        var debugoutput = '';
        var property = inheritedProperties[ key ];
        var reverseCFCLookup = this.logFields.findNoCase( key )
          ? getORMBase() & '.logged'
          : variables.instance.className;

        savecontent variable="debugoutput" {
          param type="string" name="property.fieldtype" default="string";
          param type="string" name="property.dataType" default="";

          switch ( property.fieldtype ) {
            case 'one-to-many':
            case 'many-to-many':
              var valueToLog = toMany( formData, property, reverseCFCLookup, depth );
              break;

            case 'one-to-one':
              if ( formData.keyExists( property.name ) ) {
                var valueToLog = oneToOne( formData[ property.name ], property, reverseCFCLookup, depth );
              }
              break;

            default:
              if ( formData.keyExists( property.name ) ) {
                var valueToLog = toOne( formData[ property.name ], property, reverseCFCLookup, depth );
              }
          }

          // log changes if value is not empty and if field is not one of the standard log fields
          if ( !isNull( valueToLog ) && !this.logFields.findNoCase( property.name ) ) {
            savedState[ property.name ] = valueToLog;
          } else if ( isDebugEnabled() ) {
            writeOutput( '<br>not logging anything for "#property.name#" (#isNull(valueToLog)?'null':'not null'#/#this.logFields.findNoCase( property.name )#)' );
          }
        }

        if ( isDebugEnabled() && len( trim( debugoutput ) ) && !key == '__subclass' ) {
          var colID = formatAsGUID( createUUID( ) );
          var collapseCol = "document.getElementById('#colID#').style.display=(document.getElementById('#colID#').style.display==''?'none':'');";
          writeOutput( '<tr><th width="15%" valign="top" align="right" onclick="#collapseCol#">#key#</th><td width="85%" id="#colID#">' );
          writeOutput( debugoutput.len() ? '#debugoutput#<br>' : '' );
          writeOutput( 'save() - #property.name# (#property.fieldtype#): #getTickCount() - propTimer#ms.' );
          writeOutput( '</td></tr>' );
        }
      }
    }

    if ( isDebugEnabled() ) {
      writeOutput( '
          </table>
          #variables.instance.entityName#: #getTickCount( )-basecfctimer#ms.
          <br />
        </div>
      ' );
    }

    // Process queued instructions
    if ( depth == 0 ) {
      processQueue();
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
  public boolean function isDebugEnabled() {
    param request.context.debug = false;
    return request.context.debug;
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
  public string function getClassName( filePath ) {
    param filePath=variables.instance.meta.path;
    var re = reFindNoCase( '[/\\]((orm|model[/\\]beans|model)[/\\].+)\.cfc', filePath, 1, true );
    if ( !re.pos.len() >= 2 ) return '';
    var dottedPath = mid( filePath, re.pos[2], re.len[2] ).replace( '/', '.', 'all' ).replace( '\', '.', 'all' );
    return variables.instance.config.root & '.' & dottedPath;
  }

  /**
  * the entity name (as per CFML ORM standard)
  */
  public string function getEntityName( string className ) {
    setup();

    param className = variables.instance.className;

    var basicEntityName = className.listLast( '.' );
    if ( request.allOrmEntities.keyExists( basicEntityName ) ) {
      return request.allOrmEntities[ basicEntityName ].name;
    }
    return basicEntityName;
  }

  /**
  * the database table name (as per CFML ORM standard)
  */
  public string function getTableName( string className ) {
    param className = variables.instance.className;

    var basicEntityName = className.listLast( '.' );
    if ( request.allOrmEntities.keyExists( basicEntityName ) ) {
      return request.allOrmEntities[ basicEntityName ].table;
    }
    return basicEntityName;
  }

  /**
  * the database table's schema name
  */
  public string function getSchemaName() {
    return variables.instance.meta.schema ?: 'public';
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
            var fieldValue = invoke( this, 'get#currentField#' );

            if ( isObject( fieldValue ) ) {
              arrayAppend( result, fieldValue.getName( ) );
              continue;
            } else if ( isSimpleValue( fieldValue ) && len( fieldValue ) ) {
              arrayAppend( result, fieldValue );
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
  public string function getId() {
    return isNew() ? variables.instance.id : variables.id;
  }

  public string function getShortId( numeric length = 10 ) {
    return left( hash( getId(), 'SHA-1' ), length );
  }

  /**
  * Returns a db wide unique id
  */
  public string function getEntityGUID() {
    return getEntityName() & '_' & getId();
  }

  /**
  * a struct containing this objects and its ancestors properties
  */
  public struct function getInheritedProperties() {
    var cachedPropertiesKey = 'props-#request.appName#_#variables.instance.className#';
    var cachedProperties = cacheGet( cachedPropertiesKey );

    if ( !isNull( cachedProperties ) ) {
      // return cachedProperties;
    }

    var md = variables.instance.meta;
    var result = {};

    do {
      if ( md.keyExists( 'properties' ) && isArray( md.properties ) ) {
        var numberOfProperties = arrayLen( md.properties );

        for ( var i = 1; i <= numberOfProperties; i++ ) {
          var property = md.properties[ i ];

          if ( !result.keyExists( property.name ) ) {
            result[ property.name ] = {};
          }

          if ( property.keyExists( 'cfc' ) ) {
            property.entityName = getEntityName( property.cfc );
            property.tableName = getTableName( property.cfc );
          }

          result[ property.name ].append( property, false );
        }
      }
      md = md.extends;
    } while ( md.keyExists( 'extends' ) );

    cachePut( cachedPropertiesKey, result );

    return result;
  }

  /**
  * Find the corresponding field in the joined object (using the FKColumn)
  */
  public string function getReverseField( required string cfcPath, required string fkColumn, boolean singular = true ) {
    var t = getTickCount();
    var fieldFound = 0;
    var propertiesWithCFC = variables.instance.properties.findKey( 'cfc', 'all' );
    var expectedEntityName = cfcPath.listLast( '.' );

    if ( propertiesWithCFC.isEmpty() ) {
      var logMessage = 'getReverseField() ERROR: nothing linked to #cfcPath#.';
      basecfcLog( logMessage, 'fatal' );

      try {
        var expectedCode = 'property name="#expectedEntityName#s" singularName="#expectedEntityName#" fieldType="one-to-many" cfc="#cfcPath#" fkColumn="#fkColumn#";';
        var errorDetail = 'Expected something like: #expectedCode#';

        if ( len( fkColumn ) > 2 ) {
          errorDetail &= chr( 10 ) & 'In template: #left( fkColumn, len( fkColumn ) - 2 )#.cfc';
        }
      } catch ( any e ) {
        basecfcLog( e.message, 'fatal' );
        var errorDetail = '';
      }

      throw( logMessage, 'basecfc.getReverseField', errorDetail );
    }

    var testObj = entityNew( expectedEntityName );

    for ( var property in propertiesWithCFC ) {
      var field = property.owner;

      param field.fkColumn = '';

      if ( field.fkColumn != fkColumn || !( field.fkColumn == fkColumn || field.cfc == cfcPath ) ) {
        continue;
      }

      if ( field.cfc == cfcPath && field.fkColumn == fkColumn ) {
        fieldFound = 1;
        break;
      }


      if ( luceeAcfIsInstanceOf( testObj, field.cfc.listLast( '.' ) ) ) {
        fieldFound = 2;
        break;
      }

      if ( testObj.getClassName() == field.cfc ) {
        fieldFound = 3;
        break;
      }
    }

    var propertyWithFK = structFindValue( { 'a' = propertiesWithCFC }, fkColumn, 'all' );

    if ( arrayLen( propertyWithFK ) == 1 ) {
      field = propertyWithFK[ 1 ].owner;
      fieldFound = 4;
    }

    if ( fieldFound == 0 ) {
      var logMessage = 'getReverseField() ERROR: no reverse field found for fk #fkColumn# in cfc #cfcPath#.';
      basecfcLog( logMessage, 'fatal' );
      throw( logMessage, 'basecfc.getReverseField' );
    }

    var result = field.name;

    param field.singularName = "";

    if ( singular && field.singularName.len() ) {
      result = field.singularName;
    }

    if ( isDebugEnabled() ) writeOutput( '<br>getReverseField() #getTickCount()-t#ms.' );

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
  public boolean function isNew() {
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
    if ( isSimpleValue( data ) ) {
      return data;

    } else if ( isObject( data ) ) {
      return deWormObject( data );

    } else if ( isStruct( data ) ) {
      return deWormStruct( data );

    } else if ( isArray( data ) ) {
      return deWormArray( data );

    }
  }

  private struct function deWormObject( data ) {
    return data.getInheritedProperties()
      .filter( function( key, prop ) { return !isNull( prop ); } )
      .filter( function( key, prop ) {
        var propertyHasGetter = structkeyExists( this, 'get#prop.name#' );
        var isSimpleProperty = !( prop.keyExists( 'fieldtype' ) && prop.fieldtype.findNoCase( '-to-' ) );
        return ( propertyHasGetter && isSimpleProperty );
      } )
      .map( function( key, prop ) {
        return invoke( this, 'get#prop.name#' );
      } );
  }

  private struct function deWormStruct( data ) {
    if ( isNull( data ) ) return {};

    return data
      .filter( function( key, value ) { return !isNull( value ); } )
      .map( function( key, value ) { return deORM( value ); } );
  }


  private array function deWormArray( data ) {
    var result = [];

    data.each(function(key, value){
      result.append( deORM( value ) );
    });

    return result;
  }

  /**
  * Safe get
  */
  public any function safeGet( prop ) {
    try {
      var result = invoke( this, 'get#prop#' );

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
    verifySetup();

    var result = duplicate( variables.instance );

    structDelete( result, "meta" );

    return result;
  }

  /**
  * TODO: function documentation
  */
  public array function getSubClasses( ) {
    var classMetaData = ormGetSessionFactory().getClassMetadata( variables.instance.entityName );

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
    var t = getTickCount();
    var result = [];

    // Alias for set_ which overwrites linked data with new data
    if ( formData.keyExists( property.name ) ) {
      formData[ 'set_#property.name#' ] = formData[ property.name ];
      formData.delete( property.name );
    }

    // REMOVE
    if ( formData.keyExists( 'set_#property.name#' ) ||
    formData.keyExists( 'remove_#property.name#' ) ) {
      result.append( toMany_remove( formData, property, reverseCFCLookup ), true );
    }

    // SET
    formData = toMany_convertSetToAdd( formData, property );

    // ADD
    var key = 'add_#propertyName( property )#';

    if ( formData.keyExists( key ) ) {
      result.append( toMany_add( formData[ key ], property, reverseCFCLookup, depth ), true );
    }

    if ( isDebugEnabled() ) writeOutput( '<br>toMany() #getTickCount()-t#ms.' );

    return result;
  }

  /**
  * TODO: function documentation
  */
  private any function toOne( any nestedData, struct property, string reverseCFCLookup, numeric depth ) {
    return property.keyExists( "cfc" )
      ? toOne_complex( argumentCollection = arguments )
      : toOne_simple( argumentCollection = arguments );
  }

  /**
  * generates set() command for complex (component) value fields
  */
  private any function toOne_complex( any nestedData, struct property, string reverseCFCLookup, numeric depth ) {
    if ( isDebugEnabled() ) writeOutput( '<br>called toOne_complex()' );

    var t = getTickCount();
    var fn = "set" & property.name;
    var skipToNextPropery = false;
    var propertyEntityName = property.entityName;

    if ( isStruct( nestedData ) && !isObject(nestedData) && nestedData.keyExists( "__subclass" ) ) {
      propertyEntityName = nestedData[ "__subclass" ];
    }

    var objectToLink = toComponent( nestedData, propertyEntityName, property.cfc );
    var valueToLog = "removed"; // default

    if ( !isNull( objectToLink ) ) {
      if ( isObjectActionInQueue( fn, objectToLink ) ) {
        skipToNextPropery = true;
      }

      if ( !skipToNextPropery ) {
        queueInstruction( this, fn, objectToLink );

        var reverseField = objectToLink.getReverseField( reverseCFCLookup, property.fkcolumn );

        if ( !skipToNextPropery ) {
          var updateStruct = parseUpdateStruct( nestedData, objectToLink );

          if ( updateStruct.isEmpty() ) {
            skipToNextPropery = true;
          }

          if ( !skipToNextPropery ) {
            if ( !objectToLink.isNew() ) {
              updateStruct[ '#propertyEntityName#id' ] = objectToLink.getId();
              updateStruct.delete( 'ID' );
            }

            updateStruct[ 'add_#reverseField#' ] = this;

            // Go down the rabbit hole:
            nestedData = objectToLink.save( depth = depth + 1, formData = updateStruct );

            if ( !isNull( nestedData ) ) var valueToLog = nestedData.getName();
          }
        }
      }
    }

    if ( !skipToNextPropery ) {
      // remove data if nestedData is empty
      if ( isNull( nestedData ) || isDeletedEntity( nestedData ) ) {
        queueInstruction( this, fn, "null" );
      }
    }

    if ( !isNull( valueToLog ) ) {
      return valueToLog;
    }
  }

  /**
  * generates set() command for simple value fields
  */
  private any function toOne_simple( any nestedData, struct property, string reverseCFCLookup, numeric depth ) {
    if ( isDebugEnabled() ) writeOutput( '<br>called toOne_simple()' );

    var t = getTickCount();
    var fn = "set" & property.name;
    var skipToNextPropery = false;

    if ( property.dataType == "json" && !isSimpleValue( nestedData ) ) {
      nestedData = serializeJSON( nestedData );
    }

    var dataType = getDatatype( property );

    // check inside json obj to see if an ID was passed in
    if ( property.name != 'savedstate' ) {
      try {
        var testForJSON = deserializeJSON( nestedData );
        if ( isStruct( testForJSON ) && testForJSON.keyExists( "id" ) ) {
          nestedData = testForJSON.id;
        }
      } catch ( any e ) {
      }
    }

    if ( request.basecfc.keyExists( "sanitationService" ) && this.sanitizeDataTypes.findNoCase( dataType ) ) {
      var dirtyValue = duplicate( nestedData );
      var sanitationResult = request.basecfc.sanitationService.sanitize( nestedData, dataType );

      if ( isDebugEnabled() ) writeOutput( '<br>toOne_simple() 4. #getTickCount()-t#ms.' );

      nestedData = sanitationResult.value;

      var sanitationFailed = sanitationResult.keyExists( "error" );

      if ( sanitationFailed ) {
        var sanitationError = sanitationResult.error;
        variables.instance.sanitationReport.append( {
          "type" = "sanitation",
          "object" = variables.instance.className,
          "field" = property.name,
          "value" = nestedData,
          "datatype" = dataType,
          "message" = sanitationError.message,
          "detail" = sanitationError.detail,
          "errortype" = sanitationError.type
        } );
        skipToNextPropery = true; // break off trying to set this value, as it won't work anyway.
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

      var valueToLog = isSimpleValue( nestedData ) ? left( nestedData, 255 ) : 'complex-value';
    }

    if ( !skipToNextPropery && ( isNull( nestedData ) || isDeletedEntity( nestedData ) ) ) {
      // remove data if nestedData is empty
      queueInstruction( this, fn, "null" );
    }

    if ( isDebugEnabled() ) writeOutput( '<br>toOne_simple() #getTickCount()-t#ms.' );

    if ( !isNull( valueToLog ) ) {
      return valueToLog;
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

    if ( !objectsAreadyLinked( objectToLink, property, reverseField, depth ) ) {
      queueInstruction( objectToLink, "set#reverseField#", this );
    }

    var formData = parseUpdateStruct( nestedData, objectToLink );

    // Go down the rabbit hole:
    objectToLink.save( formData, depth + 1 );

    return objectToLink.getName( );
  }

  /**
  * TODO: function documentation
  */
  private array function parseJsonOrListIntoArrayOfIds( any workData ) {
    if ( isSimpleValue( workData ) ) {
      if ( isJSON( workData ) ) {
        workData = deSerializeJSON( workData );
      } else if ( isJSON( '[' & workData & ']' ) ) {
        workData = deSerializeJSON( '[' & workData & ']' ); // for lucee
      } else {
        return workData.listToArray().map( function( itemID ) { return { "id" = itemID }; } );
      }
    }

    if ( !isArray( workData ) ) {
      return [ workData ];
    }

    return workData;
  }

  /**
  * TODO: function documentation
  */
  private array function toMany_add( any workData, struct property, string reverseCFCLookup, numeric depth ) {
    var t = getTickCount();
    var result = [];
    var fn = 'add' & propertyName( property );

    parseJsonOrListIntoArrayOfIds( workData ).each( function( nestedData, idx ) {
      var propertyEntityName = property.entityName;

      if ( isStruct( nestedData ) && !isObject( nestedData ) && nestedData.keyExists( '__subclass' ) ) {
        propertyEntityName = nestedData[ '__subclass' ];
      }

      var objectToLink = toComponent( nestedData, propertyEntityName, property.cfc );

      if ( isNull( objectToLink ) ) throw( 'Failed to convert nested data to component' );

      var fkColumn = property.fieldtype == 'many-to-many'
        ? property.inverseJoinColumn
        : property.fkcolumn;
      var reverseField = objectToLink.getReverseField( reverseCFCLookup, fkColumn );

      if ( isObjectActionInQueue( fn, objectToLink ) ) {
        continue;
      } // EARLY EXIT

      if ( objectsAreadyLinked( objectToLink, property, reverseField, depth ) ) {
        continue;
      } // EARLY EXIT

      queueInstruction( this, fn, objectToLink, idx );

      var updateStruct = parseUpdateStruct( nestedData, objectToLink );

      if ( !updateStruct.count() ) {
        continue;
      } // EARLY EXIT

      if ( !objectToLink.isNew() ) {
        updateStruct[ '#propertyEntityName#id' ] = objectToLink.getId();
      }

      if ( property.fieldtype == 'many-to-many' ) {
        reverseField = 'add_#reverseField#';
      }

      updateStruct[ reverseField ] = this;

      if ( isDebugEnabled() ) {
        basecfcLog( 'calling: o2m #propertyEntityName#.save(#depth + 1#)' );
      }

      if ( isDebugEnabled() ) writeOutput( '<br>toMany_add() -> save() #getTickCount()-t#ms.' );

      // Go down the rabbit hole:
      result.append( objectToLink.save( depth = depth + 1, formData = updateStruct ) );
    } );

    if ( isDebugEnabled() ) writeOutput( '<br>toMany_add() #getTickCount()-t#ms.' );

    return result;
  }

  /**
  * TODO: function documentation
  */
  private array function toMany_remove( struct formData, struct property, string reverseCFCLookup ) {
    var t = getTickCount();
    var result = [ ];

    var objectsToOverride = getObjectsToOverride( formData, property.name );

    if ( isDebugEnabled() ) writeOutput( '<br>called toMany_remove() => #objectsToOverride.len()#' );

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

    if ( isDebugEnabled() ) writeOutput( '<br>toMany_remove( formData, #property.name#, #reverseCFCLookup# ) - #getTickCount()-t#ms.' );

    return result;
  }

  /**
  * TODO: function documentation
  */
  private struct function toMany_convertSetToAdd( struct formData, struct property ) {
    var t = getTickCount();
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

      if ( workData.isEmpty() ) {
        formData[ 'set_#property.name#' ] = javaCast( 'null', 0 );
      }
    }

    if ( isDebugEnabled() ) writeOutput( '<br>toMany_convertSetToAdd() #getTickCount()-t#ms.' );

    return formData;
  }



  // Private functions:

  /**
  * Compares two component instances by ID or by using Java's equals()
  */
  private boolean function compareObjects( required component objA, required component objB ) {
    var idA = objA.getId( );
    var idB = objB.getId( );

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
    var t = getTickCount();
    var result = {};

    if ( isObject( data ) ) {
      return { '#data.getEntityName()#id' = data.getId() };
    } // EARLY EXIT (doesn't work on objects)

    if ( !isStruct( data ) ) {
      if ( isValidPK( data ) ) {
        // converts a UUID into a struct with an ID key:
        return { '#parseFor.getEntityName()#id' = data }; // EARLY EXIT
      } else if ( isJSON( data ) ) {
        // converts json and passes it on if it's a struct:
        var tempValue = deserializeJSON( data );
        if ( isStruct( tempValue ) ) data = tempValue;
      }
    }

    // remove default fields:
    if ( isStruct( data ) ) {
      var ignoreTheseKeys = [
        'VERSION',
        'LOGFIELDS',
        'LOGLEVELS',
        'SANITIZEDATATYPES'
      ];
      result = data.filter( function( key ) {
        return !ignoreTheseKeys.findNoCase( key );
      } );
    }

    if ( isDebugEnabled() ) writeOutput( '<br>parseUpdateStruct() #getTickCount()-t#ms.' );

    // could return an empty struct:
    return result;
  }

  /**
  * Processes the queued instructions in one batch
  */
  private void function processQueue( ) {
    if ( isDebugEnabled() ) {
      var instructionTimers = 0;
      basecfcLog( "~~ start processing queue for #variables.instance.meta.name# ~~" );
    }

    var instructionOrder = request.basecfc.queuedInstructions.keyArray();
    instructionOrder.sort( 'textNoCase' );

    // per object
    instructionOrder.each( function( entityGUID, idx ) {
      var objectInstructions = request.basecfc.queuedInstructions[ entityGUID ];

      if ( !request.basecfc.queuedObjects.keyExists( entityGUID ) ) { continue; }
      if ( !request.basecfc.instructionsOrder.keyExists( entityGUID ) ) { continue; }

      var object = request.basecfc.queuedObjects[ entityGUID ];
      var sortedCommands = sortCommands( request.basecfc.instructionsOrder[ entityGUID ] );

      // per command
      sortedCommands.each( function( command ) {
        var instructionsPerCommand = objectInstructions[ command ];

        // per value
        instructionsPerCommand.each( function( key, value ) {
          var logValue = isSimpleValue( value )
                ? value
                : isObject( value )
                  ? value.getName()
                  : '';
          var logMessage = 'called: [#entityGUID#] #object.getEntityName()#.#command#' & ( isNull( logValue ) ? '()' : '(#logValue#)' );
          var instructionTimer = getTickCount();

          // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ACTUAL GET/SET/REMOVE COMMANDS HERE ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
          try {
            invoke( object, command, [ isSimpleValue( value ) && value == 'null' ? javacast( 'null', 0 ) : value ] );
          } catch ( any e ) {
            basecfcLog( logMessage & " FAILED", "fatal" );
            rethrow;
          }

          if ( isDebugEnabled() ) {
            instructionTimer = getTickCount( ) - instructionTimer;
            var timerColor = instructionTimer > 50 ? ( instructionTimer > 250 ? 'red' : 'orange' ) : 'black';
            basecfcLog( logMessage & ' (t=#instructionTimer#, n=#idx++#)', 'fatal' );
            instructionTimers += instructionTimer;
          }
        });
      });

      if ( request.basecfc.keyExists( "validationService" ) ) {
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

            variables.instance.validationReport.append( {
              'type' = 'validation',
              'object' = obj,
              'field' = prop,
              'value' = problemValue,
              'datatype' = '',
              'message' = errorMessage,
              'detail' = '',
              'errortype' = 'validationServiceError.#err.getProperty()#'
            } );

            basecfcLog( errorMessage );
          }
        }
      }
    } );

    instructionOrder.each( function( entityGUID ) {
      if ( !request.basecfc.queuedObjects.keyExists( entityGUID ) ) { continue; }
      var object = request.basecfc.queuedObjects[ entityGUID ];
      if ( object.isNew() ) entitySave( object );
      ormEvictEntity( object.getEntityName(), object.getId() );
    } );

    if ( isDebugEnabled() ) {
      basecfcLog( '~~ finished queue in #instructionTimers#ms. ~~' );
    }
  }

  private void function outputQueue() {
    writeOutput( '<ul>' );
    request.basecfc.queuedInstructions.each(function( objId, obj, rest ){
      writeOutput( '<li>#objId#</li>' );
      writeOutput( '<ul>' );
      obj.each(function( fnname, fncall, rest ){
        fncall.each(function( key, value, rest ){
          writeOutput( '<li>#fnname#(#isObject(value)?'object':value#)</li>' );
        });
      });
      writeOutput( '</ul>' );
    });
    writeOutput( '</ul>' );
  }

  /**
  * TODO: function documentation
  */
  private array function sortCommands( required struct commands ) {
    var tmp = {
      'remCommands' = [],
      'setCommands' = [],
      'addCommands' = []
    };

    commands.each( function( command ) {
      tmp[ command.left( 3 ) & 'Commands' ].append( command );
    } );

    tmp.remCommands.sort( 'textnocase' );
    tmp.setCommands.sort( 'textnocase' );
    tmp.addCommands.sort( 'textnocase' );

    var result = [];

    result.append( tmp.remCommands, true );
    result.append( tmp.setCommands, true );
    result.append( tmp.addCommands, true );

    return result;
  }

  /**
  * Method to add instructions to the queue, which is later processed using
  * processQueue() overwriting previous instructions so no duplicate actions
  * are taking place
  */
  private void function queueInstruction( required component entity, required string command, required any value, numeric idx ) {
    param struct request.basecfc.instructionsOrder={}; // should be ordered, but cf11 doesn't have this feature.
    param struct request.basecfc.queuedInstructions={}; // should be ordered, but cf11 doesn't have this feature.
    param struct request.basecfc.queuedObjects={}; // should be ordered, but cf11 doesn't have this feature.

    if ( command == 'set__subclass' ) {
      return;
    }

    var entityGUID = entity.getEntityGUID();

    if ( !request.basecfc.queuedObjects.keyExists( entityGUID ) ) {
      request.basecfc.queuedObjects[ entityGUID ] = entity;
    }

    if ( !request.basecfc.instructionsOrder.keyExists( entityGUID ) ) {
      request.basecfc.instructionsOrder[ entityGUID ] = {}; // should be ordered, but cf11 doesn't have this feature.
    }

    if ( !request.basecfc.queuedInstructions.keyExists( entityGUID ) ) {
      request.basecfc.queuedInstructions[ entityGUID ] = {}; // should be ordered, but cf11 doesn't have this feature.
    }

    if ( !request.basecfc.queuedInstructions[ entityGUID ].keyExists( command ) ) {
      request.basecfc.queuedInstructions[ entityGUID ][ command ] = {}; // should be ordered, but cf11 doesn't have this feature.
    }

    if ( isObject( value ) ) {
      var valueID = value.getEntityGUID( );

      if ( isNull( valueID ) ) {
        var logMessage = "No ID set on entity #value.getName( )#";
        basecfcLog( logMessage, "fatal" );
        throw( logMessage, "basecfc.queueInstruction" );
      }

      // Adds multiple values:
      request.basecfc.queuedInstructions[ entityGUID ][ command ][ valueID ] = value;

      if ( !request.basecfc.instructionsOrder[ entityGUID ].keyExists( command ) ) {
        request.basecfc.instructionsOrder[ entityGUID ][ command ] = [ ];
      }

      var existingInstructionIndex = request.basecfc.instructionsOrder[ entityGUID ][ command ].findNoCase( valueID );

      if ( existingInstructionIndex && command.left( 3 ) != "add" ) {
        request.basecfc.instructionsOrder[ entityGUID ][ command ].deleteAt( existingInstructionIndex );
      }

      request.basecfc.instructionsOrder[ entityGUID ][ command ].append( valueID );
    } else {
      // Adds single value:
      request.basecfc.queuedInstructions[ entityGUID ][ command ].value = value;
      request.basecfc.instructionsOrder[ entityGUID ][ command ] = [ "value" ];
    }
  }

  /**
  * Takes a GUID or struct containing one and an entity name to construct a
  * component (or passes along the given component)
  */
  private boolean function luceeAcfIsInstanceOf( object, cfc ) {
    return isInstanceOf( object, server.keyExists( 'lucee' ) ? cfc.listLast( '.' ) : cfc );
  }

  /**
  * Takes a GUID or struct containing one and an entity name to construct a
  * component (or passes along the given component)
  */
  private any function toComponent( required any variable, required string entityName, required string cfc ) {
    writeOutput( '<br>called toComponent()' );

    var t = getTickCount();
    var parsedVar = variable;

    if ( isNull( parsedVar ) || isDeletedEntity( parsedVar ) ) return;

    try {
      if ( isObject( parsedVar ) && luceeAcfIsInstanceOf( parsedVar, cfc ) ) {
        if ( isDebugEnabled() ) writeOutput( '<br><b>toComponent()</b> => #cfc# - #getTickCount()-t#ms. (early exit)' );
        return parsedVar;
      }

      if ( isSimpleValue( parsedVar ) && len( trim( parsedVar ) ) ) {
        if ( isDebugEnabled() ) writeOutput( '<br><b>toComponent()</b> => parsedVar might be an ID: #parsedVar# - #getTickCount()-t#ms.' );

        if ( isValidPK( parsedVar ) ) {
          parsedVar = { "id" = parsedVar };
        } else if ( isJSON( parsedVar ) ) {
          parsedVar = deserializeJSON( parsedVar );
        } else {
          parsedVar = { "name" = parsedVar };
        }
      }

      if ( isStruct( parsedVar ) ) {
        if ( structIsEmpty( parsedVar ) ) {
          if ( isDebugEnabled() ) writeOutput( '<br><b>toComponent()</b> => empty struct - #getTickCount()-t#ms. (early exit)' );
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
        if ( isDebugEnabled() ) writeOutput( '<br><b>toComponent()</b> => objectToLink still null - #getTickCount()-t#ms. (early exit)' );

        if ( isDebugEnabled() ) {
          basecfcLog( "Creating new #entityName#." );
        }

        var objectToLink = entityNew( entityName );
        entitySave( objectToLink );
        var entityGUID = objectToLink.getEntityGUID();

        if ( !structKeyExists( request.basecfc.queuedObjects, entityGUID ) ) {
          request.basecfc.queuedObjects[ entityGUID ] = objectToLink;
        }
      }

      if ( isObject( objectToLink ) && luceeAcfIsInstanceOf( objectToLink, "basecfc.base" ) ) {
        if ( isDebugEnabled() ) writeOutput( '<br><b>toComponent()</b> => basecfc.base #getTickCount()-t#ms. (early exit)' );
        return objectToLink;
      }

      var logMessage = "Variable could not be translated to component of type #entityName#";
      basecfcLog( logMessage, "fatal" );
      throw( logMessage, "basecfc.toComponent" );
    } catch ( basecfc.toComponent e ) {
      if ( isDebugEnabled() ) {
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

      if ( isDebugEnabled() ) {
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

    if ( isDebugEnabled() ) writeOutput( '<br><b>toComponent()</b> #getTickCount()-t#ms.' );
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

    var instanceLevel = isNull( variables.instance.config.logLevel ) ? 'debug' : variables.instance.config.logLevel;

    var levelThreshold = arrayFindNoCase( this.logLevels, instanceLevel );

    if ( requestedLevel >= levelThreshold ) {
      writeLog( text = text, type = level, file = file );
    }

    if ( isDebugEnabled() ) {
      writeOutput( "<br />" & text );
    }
  }

  /**
  * the singular property name, if that exists, otherwise it returns
  * the default name
  */
  private string function propertyName( property ) {
    return property.keyExists( 'singularName' ) && property.singularName.trim().len() ? property.singularName : property.name;
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

  /**
  * The default fields are created/updated using other methods or not at all (in case of CF form fields like 'fieldnames')
  */
  private boolean function isDefaultField( required string fieldName ) {
    return arrayFindNoCase( variables.instance.defaultFields, fieldName );
  }

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
    if ( !canBeLogged( ) ) {
      return;
    }

    if ( variables.instance.entityName == 'logentry' ) {
      return;
    }

    var logAction = isNew() ? 'created' : 'changed';

    transaction {
      var logEntry = entityNew( 'logentry' );
      entitySave( logEntry );
      var logResult = logEntry.enterIntoLog( logAction, savedState, this );
    }

    basecfcLog( 'Added log entry for #getName()# (#logResult.getId()#).' );
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
  private array function getObjectsToOverride( formData, propertyName ) {
    var hql = '
      SELECT    otherEntity
      FROM      #variables.instance.entityName# thisEntity
                  JOIN thisEntity.#propertyName# otherEntity
      WHERE     thisEntity.id = :thisTablePK
    ';
    var params = { 'thisTablePK' = getId() };

    if ( structKeyExists( formData, 'remove_#propertyName#' ) ) {
      var entitiesToRemove = formData[ 'remove_#propertyName#' ];

      if ( !isArray( entitiesToRemove ) ) {
        entitiesToRemove = [ entitiesToRemove ];
      }

      var entitiesToRemoveAsIds = [];

      for ( var entityToRemove in entitiesToRemove ) {
        var asEntityGUId = entityToRemove;

        if ( isObject( entityToRemove ) && structKeyExists( entityToRemove, 'getId' ) ) {
          asEntityGUId = entityToRemove.getId();
        }

        if ( isValidPK( asEntityGUId ) ) {
          arrayAppend( entitiesToRemoveAsIds, asEntityGUId );
        }
      }

      if ( !entitiesToRemoveAsIds.isEmpty() ) {
        params[ 'otherTableIds' ] = entitiesToRemoveAsIds;
        hql &= ' AND otherEntity.id IN ( :otherTableIds )';
      }
    }

    try {
      return ormExecuteQuery( hql, params );
    } catch ( any e ) {
      throw( 'Error in query', 'basecfc.global', '#e.message# #e.detail# - SQL: #hql#, Params: #serializeJSON( params )#' );
    }
  }

  /**
  * Check if an ORM function call was already placed in the queue, no need to do that twice
  */
  private boolean function isObjectActionInQueue( fn, objectToLink ) {
    var entityGUId = getEntityGUID();

    var result = request.basecfc.queuedInstructions.keyExists( entityGUId ) && request.basecfc.queuedInstructions[ entityGUId ].keyExists( fn );

    if ( !isNull( objectToLink ) ) {
      writeOutput( '<br>#objectToLink.getEntityName()# - #objectToLink.getName()#' );
      return ( result && request.basecfc.queuedInstructions[ entityGUId ][ fn ].keyExists( objectToLink.getEntityGUID() ) );
    }

    return result;
  }

  private boolean function objectsAreadyLinked( component otherObj, struct property, string otherField, numeric depth ) {
    var t = getTickCount();

    // NB: lucee doesn't want a property in the has() function when called on a to-one relation, also, it's fucking slow.
    param property.fieldtype='';

    switch ( property.fieldtype ) {
      case 'one-to-one':
      case 'many-to-one':
        var linkeObjectHasthisObject = invoke( otherObj, 'has#otherField#' );
        if ( isDebugEnabled() ) writeOutput( '<br>objectsAreadyLinked() 1: #getTickCount()-t#ms. -> #linkeObjectHasthisObject#' );
        break;

      case 'one-to-many':
      case 'many-to-many':
        var linkeObjectHasthisObject = server.keyExists( 'lucee' )
          ? ormExecuteQuery( '
              SELECT COUNT(l.id) FROM #getEntityName()# l JOIN l.#property.name# r WHERE l.id = :thisId AND r.id = :otherId
            ', { 'thisId' = getId(), 'otherId' = otherObj.getId() }, { cacheable = false } ).first()
          : invoke( otherObj, 'has#otherField#', this );
        if ( isDebugEnabled() ) writeOutput( '<br>objectsAreadyLinked() 2: #getTickCount()-t#ms. -> #linkeObjectHasthisObject#' );
        break;
    }


    switch ( property.fieldtype ) {
      case 'one-to-one':
      case 'many-to-one':
        var thisObjectHasLinkedObject = invoke( this, 'has#propertyName( property )#' );
        if ( isDebugEnabled() ) writeOutput( '<br>objectsAreadyLinked() 3: #getTickCount()-t#ms. -> #linkeObjectHasthisObject#' );
        break;

      case 'one-to-many':
      case 'many-to-many':
        var linkeObjectHasthisObject = server.keyExists( 'lucee' )
          ? ormExecuteQuery( '
              SELECT COUNT(l.id) FROM #getEntityName()# l JOIN l.#property.name# r WHERE l.id = :otherId AND r.id = :thisId
            ', { 'thisId' = getId(), 'otherId' = otherObj.getId() }, { cacheable = false } ).first()
          : invoke( this, 'has#propertyName( property )#', otherObj );
        if ( isDebugEnabled() ) writeOutput( '<br>objectsAreadyLinked() 4: #getTickCount()-t#ms. -> #linkeObjectHasthisObject#' );
        break;
    }


    if ( isNull( thisObjectHasLinkedObject ) || isNull( linkeObjectHasthisObject ) ) return false;

    return thisObjectHasLinkedObject && linkeObjectHasthisObject;
  }

  /**
  * Basic presence check on the basecfc mandatory fields
  *  - name      every basecfc-entity has a name, so getName() can always be used (what you do with it is up to you)
  *  - deleted   basecfc-entities are not deleted, only marked as such
  *  - sortorder basecfc-entities always have a sortkey, if you don't use it, set it to 0.
  */
  private void function validateBaseProperties() {
    if ( !variables.keyExists( 'instance' ) || variables.instance.className == 'basecfc.base' || variables.instance.className == '' ) {
      return;
    }

    if ( !structKeyExists( variables.instance.properties, 'name' ) ||
         !structKeyExists( variables.instance.properties, 'deleted' ) ||
         !structKeyExists( variables.instance.properties, 'sortorder' ) ) {
      throw(
        'Missing essential properties in "#variables.instance.className#".',
        'basecfc.init.invalidPropertiesError',
        'Objects extending basecfc must have a name, deleted and sortorder property.'
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
      if ( !hasCreateContact() ) {
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

  private string function getORMBase() {
    return variables.instance.config.root & '.model';
  }

  private void function setup() {
    if ( !request.keyExists( 'allOrmEntities' ) ) return; // Application not set up for ORM
    if ( variables.keyExists( 'instance' ) && variables.instance.keyExists( 'className' ) ) return; // entity already set up

    param variables.name="";
    param variables.deleted=false;
    param variables.sortorder=0;

    variables.instance = {
      'entities' = {},
      'config' = {},
      'meta' = getMetadata(),
      'sanitationReport' = [],
      'validationReport' = []
    };

    if ( url.keyExists( 'clear' ) ) {
      var allCacheIds = cacheGetAllIds();
      if ( !allCacheIds.isEmpty() ) {
        cacheRemove( allCacheIds.toList(), false );
      }
    }

    param variables.instance.config.root="root";
    param variables.instance.config.log=false;
    param variables.instance.properties.id.type='';

    variables.instance[ 'className' ] = getClassName();
    variables.instance[ 'schema' ] = getSchemaName();
    variables.instance[ 'id' ] = getDefaultPK();
    variables.instance[ 'properties' ] = getInheritedProperties();
    variables.instance[ 'entityName' ] = getEntityName();
    variables.instance[ 'settings' ] = getInheritedSettings();
    variables.instance[ 'defaultFields' ] = getDefaultFields();

    // check to see if object has all basic properties (like name, deleted, sortorder)
    validateBaseProperties( );

    // overwrite instance variables:
    if ( request.keyExists( 'context' ) &&
         isStruct( request.context ) &&
         request.context.keyExists( 'config' ) &&
         isStruct( request.context.config ) ) {
      param request.context.config={};
      param request.context.config.log=false;
      param request.context.config.root="root";
      param request.context.config.disableSecurity=true;
      param request.context.config.logLevel="fatal";

      var appendRcToInstance = {
        'config' = {
          'log' = request.context.config.log,
          'root' = request.context.config.root,
          'disableSecurity' = request.context.config.disableSecurity,
          'logLevel' = request.context.config.logLevel
        }
      };

      variables.instance.append( appendRcToInstance, true );
    }

    variables.instance.append( arguments, true );

    param request.appName="basecfc";
  }

  private void function verifySetup() {
    if ( !variables.keyExists( 'instance' ) ) {
      var logMessage = 'Basecfc not initialised';
      basecfcLog( logMessage, 'fatal' );
      throw( logMessage, 'basecfc.global' );
    }
  }

  private boolean function isDeletedEntity( value ) {
    if ( isSimpleValue( value ) && value == 'null' ) return true;
    if ( isSimpleValue( value ) && value == '' ) return true;
    return false;
  }
}