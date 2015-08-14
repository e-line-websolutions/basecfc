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

component cacheuse="transactional" defaultSort="sortorder" mappedSuperClass=true hide=true {
  property name="id" fieldType="id" generator="uuid";
  property name="name" fieldType="column" type="string" length=128;
  property name="deleted" fieldType="column" ORMType="boolean" default=false;
  property name="sortorder" fieldType="column" ORMType="integer";

  variables.instance = {
    ormActions = {},
    debug = false,
    config = {
      log = false,
      disableSecurity = true
    }
  };

  if( structKeyExists( request, "context" ) && isStruct( request.context )){
    structAppend( variables.instance, request.context, true );
  }

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  public any function init(){
    return this;
  }

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  public string function toString(){
    var jsonified = deserializeJSON( serializeJSON( this ));
    structDelete( jsonified, "password" );
    return serializeJSON( jsonified );
  }

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  public array function getFieldsToDisplay( required type, struct formdata = {} ){
    var properties = getInheritedProperties();
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
            local.valueToDisplay = formdata[currentField];
          }

          if( !structKeyExists( local, "valueToDisplay" )){
            try{
              local.valueToDisplay = evaluate( "get" & currentField );
            }
            catch( any cfcatch ){}
          }

          if( structKeyExists( local, "valueToDisplay" ) && isObject( local.valueToDisplay )){
            local.valueToDisplay = local.valueToDisplay.getName();
          }

          param local.valueToDisplay = "";

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
  public boolean function hasProperty( required string propertyToCheck ){
    return structKeyExists( getInheritedProperties(), propertyToCheck );
  }

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  public struct function getInheritedProperties(){
    var meta = getMetaData( this );
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

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  public string function getEntityName( string className = getClassName()){
    var sessionFactory = ORMGetSessionFactory();
    var metaData = sessionFactory.getClassMetadata( listLast( className, '.' ));

    return metaData.getEntityName();
  }

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  public string function getClassName(){
    return listLast( getMetaData( this ).fullname, "." );
  }

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  public string function getReverseField( required string cfc,
                                          required string fkColumn,
                                          required string type,
                                          required string singular_or_plural="singular" ){
    var properties = structFindKey( getInheritedProperties(), "cfc", "all" );
    var field = 0;
    var fieldFound = false;

    if( !arrayLen( properties )){
      writeOutput( "ERROR: <b>#cfc#</b> not linked to any CFCs" );
      writeDump( getInheritedProperties());
      writeDump( arguments );
      abort;
    }

    for( var property in properties ){
      field = property.owner;

      if(!(
        (
          structKeyExists( field, "fkcolumn" ) &&
          field.fkColumn == fkColumn
        ) ||
        field.cfc == cfc
      )) {
        continue;
      }

      if( field.cfc == cfc ){
        fieldFound = true;
        break;
      }

      var testObj = createObject( cfc );

      if( isInstanceOf( testObj, field.cfc )){
        fieldFound = true;
        break;
      }

      if( testObj.getClassName() == field.cfc ){
        fieldFound = true;
        break;
      }
    }

    var propertyWithFK = structFindValue({ 'search' = properties }, fkColumn, 'all' );

    if( arrayLen( propertyWithFK ) == 1 ){
      field = propertyWithFK[1].owner;
      fieldFound = true;
    }

    if( !fieldFound ){
      // ERROR: no valid properties found in #listLast( local.meta.name, '.' )#
      writeDump( arguments );
      writeDump( getMetaData( this ));
      writeDump( properties );
      abort;
    }

    var result = field.name;

    if( singular_or_plural == "singular" && structKeyExists( field, 'singularName' )){
      result = field['singularName'];
    }


    return result;
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
  public any function save( struct formData = {},
                            struct calledBy = { entity = '', id = '' },
                            numeric depth = 0 ){
    var timer = getTickCount();
    var savedState = {};
    var meta = getMetaData( this );
    var entityName = this.getEntityName();
    var properties = getInheritedProperties();
    var canBeLogged = ( variables.instance.config.log && isInstanceOf( this, "root.model.logged" ));
    var uuid = createUUID();
    var defaultFields = "log,id,fieldnames,submitbutton,#entityName#id";
    var logFields = "createContact,createDate,createIP,updateContact,updateDate,updateIP";

    param formData.deleted = false;

    if( !structKeyExists( request, "basecfc-save" )){
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

    if( variables.instance.debug ){
      if( depth == 0 ){
        writeOutput( '<div class="basecfc-debug">' );
      }
      writeOutput( '<p>#depth# - #entityName#</p>' );
    }

    // Hard coded depth limit
    if( depth > 10 ){
      return;
    }

    if( canBeLogged && !( depth > 0 && isInstanceOf( this, "root.model.contact" ))){
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

    if( variables.instance.debug ){
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

    if( arrayLen( structFindValue( meta, "onMissingMethod" ))){
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
    for( var key in properties ){
      var property = properties[key];

      // Skip default fields (like buttons and PKs) and property not found in form or internal update fields
      if( // default field:
          listFindNoCase( defaultFields, key ) ||
          (
            // not in form
            !( structKeyExists( formdata, property.name )) &&
            // not added:
            !( structKeyExists( formData, "add_#property.name#" ) || ( structKeyExists( property, "singularName" ) && structKeyExists( formData, "add_#property.singularName#" ))) &&
            // not set:
            !( structKeyExists( formData, "set_#property.name#" )) &&
            // not removed:
            !( structKeyExists( formData, "remove_#property.name#" ) || ( structKeyExists( property, "singularName" ) && structKeyExists( formData, "remove_#property.singularName#" )))
          )
        )
      {
        continue;
      }

      var reverseCFCLookup = meta.name;

      if( listFindNoCase( logFields, key )){
        reverseCFCLookup = "root.model.logged";
      }

      param string property.fieldtype = "string";

      if( structKeyExists( property, "cfc" )){
        var propertyEntityName = getEntityName( property.cfc );
      }

      savecontent variable="local.debugoutput" {
        switch( property.fieldtype ){
          case "one-to-many":
          case "many-to-many":
            // ████████╗ ██████╗       ███╗   ███╗ █████╗ ███╗   ██╗██╗   ██╗
            // ╚══██╔══╝██╔═══██╗      ████╗ ████║██╔══██╗████╗  ██║╚██╗ ██╔╝
            //    ██║   ██║   ██║█████╗██╔████╔██║███████║██╔██╗ ██║ ╚████╔╝
            //    ██║   ██║   ██║╚════╝██║╚██╔╝██║██╔══██║██║╚██╗██║  ╚██╔╝
            //    ██║   ╚██████╔╝      ██║ ╚═╝ ██║██║  ██║██║ ╚████║   ██║
            //    ╚═╝    ╚═════╝       ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝

            // OVERRIDE to
            if( structKeyExists( formdata, property.name )){
              // Valid input:
              var inputType = "invalid";

              // a JSON var
              if( isJSON( formdata[property.name] )){
                inputType = "json";
              } else {
                if( isArray( formdata[property.name] )){
                  // list of JSON structs
                  formdata[property.name] = arrayToList( formdata[property.name] );
                }

                if( isJSON( "[#formdata[property.name]#]" )){
                  inputType = "multiple-json";
                } else {
                  // list of UUIDs
                  inputType = "uuid";
                }
              }

              formdata["set_#property.name#"] = "";

              for( var dataToSave in formdata[property.name] ){
                if( inputType == "uuid" ){
                  dataToSave = '{"id":"#dataToSave#"}';
                }

                formdata["set_#property.name#"] = listAppend( formdata["set_#property.name#"], dataToSave );
              }

              local.workData = formdata[property.name];
              structDelete( formdata, property.name );
            }

            // REMOVE
            if( structKeyExists( formdata, "set_#property.name#" ) || structKeyExists( formdata, "remove_#property.name#" )){
              local.query = "SELECT b FROM #entityName# a JOIN a.#property.name# b WHERE a.id = :id ";
              local.params = { "id" = getID() };

              if( structKeyExists( formdata, "remove_#property.name#" )){
                local.query &= " AND b.id IN ( :list )";
                local.params['list'] = listToArray( formdata['remove_#property.name#'] );
              }

              local.objectsToOverride = ORMExecuteQuery( local.query, local.params, { "cacheable" = true });

              for( var objectToOverride in local.objectsToOverride ){
                if( property.fieldType == "many-to-many" ){
                  local.reverseField = objectToOverride.getReverseField( reverseCFCLookup, property.inverseJoinColumn, property.fieldtype, 'singular' );

                  evaluate( "remove#local.reverseField#(this)" );

                  if( variables.instance.debug ){
                    writeOutput( '<p>objectToOverride.remove#local.reverseField#(this)</p>' );
                  }
                } else {
                  local.reverseField = objectToOverride.getReverseField( reverseCFCLookup, property.fkcolumn, property.fieldtype, 'plural' );

                  evaluate( "objectToOverride.set#local.reverseField#(javaCast('null',0))" );

                  if( variables.instance.debug ){
                    writeOutput( '<p>objectToOverride.set#local.reverseField#(javaCast(''null'',0))</p>' );
                  }
                }

                evaluate( "remove#property.singularName#(objectToOverride)" );

                if( variables.instance.debug ){
                  writeOutput( '<p>remove#property.singularName#(objectToOverride)</p>' );
                }
              }
            }

            // SET
            if( structKeyExists( formdata, "set_#property.name#" )){
              local.workData = deSerializeJSON( '[' & formdata["set_#property.name#"] & ']' );

              if( arrayLen( local.workData )){
                formdata["add_#property.singularName#"] = "";
              }

              for( var toAdd in local.workData ){
                if( !isJSON( toAdd )){
                  toAdd = serializeJSON( toAdd );
                }

                formdata["add_#property.singularName#"] = listAppend( formdata["add_#property.singularName#"], toAdd );
              }

              structDelete( formdata, "set_#property.name#" );
            }

            // ADD
            if( structKeyExists( formdata, "add_#property.singularName#" )){
              local.workData = deSerializeJSON( '[' & formdata["add_#property.singularName#"] & ']' );

              for( var updatedStruct in local.workData ){
                if( isJSON( updatedStruct )){
                  updatedStruct = deSerializeJSON( updatedStruct );
                }

                if( isStruct( updatedStruct ) && structKeyExists( updatedStruct, "id" )){
                  local.objectToLink = entityLoadByPK( propertyEntityName, updatedStruct.id );
                  structDelete( updatedStruct, "id" );
                }

                if( isNull( local.objectToLink )){
                  local.objectToLink = entityNew( propertyEntityName );
                  entitySave( local.objectToLink );
                }

                local.alreadyHasValue = evaluate( "has#property.singularName#(local.objectToLink)" );

                if( variables.instance.debug ){
                  writeOutput( '<p>this.has#property.singularName#( #local.objectToLink.getName()# #local.objectToLink.getID()# ) -> #local.alreadyHasValue#</p>' );
                }

                local.ormAction = "#getID()#_#local.objectToLink.getID()#";

                if( !local.alreadyHasValue && !structKeyExists( variables.instance.ormActions, local.ormAction )){
                  evaluate( "add#property.singularName#(local.objectToLink)" );

                  if( variables.instance.debug ){
                    writeOutput( '<p>add#property.singularName#(local.objectToLink)</p>' );
                    writeOutput( local.ormAction );
                  }

                  local.reverseField = local.objectToLink.getReverseField( reverseCFCLookup, property.fkcolumn, property.fieldtype, 'singular' );

                  if( property.fieldtype == "many-to-many" ){
                    updatedStruct['add_#local.reverseField#'] = '{"id":"#getID()#"}';
                    variables.instance.ormActions[local.ormAction] = property.name;
                  } else {
                    updatedStruct[local.reverseField] = getID();
                    variables.instance.ormActions[local.ormAction] = property.name;
                  }
                } else if( variables.instance.debug ){
                  writeOutput( '<p>skipped add#property.singularName#(local.objectToLink) - already did that once</p>' );
                }

                // Go down the rabbit hole:
                if( structCount( updatedStruct )){
                  if( variables.instance.debug ){
                    writeOutput( '<b>ADD .save()</b>' );
                  }

                  local.objectToLink = local.objectToLink.save(
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
            if( structKeyExists( local, "workData" )){
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

            // inline forms (todo: should remove this)
            if( structKeyExists( property, "inlineedit" ) &&
                ( structKeyExists( formdata, property.name ) ||
                  structKeyList( formdata ) contains '#property.name#_' ||
                  structKeyExists( formdata, "#property.name#id" ))){
              if( propertyEntityName == calledBy.entity ){
                // this prevents invinite loops
                local.inlineEntity = entityLoadByPK( "#calledBy.entity#", calledBy.id );
              } else {
                local.inlineEntity = evaluate( "get#property.name#" );

                if( variables.instance.debug ){
                  writeOutput( '<p>get#property.name#()</p>' );
                }

                if( isNull( local.inlineEntity )){
                  if( structKeyExists( formData, "#property.name#id" )){
                    local.inlineEntity = entityLoadByPK( propertyEntityName, formData["#property.name#id"] );
                  }

                  if( isNull( local.inlineEntity )){
                    local.inlineEntity = entityNew( propertyEntityName );
                    entitySave( local.inlineEntity );
                  }
                }

                local.inlineEntityParameters = {};

                for( var formField in formData ){
                  if( listLen( formField, '_' ) gte 2 && listFirst( formField, "_" ) == property.name ){
                    local.inlineEntityParameters[listRest( formField, "_" )] = formData[formField];
                  }
                }

                if( structKeyExists( formdata, property.name ) &&
                    isJSON( formdata[property.name] ) &&
                    !structCount( local.inlineEntityParameters )){
                  local.inlineEntityParameters = deSerializeJSON( formdata[property.name] );
                }
              }

              formdata[property.name] = local.inlineEntity.getID();
            }

            // save value and link objects together
            if( structKeyExists( formdata, property.name )){
              local.value = formdata[property.name];
              local.valueToLog = left( local.value, 255 );

              if( structKeyExists( property, "cfc" )){
                // LINK TO OTHER OBJECT (USING PROVIDED ID)
                if( structKeyExists( local, "inlineEntity" )){
                  local.obj = local.inlineEntity;
                  structDelete( local, "inlineEntity" );
                } else if( len( trim( local.value ))) {
                  local.obj = entityLoadByPK( propertyEntityName, local.value );
                }

                if( !isNull( local.obj )){
                  if( !structKeyExists( local, "inlineEntityParameters" )){
                    local.inlineEntityParameters = {};
                  }

                  local.inlineEntityParameters["#propertyEntityName#id"] = local.obj.getID();
                  local.reverseField = local.obj.getReverseField( reverseCFCLookup, property.fkcolumn, property.fieldtype, 'singular' );
                  local.alreadyHasValue = evaluate( "local.obj.has#local.reverseField#(this)" );

                  if( variables.instance.debug ){
                    writeOutput( '<p>local.obj.has#local.reverseField#( #getID()# ) -> #local.alreadyHasValue#</p>' );
                  }

                  local.ormAction = "#getID()#_#local.obj.getID()#";

                  if( !local.alreadyHasValue && !structKeyExists( variables.instance.ormActions, local.ormAction )){
                    if( variables.instance.debug ){
                      writeOutput( local.ormAction );
                    }

                    local.inlineEntityParameters['add_#local.reverseField#'] = '{"id":"#getID()#"}';
                    variables.instance.ormActions[local.ormAction] = property.name;
                  } else if( variables.instance.debug ){
                    writeOutput( '<p>skipped add_#local.reverseField# - already did that once</p>' );
                  }

                  if( structCount( local.inlineEntityParameters )){
                    if( variables.instance.debug ){
                      writeOutput( '<b>.save()</b>' );
                    }

                    try{
                      local.obj.save( depth = ( depth + 1 ), calledBy = { entity = entityName, id = getID()}, formData = local.inlineEntityParameters );
                    } catch( any cfcatch ) {
                      if( variables.instance.debug ){
                        writeDump( local.inlineEntityParameters );
                        writeDump( cfcatch );
                        abort;
                      } else {
                        throw( cfcatch.message );
                      }
                    }
                  }

                  local.valueToLog = local.obj.getName();
                  local.value = local.obj;

                  structDelete( local, "obj" );
                  structDelete( local, "inlineEntityParameters" );
                } else {
                  local.valueToLog = "removed";
                  structDelete( local, "value" );
                }
              } else {
                // SIMPLE VALUE
                // make sure integers are saved as that:
                if( structKeyExists( property, "ORMType" )){
                  if( property.ORMType == "int" || property.ORMType == "integer" ){
                    local.value = int( val( local.value ));
                  }

                  if( property.ORMType == "float" ){
                    local.value = val( local.value );
                  }
                }
              }

              local.fn = "set" & property.name;

              if( !isNull( local.value )){
                if( variables.instance.debug ){
                  var dbugAttr = local.value.toString();
                  if( isJSON( dbugAttr )){
                    writeOutput( '<p>#local.fn#() with:</p>' );
                    writeOutput( '<code class="prettyprint">#replace( dbugAttr, ',', ', ', 'all' )#</code>' );
                  } else {
                    writeOutput( '<p>#local.fn#( #dbugAttr# )</p>' );
                  }
                }

                evaluate( "this.#local.fn#(local.value)" );
              } else {
                if( variables.instance.debug ){
                  writeOutput( '<p>#local.fn#( NULL )</p>' );
                }

                evaluate( "this.#local.fn#(javaCast('null',0))" );
              }
            }
        }
      }

      if( variables.instance.debug ){
        var colID = createUuid();
        var collapseCol = "document.getElementById('#colID#').style.display=(document.getElementById('#colID#').style.display==''?'none':'');";
        writeOutput( '
          <tr>
            <th width="15%" valign="top" align="right" onclick="#collapseCol#">#key#</th>
            <td width="85%" id="#colID#">#len( trim( local.debugoutput )) ? local.debugoutput : 'no action'#</td>
          </tr>
        ' );
      }

      if( structKeyExists( local, "valueToLog" )){
        if( not listFindNoCase( logFields, property.name )){
          savedState[property.name] = local.valueToLog;
        }
        structDelete( local, "valueToLog" );
      }
    }

    if( variables.instance.debug ){
      writeOutput( '
        </table>
      </div>
      ' );
    }

    if( depth == 0 &&
        canBeLogged &&
        entityName neq "logentry" ){
      var logFormData = {
            entity = this.getID(),
            deleted = false
          };

      if( structKeyExists( form, "logentry_note" )){
        logFormData.note = form.logentry_note;
      }

      if( structKeyExists( form, "logentry_attachment" )){
        logFormData.attachment = form.logentry_attachment;
      }

      var logentry = entityNew( "logentry" );
      entitySave( logentry );

      variables.instance.log = logentry
        .save( logFormData )
        .enterIntoLog( "changed", savedState );
    }

    if( variables.instance.debug ){
      writeOutput( getTickCount() - timer & "ms" );
    }

    if( depth == 0 && variables.instance.debug ){
      writeOutput( '<code class="prettyprint">#replace( serializeJSON( variables.instance.ormActions ), ',', ', ', 'all' )#</code></div>' );
    }

    return this;
  }

  public array function list(){
    param arguments.d           = 0;// rc.d(escending) default false (ASC)
    param arguments.filterType  = "contains";
    param arguments.maxResults  = 30;
    param arguments.offset      = 0;
    param arguments.orderby     = "";
    param arguments.startsWith  = "";

    param array arguments.filters = [];
    param boolean arguments.showdeleted = 0;

    var HQL = "";
    var columnName = "";
    var columnsInList = [];
    var defaultSort = "";
    var entityName = getEntityName();
    var entityProperties = getMetaData( this );
    var indexNr = 0;
    var orderByString = "";
    var properties = getInheritedProperties();
    var queryOptions = { ignorecase = true, maxResults = maxResults, offset = offset };

    if( structKeyExists( entityProperties, "defaultSort" )){
      defaultSort = entityProperties.defaultSort;
    } else if( structKeyExists( entityProperties.extends, "defaultSort" )){
      defaultSort = entityProperties.extends.defaultSort;
    }

    if( len( trim( orderby ))){
      var vettedOrderByString = "";

      for( var orderField in listToArray( orderby )){
        if( orderField contains ';' ){
          continue;
        }

        if( orderField contains ' ASC' || orderField contains ' DESC' ){
          orderField = listFirst( orderField, ' ' );
        }

        if( structKeyExists( properties, orderField )){
          local.vettedOrderByString = listAppend( local.vettedOrderByString, orderField );
        }
      }

      orderby = local.vettedOrderByString;

      if( len( trim( orderby ))){
        defaultSort = orderby & ( d ? ' DESC' : '' );
      }
    }

    orderby = replaceNoCase( defaultSort, ' ASC', '', 'all' );
    orderby = replaceNoCase( orderby, ' DESC', '', 'all' );

    if( defaultSort contains ' DESC' ){
      d = 1;
    } else if( defaultSort contains ' ASC' ){
      d = 0;
    }

    for( var orderByPart in listToArray( defaultSort )){
      orderByString = listAppend( orderByString, "mainEntity.#orderByPart#" );
    }

    if( len( trim( startsWith ))){
      filters = [{
        "field" = "name",
        "filterOn" = replace( startsWith, '''', '''''', 'all' )
      }];
      filterType = "starts-with";
    }

    if( arrayLen( filters )){
      var alsoFilterKeys = structFindKey( properties, 'alsoFilter' );
      var alsoFilterEntity = "";
      var whereBlock = " WHERE 0 = 0 ";
      var whereParameters = {};
      var counter = 0;

      if( showdeleted == 0 ){
        whereBlock &= " AND ( mainEntity.deleted IS NULL OR mainEntity.deleted = false ) ";
      }

      for( var filter in filters ){
        if( len( filter.field ) > 2 && right( filter.field, 2 ) == "id" ){
          whereBlock &= "AND mainEntity.#left( filter.field, len( filter.field ) - 2 )# = ( FROM #left( filter.field, len( filter.field ) - 2 )# WHERE id = :where_id )";
          whereParameters["where_id"] = filter.filterOn;
        } else {
          if( filter.filterOn == "NULL" ){
            whereBlock &= " AND ( ";
            whereBlock &= " mainEntity.#lCase( filter.field )# IS NULL ";
          } else if( structKeyExists( properties[filter.field], "cfc" )){
            whereBlock &= " AND ( ";
            whereBlock &= " mainEntity.#lCase( filter.field )#.id = :where_#lCase( filter.field )# ";
            whereParameters["where_#lCase( filter.field )#"] = filter.filterOn;
          } else {
            if( filterType == "contains" ){
              filter.filterOn = "%#filter.filterOn#";
            }

            filter.filterOn = "#filter.filterOn#%";

            whereBlock &= " AND ( ";
            whereBlock &= " mainEntity.#lCase( filter.field )# LIKE :where_#lCase( filter.field )# ";
            whereParameters["where_#lCase( filter.field )#"] = filter.filterOn;
          }

          for( var alsoFilterKey in alsoFilterKeys ){
            if( alsoFilterKey.owner.name neq filter.field ){
              continue;
            }

            counter++;
            alsoFilterEntity &= " LEFT JOIN mainEntity.#listFirst( alsoFilterKey.owner.alsoFilter, '.' )# AS entity_#counter# ";
            whereBlock &= " OR entity_#counter#.#listLast( alsoFilterKey.owner.alsoFilter, '.' )# LIKE '#filter.filterOn#' ";
            whereParameters["where_#listLast( alsoFilterKey.owner.alsoFilter, '.' )#"] = filter.filterOn;
          }
          whereBlock &= " ) ";
        }
      }

      if( structKeyExists( entityProperties, "where" ) && len( trim( entityProperties.where ))){
        whereBlock &= entityProperties.where;
      }

      var HQLcounter  = " SELECT COUNT( mainEntity ) AS total ";
      var HQLselector  = " SELECT mainEntity ";

      HQL = "";
      HQL &= " FROM #lCase( entityName )# mainEntity ";
      HQL &= alsoFilterEntity;
      HQL &= whereBlock;

      HQLcounter = HQLcounter & HQL;
      HQLselector = HQLselector & HQL;

      if( len( trim( orderByString ))){
        HQLselector &= " ORDER BY #orderByString# ";
      }

      alldata = ORMExecuteQuery( HQLselector, whereParameters, queryOptions );

      if( arrayLen( alldata ) > 0 ){
        recordCounter = ORMExecuteQuery( HQLcounter, whereParameters, { ignorecase = true })[1];
      }
    } else {
      HQL = " FROM #lCase( entityName )# mainEntity ";

      if( showDeleted ){
        HQL &= " WHERE mainEntity.deleted = TRUE ";
      } else {
        HQL &= " WHERE ( mainEntity.deleted IS NULL OR mainEntity.deleted = FALSE ) ";
      }

      if( len( trim( orderByString ))){
        HQL &= " ORDER BY #orderByString# ";
      }

      try{
        alldata = ORMExecuteQuery( HQL, {}, queryOptions );
      } catch( any e ) {
        writeDump( e );
        abort;
        alldata = [];
      }

      if( arrayLen( alldata ) > 0 ){
        recordCounter = ORMExecuteQuery( "SELECT COUNT( e ) AS total FROM #lCase( entityName )# AS e WHERE e.deleted != :deleted", { "deleted" = true }, { ignorecase = true })[1];
        deleteddata = ORMExecuteQuery( "SELECT COUNT( mainEntity.id ) AS total FROM #lCase( entityName )# AS mainEntity WHERE mainEntity.deleted = :deleted", { "deleted" = true } )[1];

        if( showdeleted ){
          recordCounter = deleteddata;
        }
      }
    }

    return alldata;
  }
}