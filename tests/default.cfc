component extends="testbox.system.BaseSpec" {
  function beforeAll(){
    addMatchers({
      toBeJSON = function( expectation, args={}){ return isJSON( expectation.actual ); }
    });

    ORMReload();
  }

  function afterEach(){
    ORMFlush();
  }

  function run(){
    describe( "Test helper methods.", function(){
      var obj = entityNew( "test" );

      it( "Expects toString() to return a json representation of the entity.", function() {
        expect( obj.toString())
          .toBeString()
          .notToBeNULL()
          .toBeJSON();
      });

      it( "Expects toString() to contain all properties of the entity.", function() {
        expect( obj.toString())
          .toInclude( '"sortorder"' )
          .toInclude( '"id"' )
          .toInclude( '"deleted"' )
          .toInclude( '"name"' );
      });

      it( "Expects hasProperty() to return true when the entity has the provided property and false when it doesn't.", function() {
        expect( obj.hasProperty( "name" ))
          .toBeBoolean()
          .toBeTrue();
        expect( obj.hasProperty( "droids" ))
          .toBeBoolean()
          .toBeFalse();
      });

      it( "Expects getInheritedProperties() to return a struct containing all inherited properties of the entity.", function() {
        expect( obj.getInheritedProperties())
          .toBeStruct()
          .toHaveKey( 'entitiesInSubfolder' )
          .toHaveKey( 'id' )
          .toHaveKey( 'name' )
          .toHaveKey( 'deleted' )
          .toHaveKey( 'sortorder' )
          .notToHaveKey( 'droid' );
      });

      it( "Expects getEntityName() to return the name of the entity.", function() {
        expect( obj.getEntityName())
          .toBeString()
          .toBe( "test" )
          .notToBe( "root.model.test" )
          .notToBe( "droid" );
      });

      it( "Expects getClassName() to return the full CFC name/path of the entity.", function() {
        expect( obj.getClassName())
          .toBeString()
          .toBe( "root.model.test" )
          .notToBe( "droid" )
          .notToBe( "test" );
      });

      it( "Expects getReverseField( cfc, fk ) to return the field linking two entities together.", function() {
        // test one-to-many
        expect( obj.getReverseField( "root.model.sub.other", "testid" ))
          .toBeString()
          .toBe( "entityInSubfolder" );

        // test many-to-one
        expect( obj.getReverseField( "root.model.more", "moreid" ))
          .toBeString()
          .toBe( "more" )
          .notToBe( "duplicate" );

        // test another link to same entity, different fk
        expect( obj.getReverseField( "root.model.more", "duplicateid" ))
          .toBeString()
          .toBe( "duplicate" )
          .notToBe( "more" );

        expect( function(){
          obj.getReverseField( "root.model.more", "notAnExistingFK" );
        }).toThrow( type="basecfc.getReverseField", regex="no reverse field found" );
      });
    });

    describe( "Test basic save function.", function(){
      var obj = entityNew( "test" );
      obj.save({ name="InvalidName" });
      entitySave( obj );

      it( "Expects save() to return the entity", function() {
        expect( obj.save())
          .toBeTypeOf( 'component' );
      });

      it( "Expects save({name='test'}) to change name (a string) to 'test'", function() {
        expect( obj.getName())
          .toBe( 'InvalidName' );

        var saveData = {
          name="test"
        };

        var alteredObj = obj.save( saveData );

        expect( alteredObj.getName())
          .toBe( 'test' )
          .notToBe( 'InvalidName' );
      });
    });

    describe( "Test save function with one-to-many relations.", function(){
      beforeEach( function( currentSpec ){
        obj = entityNew( "test" );
        obj.save({ name="InvalidName" });
        entitySave( obj );
      });

      afterEach(function( currentSpec ){
        structDelete( variables, "obj" );
      });

      it( "Expects save({add_data=obj}) to be able to add a one-to-many object using object", function(){
        var other = entityNew( "other" );
        entitySave( other );

        var saveData = {
          add_entityInSubfolder = other
        };

        var saved = obj.save( saveData );

        expect( saved.getEntitiesInSubfolder())
          .toBeArray()
          .toHaveLength( 1 );

        expect( saved.getEntitiesInSubfolder()[1] )
          .toBe( other );
      });

      it( "Expects save({add_data=123}) to be able to add a one-to-many object using pk", function(){
        var other = entityNew( "other" );
        entitySave( other );

        var saveData = {
          add_entityInSubfolder = other.getID()
        };

        var saved = obj.save( saveData );

        expect( saved.getEntitiesInSubfolder())
          .toBeArray()
          .toHaveLength( 1 );

        expect( saved.getEntitiesInSubfolder()[1] )
          .toBe( other );
      });

      it( "Expects save({add_data={id:123}}) to be able to add a one-to-many object using pk in struct", function(){
        var other = entityNew( "other" );
        entitySave( other );

        var saveData = {
          add_entityInSubfolder = { id = other.getID()}
        };

        var saved = obj.save( saveData );

        expect( saved.getEntitiesInSubfolder())
          .toBeArray()
          .toHaveLength( 1 );

        expect( saved.getEntitiesInSubfolder()[1] )
          .toBe( other );
      });

      it( "Expects save({add_data='{id:123}'}) to be able to add a one-to-many object using pk in json", function(){
        var other = entityNew( "other" );
        entitySave( other );

        var saveData = {
          add_entityInSubfolder = serializeJSON({ id = other.getID()})
        };

        var saved = obj.save( saveData );

        expect( saved.getEntitiesInSubfolder())
          .toBeArray()
          .toHaveLength( 1 );

        expect( saved.getEntitiesInSubfolder()[1] )
          .toBe( other );
      });

      it( "Expects save({add_data={name='test'}}) to be able to add a NEW one-to-many object", function(){
        var saveData = {
          add_entityInSubfolder = {
            name = "MyNewObject",
            moreother = {
              name = "testMore"
            }
          }
        };

        var saved = obj.save( saveData );

        expect( saved.getEntitiesInSubfolder())
          .toBeArray()
          .toHaveLength( 1 );

        expect( saved.getEntitiesInSubfolder()[1].getName() )
          .toBe( "MyNewObject" );
      });

      it( "Expects save({add_data=[data]}) to be able to add multiple one-to-many objects", function(){
        var first = entityNew( "other" );
        entitySave( first );
        first.getID();

        var second = entityNew( "other" );
        entitySave( second );
        second.getID();

        var saveData = {
          add_entityInSubfolder = [
            { id = first.getID()},
            second
          ]
        };

        var saved = obj.save( saveData );

        expect( saved.getEntitiesInSubfolder())
          .toBeArray()
          .toHaveLength( 2 );

        expect( saved.getEntitiesInSubfolder()[1] )
          .toBe( first );

        expect( saved.getEntitiesInSubfolder()[2] )
          .toBe( second );
      });

      it( "Expects save({set_data=[data]}) to replace all items in a one-to-many relation", function(){
        var first = entityNew( "other" ).save({name='first'});
        entitySave( first );
        var second = entityNew( "other" ).save({name='second'});
        entitySave( second );
        var third = entityNew( "other" ).save({name='third'});
        entitySave( third );

        var saveData = {
          entitiesInSubfolder = "#first.getID()#,#second.getID()#"
        };

        var saved = obj.save( saveData );

        expect( saved.getEntitiesInSubfolder())
          .toBeArray()
          .toHaveLength( 2 );
        expect( saved.getEntitiesInSubfolder()[1] )
          .toBe( first );
        expect( saved.getEntitiesInSubfolder()[2] )
          .toBe( second );

        ormFlush();

        var overwriteData = {
          entitiesInSubfolder = [ third ]
        };

        var newSave = obj.save( overwriteData );

        expect( newSave.getEntitiesInSubfolder())
          .toBeArray()
          .toHaveLength( 1 );
        expect( newSave.getEntitiesInSubfolder()[1] )
          .toBe( third );
      });
    });

    describe( "Test save function with many-to-one relations.", function(){
      beforeEach( function( currentSpec ){
        obj = entityNew( "test" );
        obj.save({ name="InvalidName" });
        entitySave( obj );
      });

      afterEach(function( currentSpec ){
        structDelete( variables, "obj" );
      });

      it( "Expects save({data=obj}) to be able to add a many-to-one object using object", function(){
        var more = entityNew( "more" );
        entitySave( more );

        var saveData = {
          more = more
        };

        var saved = obj.save( saveData );

        expect( saved.getMore())
          .toBe( more );
      });

      it( "Expects save({data=123}) to be able to add a many-to-one object using pk", function(){
        var more = entityNew( "more" );
        entitySave( more );

        var saveData = {
          more = more.getID()
        };

        var saved = obj.save( saveData );

        expect( saved.getMore())
          .toBe( more );
      });

      it( "Expects save({data={id=123}}) to be able to add a many-to-one object using pk in struct", function(){
        var more = entityNew( "more" );
        entitySave( more );

        var saveData = {
          more = { id = more.getID()}
        };

        var saved = obj.save( saveData );

        expect( saved.getMore())
          .toBe( more );
      });

      it( "Expects save({data='{id:123}'}) to be able to add a many-to-one object using pk in json", function(){
        var more = entityNew( "more" );
        entitySave( more );

        var saveData = {
          more = serializeJSON({ id = more.getID()})
        };

        var saved = obj.save( saveData );

        expect( saved.getMore())
          .toBe( more );
      });

      it( "Expects save({data={name='test'}}) to be able to add a NEW many-to-one object", function(){
        var saveData = {
          more = {
            name = "newMore",
            deeper = {
              name = "deeper"
            }
          }
        };

        var saved = obj.save( saveData );
        var more = saved.getMore();
        expect( more )
          .notToBeNULL();
        expect( more.getName())
          .toBe( "newMore" );

        // test the reverse link:
        var linkBack = more.getTests();
        expect( linkBack )
          .toBeArray()
          .toHaveLength( 1 );
        expect( linkBack[1] )
          .toBe( saved );

        // also check one level deeper:
        var deeper = more.getDeeper();
        expect( deeper.getName())
          .toBe( "deeper" );

        // test the reverse link:
        var deeperLinkBack = deeper.getMores();
        expect( deeperLinkBack )
          .toBeArray()
          .toHaveLength( 1 );
        expect( deeperLinkBack[1] )
          .toBe( more );
      });
    });
  }
}