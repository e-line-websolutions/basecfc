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
  property name="name" type="string" length=128;
  property name="deleted" ORMType="boolean" default=false;
  property name="sortorder" ORMType="integer";

  param request.appName="basecfc"; // hash( getBaseTemplatePath())

  variables.sep = server.os.name contains 'Windows' ? '\' : '/';

  /** The constructor needs to be called in order to populate the instance
    * variables (like instance.meta which is used by the other methods)
    */
  public any function init() {
    variables.instance = {
      "config" = { "log" = false, "disableSecurity" = true },
      "debug" = false,
      "meta" = getMetaData(),
      "entities" = {},
      "properties" = {},
      "id" = createUUID(),
      "new" = false
    };

    variables.instance.properties = getInheritedProperties();

    try{
      var allEntities = ORMGetSessionFactory().getAllClassMetadata();

      for( var key in allEntities ) {
        var entity = allEntities[key];
        structInsert( variables.instance.entities, key, entity.getEntityName());
      }
    } catch( any e ) {}

    if( structKeyExists( request, "context" ) && isStruct( request.context )) {
      structAppend( variables.instance, request.context, true );
    }

    structAppend( variables.instance, arguments, true );

    return this;
  }

  /** This persists objects extending this base cfc into a database using ORM
    * It goes through all passed fields and updates all linked objects recursively
    *
    * @formData The data structure containing the new data to be saved
    * @depth Used to prevent inv. loops (don't keep going infinitely)
    */
  public any function save( required struct formData={}, numeric depth=0 ) {
    // Hard coded depth limit
    if( depth > 10 ) {
      if( variables.instance.debug ) {
        writeDump( request.basecfc.queuedInstructions );
        abort;
      }

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
      request.basecfc.queuedObjects = { "#variables.instance.id#" = this };
    }

    for( var logField in listToArray( logFields )) {
      structDelete( formData, logField );
    }

    if( canBeLogged && ( depth == 0 || entityName == "logentry" )) {
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
    }

    if( variables.instance.debug ) {
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
        writeLog( text = "~~~ start basecfc.save() ~~~", file = request.appName );
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
    if( arrayLen( structFindValue( variables.instance.meta, "onMissingMethod" ))) {
      for( var key in structKeyArray( formData )) {
        if( !structKeyExists( inheritedProperties, key ) && !listFindNoCase( defaultFields, key )) {
          structInsert( inheritedProperties, key, { "name" = key, "jsonData" = true }, true );
        }
      }
    }

    // SAVE VALUES PASSED VIA FORM
    for( var key in inheritedProperties ) {
      var property = inheritedProperties[key];
      var valueToLog = "";

      if( structKeyExists( property, "removeFromFormdata" ) && property.removeFromFormdata ) {
        continue;
      }

      // WARNING UGLY IF STATEMENT COMING UP
      // Skip default fields (like buttons and PKs) and property not found in form or internal update fields
      if(
          // default field:
          listFindNoCase( defaultFields, key ) || (

            // not in form
            !structKeyExists( formdata, property.name ) &&

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
          )
        ) {
        continue;
      }

      var debugoutput = "";

      savecontent variable="debugoutput" {
        param string property.fieldtype="string";

        if( structKeyExists( property, "cfc" )) {
          var reverseCFCLookup = listFindNoCase( logFields, key ) ? "root.model.logged" : getClassName();
        }

        switch( property.fieldtype ) {
          case "one-to-many":
          case "many-to-many":
            //   ___                  _____           __  __
            //  / _ \  _ _   ___  ___|_   _|___  ___ |  \/  | __ _  _ _  _  _
            // | (_) || ' \ / -_)|___| | | / _ \|___|| |\/| |/ _` || ' \| || |
            //  \___/ |_||_|\___|      |_| \___/     |_|  |_|\__,_||_||_|\_, |
            //                                                           |__/

            // Alias for set_ which overwrites linked data with new data
            if( structKeyExists( formdata, property.name )) {
              formdata["set_#property.name#"] = formdata[property.name];
            }

            // REMOVE
            if( structKeyExists( formdata, "set_#property.name#" ) || structKeyExists( formdata, "remove_#property.name#" )) {
              var query = "SELECT b FROM #entityName# a JOIN a.#property.name# b WHERE a.id = :id ";
              var params = { "id" = getID()};

              if( structKeyExists( formdata, "remove_#property.name#" )) {
                query &= " AND b.id IN ( :list )";
                params["list"] = listToArray( formdata["remove_#property.name#"] );
              }

              try {
                var objectsToOverride = ORMExecuteQuery( query, params );
              } catch( any e ) {
                throw( type = "basecfc.global",
                       message = "Error in query: " & query,
                       detail = "Params: #serializeJSON( params )#" );
              }

              for( var objectToOverride in objectsToOverride ) {
                if( property.fieldType == "many-to-many" ) {
                  var reverseField = objectToOverride.getReverseField( reverseCFCLookup, property.inverseJoinColumn );
                  queueInstruction( objectToOverride, objectToOverride.getID(), "remove#reverseField#", this );
                } else {
                  var reverseField = objectToOverride.getReverseField( reverseCFCLookup, property.fkcolumn, false );
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
                  if( !isJSON( toAdd ) && !isObject( toAdd )) {
                    toAdd = serializeJSON( toAdd );
                  }

                  arrayAppend( entitiesToAdd, toAdd );
                }

                formdata["add_#property.singularName#"] = entitiesToAdd;
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
                  for( var itemID in listToArray( itemList )) {
                    arrayAppend( workData, { "id" = itemID });
                  }
                }
              }

              if( !isArray( workData )) {
                workData = [ workData ];
              }

              for( var nestedData in workData ) {
                var objectToLink = toComponent( nestedData, property.entityName );

                if( !isNull( objectToLink )) {
                  if( structKeyExists( request.basecfc.queuedInstructions, getID()) &&
                      structKeyExists( request.basecfc.queuedInstructions[getID()], "add#property.singularName#" ) &&
                      structKeyExists( request.basecfc.queuedInstructions[getID()]["add#property.singularName#"], objectToLink.getID())) {
                    continue; // already queued
                  }

                  queueInstruction( this, getID(), "add#property.singularName#", objectToLink );

                  var fkColumn = property.fieldtype == "many-to-many" ? property.inverseJoinColumn : property.fkcolumn;
                  var reverseField = objectToLink.getReverseField( reverseCFCLookup, fkColumn );

                  if( evaluate( "has#property.singularName#(objectToLink)" ) &&
                      evaluate( "objectToLink.has#reverseField#(this)" )) {
                    continue; // alread in object
                  }

                  var updateStruct = parseUpdateStruct( nestedData );

                  if( property.fieldtype == "many-to-many" ) {
                    reverseField = "add_#reverseField#";
                  }

                  updateStruct[reverseField] = this;

                  if( isNew()) {
                    updateStruct["#property.entityName#id"] = objectToLink.getID();
                  }

                  if( variables.instance.debug ) {
                    writeLog( text = "called: #property.entityName#.save(#depth+1#)", file = request.appName );
                  }

                  // Go down the rabbit hole:
                  var value = objectToLink.save(
                    depth = ( depth + 1 ),
                    formData = updateStruct
                  );

                }
              }

              structDelete( formdata, "add_#property.singularName#" );
            }

            break;
          default:
            //  __  __                       _____            ___
            // |  \/  | __ _  _ _  _  _  ___|_   _|___  ___  / _ \  _ _   ___
            // | |\/| |/ _` || ' \| || ||___| | | / _ \|___|| (_) || ' \ / -_)
            // |_|  |_|\__,_||_||_|\_, |      |_| \___/      \___/ |_||_|\___|
            //                     |__/
            if( structKeyExists( formdata, property.name )) {
              // save value and link objects together
              var fn = "set" & property.name;
              var value = formdata[property.name];

              if( structKeyExists( property, "cfc" )) {
                var objectToLink = toComponent( value, property.entityName );
                var updateStruct = parseUpdateStruct( value );

                structDelete( local, "value" );

                if( !isNull( objectToLink )) {
                  if( structKeyExists( request.basecfc.queuedInstructions, getID()) &&
                      structKeyExists( request.basecfc.queuedInstructions[getID()], fn )) {
                    continue; // already queued
                  }

                  queueInstruction( this, getID(), fn, objectToLink );

                  var reverseField = objectToLink.getReverseField( reverseCFCLookup, property.fkcolumn );

                  if( evaluate( "objectToLink.has#reverseField#(this)" )) {
                    continue; // already in object
                  }

                  updateStruct["add_#reverseField#"] = this;

                  if( isNew()) {
                    updateStruct["#property.entityName#id"] = objectToLink.getID();
                  }

                  if( variables.instance.debug ) {
                    writeLog( text = "called: #property.entityName#.save(#depth+1#)", file = request.appName );
                  }

                  var value = objectToLink.save(
                    depth = ( depth + 1 ),
                    formData = updateStruct
                  );

                  valueToLog = value.getName();
                } else {
                  valueToLog = "removed";
                }
              } else if( isSimpleValue( value )) {
                // check inside json obj to see if an ID was passed in
                try {
                  var testForJSON = deserializeJSON( value );
                  if( isStruct( testForJSON ) && structKeyExists( testForJSON, "id" )) {
                    value = testForJSON.id;
                  }
                } catch( any e ) {
                }

                // make sure integers are saved as that:
                if( structKeyExists( property, "ORMType" )) {
                  if( property.ORMType == "int" || property.ORMType == "integer" ) {
                    value = int( val( value ));
                  } else if( property.ORMType == "float" ) {
                    value = val( value );
                  }
                }

                queueInstruction( this, getID(), fn, value );

                valueToLog = left( value, 255 );
              }

              if( !isNull( value )) {
                if( variables.instance.debug ) {
                  var dbugAttr = value.toString();

                  if( structKeyExists( local, "updateStruct" )) {
                    dbugAttr = serializeJSON( updateStruct );
                  }

                  if( isJSON( dbugAttr ) && !isBoolean( dbugAttr ) && !isNumeric( dbugAttr )) {
                    dbugAttr = '<code class="prettyprint">#replace( dbugAttr, ',', ',<br />', 'all' )#</code>';
                  }

                  writeOutput( '<p>#fn#( #dbugAttr# )</p>' );
                }
              } else {
                queueInstruction( this, getID(), fn, "null" );

                if( variables.instance.debug ) {
                  writeOutput( '<p>#fn#( null )</p>' );
                }
              }

              structDelete( local, "objectToLink" );
              structDelete( local, "updateStruct" );
              structDelete( local, "value" );
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
        var logAction = ( structKeyExists( formData, "#getEntityName()#id" ) && formData["#getEntityName()#id"] == getID()) ?
              "changed" :
              "created";

        var logentry = entityNew( "logentry" )
              .init()
              .enterIntoLog( logAction, savedState, this );

        entitySave( logentry );
      }

      processQueue();
    }

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
        for( var property in meta.properties ) {
          if( structKeyExists( property, "cfc" )) {
            result[property.name]["entityName"] = getEntityName( property.cfc );
          }

          for( var field in property ) {
            result[property.name][field] = property[field];
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
    var basicEntityName = listLast( className, '.' );

    if( structKeyExists( variables.instance.entities, basicEntityName )) {
      return variables.instance.entities[basicEntityName];
    }

    return basicEntityName;
  }

  /** returns the full cfc path
    */
  public string function getClassName() {
    var start = findNoCase( '#variables.sep#model#variables.sep#', variables.instance.meta.path );
    if( start > 0 ) {
      return "root" & replace( replace( mid( variables.instance.meta.path, start, len( variables.instance.meta.path )), '.cfc', '', 'one' ), variables.sep, '.', 'all' );
    }

    return variables.instance.meta.fullname;
  }

  /** find the corresponding field in the joined object (using the FKColumn)
    */
  public string function getReverseField( required string cfc, required string fkColumn, boolean singular=true ) {
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

  /** Overrid default getter to generate a GUID to identify this object with.
    */
  public string function getID() {
    return isNew() ? variables.instance.id : variables.id;
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

  //  ___       _             _          __  __       _    _             _
  // | _ \ _ _ (_)__ __ __ _ | |_  ___  |  \/  | ___ | |_ | |_   ___  __| | ___
  // |  _/| '_|| |\ V // _` ||  _|/ -_) | |\/| |/ -_)|  _|| ' \ / _ \/ _` |(_-<
  // |_|  |_|  |_| \_/ \__,_| \__|\___| |_|  |_|\___| \__||_||_|\___/\__,_|/__/

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
  private void function queueInstruction( required component entity, required string id, required string command, required any value ) {
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

    if( isObject( value )) {
      var valueID = value.getID();

      if( isNull( valueID )) {
        var logMessage = "No ID set on entity #value.getName()#";
        writeLog( text = logMessage, type = "fatal", file = request.appName );
        throw( type = "basecfc.queueInstruction", message = logMessage );
      }

      // Adds multiple values:
      request.basecfc.queuedInstructions[id][command][valueID] = value;

      if( !structKeyExists( request.basecfc.instructionsOrder[id], command )) {
        request.basecfc.instructionsOrder[id][command] = [];
      }

      var existingInstructionIndex = arrayFindNoCase( request.basecfc.instructionsOrder[id][command], valueID);

      if( existingInstructionIndex && left( command, 3 ) != "add" ) {
        arrayDeleteAt( request.basecfc.instructionsOrder[id][command], existingInstructionIndex );
      }

      if( left( command, 6 ) == "remove" ) {
        arrayPrepend( request.basecfc.instructionsOrder[id][command], valueID);
      } else {
        arrayAppend( request.basecfc.instructionsOrder[id][command], valueID);
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

  /** Preps string before validating it as GUID */
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

  /** Takes a GUID or struct containing one and an entity name to construct a
    * component (or passes along the given component)
    */
  private component function toComponent( required any variable, required string entityName ) {
    try {
      if( isObject( variable ) && variable.getEntityName() == entityName ) {
        return variable.init();
      } else {
        if( isSimpleValue( variable ) && isGUID( variable )) {
          variable = { "id" = variable };
        }

        if( isSimpleValue( variable ) && len( trim( variable )) && isJSON( variable )) {
          variable = deserializeJSON( variable );
        }

        if( isStruct( variable )) {
          var pk = "";
          if( structKeyExists( variable, "#entityName#id" )) {
            pk = variable["#entityName#id"];
          } else if( structKeyExists( variable, "id" )) {
            pk = variable["id"];
          }

          if( isGUID( pk )) {
            var objectToLink = entityLoadByPK( entityName, pk );
          }
        }

        if( isNull( objectToLink )) {
          var objectToLink = entityNew( entityName );
          entitySave( objectToLink );
        }

        if( isObject( objectToLink )) {
          // must init object so meta data is set:
          return objectToLink.init();
        }
      }

      var logMessage = "Variable could not be translated to component of type #entityName#";
      writeLog( text = logMessage, type = "fatal", file = request.appName );
      throw( type = "basecfc.toComponent", message = logMessage );
    } catch( basecfc.toComponent e ) {
      if( variables.instance.debug ) {
        writeDump( arguments );
        writeDump( e );
        abort;
      }

      rethrow;
    } catch( any e ) {
      if( variables.instance.debug ) {
        writeDump( arguments );
        writeDump( e );
        abort;
      }

      var logMessage = "An unexpected error occured while looking for an entity of type #entityName#";
      writeLog( text = logMessage, type = "fatal", file = request.appName );
      throw( type = "basecfc.toComponent", message = logMessage );
    }
  }

  /** Returns a simplified representation of the object
    * By Adam Tuttle ( http://fusiongrokker.com/post/deorm ).
    * @data One or more entities to be converted to a less complex representation
    */
  private any function deORM( required any data ) {
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

  /** Parses a JSON string into a struct (or passes through the given struct)
   */
  private struct function parseUpdateStruct( required any data ) {
    var result = {};

    if( isSimpleValue( data ) && len( trim( data )) && isJSON( data )) {
      var tempValue = deserializeJSON( data );
      if( isStruct( tempValue )) {
        data = tempValue;
      }
    }

    if( isStruct( data )) {
      result = duplicate( data );
    }

    return result;
  }

  /** Compares two component instances wither by ID or by using Java's equals()
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

  /** Determines whether this is a new object (without an ID) or an existing one
    */
  private boolean function isNew() {
    variables.instance.new = ( !structKeyExists( variables, "id" ) || isNull( variables.id ) || !len( trim( variables.id )));

    return variables.instance.new;
  }
}