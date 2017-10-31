component extends="testbox.system.BaseSpec" {
  variables.bf = new framework.ioc( [ "/mustang/services" ], { "constants" = { "config" = { } } } );
  variables.dataService = bf.getBean( "dataService" );

  function beforeAll( ) {
    addMatchers( {
               toBeJSON = function( expectation, args={}) { return isJSON( expectation.actual ); },
            notToBeJSON = function( expectation, args={}) { return !isJSON( expectation.actual ); },
         toHaveFunction = function( expectation, args={}) { return structKeyExists( expectation.actual, args[1] ); },
      notToHaveFunction = function( expectation, args={}) { return !structKeyExists( expectation.actual, args[1] ); },
         toBeInstanceOf = function( expectation, args={}) { return isInstanceOf( expectation.actual, args[1] ); },
      notToBeInstanceOf = function( expectation, args={}) { return !isInstanceOf( expectation.actual, args[1] ); }
    } );
  }

  function run( ) {
    describe( "Test object instantiation", function( ) {
      it( "Expects baseCFC Objects to throw an error when missing mandatory properties", function( ) {
        expect( function( ) { var newObject = entityNew( "test" ); } )
          .notToThrow( );

        expect( function( ) { var newObject = entityNew( "invalid" ); } )
          .toThrow( "basecfc.init.invalidPropertiesError" );
      } );
    } );

    describe( "Test helper methods.", function( ) {
      beforeEach( function( currentSpec ) {
        obj = entityNew( "test" );
        obj.save( { name="helperMethods" } );
      } );

      afterEach( function( currentSpec ) {
        structDelete( variables, "obj" );
      } );

      it( "Expects toString( ) to return a json representation of the entity.", function( ) {
        expect( obj.toString( ))
          .toBeString( )
          .notToBeNULL( )
          .toBeJSON( );
      } );

      it( "Expects toString( ) to contain all properties of the entity.", function( ) {
        expect( obj.toString( ))
          .toInclude( '"sortorder"' )
          .toInclude( '"id"' )
          .toInclude( '"deleted"' )
          .toInclude( '"name"' );
      } );

      it( "Expects propertyExists( ) to return true when the entity has the provided property and false when it doesn't.", function( ) {
        expect( obj.propertyExists( "name" ))
          .toBeBoolean( )
          .toBeTrue( );
        expect( obj.propertyExists( "droids" ))
          .toBeBoolean( )
          .toBeFalse( );
      } );

      it( "Expects getInheritedProperties( ) to return a struct containing all inherited properties of the entity.", function( ) {
        expect( obj.getInheritedProperties( ))
          .toBeStruct( )
          .toHaveKey( 'entitiesInSubfolder' )
          .toHaveKey( 'id' )
          .toHaveKey( 'name' )
          .toHaveKey( 'deleted' )
          .toHaveKey( 'sortorder' )
          .notToHaveKey( 'droid' );
      } );

      it( "Expects getEntityName( ) to return the name of the entity.", function( ) {
        expect( obj.getEntityName( ))
          .toBeString( )
          .toBe( "test" )
          .notToMatch( "^.+\.test" )
          .notToBe( "droid" );
      } );

      it( "Expects getClassName( ) to return the full CFC name/path of the entity.", function( ) {
        expect( obj.getClassName( ))
          .toBeString( )
          .toBe( "root.model.beans.test" )
          .notToBe( "droid" );

        var other = entityNew( "other" );

        expect( other.getClassName( ))
          .toBeString( )
          .toBe( "root.model.beans.sub.other" )
          .notToBe( "droid" );
      } );

      it( "Expects getReverseField( ) to return the field linking two entities together.", function( ) {
        // test one-to-many
        expect( obj.getReverseField( "root.model.beans.multiple", "testid" ))
          .toBeString( )
          .toBe( "multiple" );

        // test many-to-one
        expect( obj.getReverseField( "root.model.beans.more", "moreid" ))
          .toBeString( )
          .toBe( "more" );

        expect( function( ) {
          obj.getReverseField( "root.model.beans.more", "moreid" );
        }).notToThrow( );

        expect( function( ) {
          obj.getReverseField( "root.model.beans.more", "notAnExistingFK" );
        }).toThrow( type="basecfc.getReverseField", regex="no reverse field found" );
      } );

      it( "Expects getReverseField( ) to work on sub folders.", function( ) {
        // root to sub folder (one-to-many)
        expect( obj.getReverseField( "root.model.beans.sub.other", "testid" ))
          .toBeString( )
          .toBe( "entityInSubfolder" );

        // from sub folder to root (many-to-one)
        var other = entityNew( "other" );

        expect( other.getReverseField( "root.model.beans.test", "testid" ))
          .toBeString( )
          .toBe( "test" );
      } );

      it( "Expects getReverseField( ) to work with multiple FKs of the same name.", function( ) {
        // test another link to same entity, different fk
        expect( obj.getReverseField( "root.model.beans.more", "duplicateid" ))
          .toBeString( )
          .toBe( "duplicate" )
          .notToBe( "more" );

        // test many-to-one
        expect( obj.getReverseField( "root.model.beans.more", "moreid" ))
          .toBeString( )
          .toBe( "more" )
          .notToBe( "duplicate" );
      } );
    } );

    describe( "Test basic save function.", function( ) {
      beforeEach( function( currentSpec ) {
        obj = entityNew( "test" ).save( { name = "InvalidNameBasicSave" } );
      } );

      afterEach( function( currentSpec ) {
        structDelete( variables, "obj" );
      } );

      it( "Expects save( ) to return the entity", function( ) {
        var result = obj.save( );
        expect( result )
          .toBeTypeOf( 'component' )
          .toBeInstanceOf( 'root.model.beans.test' );
      } );

      it( "Expects save( {name='test'}) to change name (a string) to 'test'", function( ) {
        expect( obj.getName( ))
          .toBe( 'InvalidNameBasicSave' );

        var saveData = {
          name="test"
        };

        var alteredObj = obj.save( saveData );

        expect( alteredObj.getName( ))
          .toBe( 'test' )
          .notToBe( 'InvalidNameBasicSave' );
      } );

      it( "Expects save( ) to prioritize first level values", function( ) {
        var tests = [ { testid = obj.getID( ), name = "renamed" } ];
        var more = entityNew( "more" ).save( { name  = "more", tests = tests } );
        obj.save( { "name" = "prio name", "more" = more } );
        expect( obj.getName( ))
          .toBe( "prio name" )
          .notToBe( "renamed" );
      } );
    } );

    describe( "Test save function with one-to-many relations.", function( ) {
      beforeEach( function( currentSpec ) {
        obj = entityNew( "test" ).save( { name = "InvalidName" } );
      } );

      afterEach( function( currentSpec ) {
        structDelete( variables, "obj" );
      } );

      it( "Expects save( {add_data=obj}) to be able to add a one-to-many object using object", function( ) {
        var other = entityNew( "other" ).save( );
        var saved = obj.save( { add_entityInSubfolder = other } );
        var savedEntitiesInSubfolder = saved.getEntitiesInSubfolder( );

        expect( savedEntitiesInSubfolder )
          .toBeArray( )
          .toHaveLength( 1 );

        expect( savedEntitiesInSubfolder[1].getId( ) )
          .toBe( other.getId( ) );
      } );

      it( "Expects save( {add_data=123}) to be able to add a one-to-many object using pk", function( ) {
        var other = entityNew( "other" ).save( );
        var saved = obj.save( { add_entityInSubfolder = other.getID( ) } );
        var savedEntitiesInSubfolder = saved.getEntitiesInSubfolder( );

        expect( savedEntitiesInSubfolder)
          .toBeArray( )
          .toHaveLength( 1 );

        expect( savedEntitiesInSubfolder[1].getId( ) )
          .toBe( other.getId( ) );
      } );

      it( "Expects save( {add_data={id:123}}) to be able to add a one-to-many object using pk in struct", function( ) {
        var other = entityNew( "other" ).save( );
        var saved = obj.save( { add_entityInSubfolder = { id = other.getID( ) } } );
        var savedEntitiesInSubfolder = saved.getEntitiesInSubfolder( );

        expect( savedEntitiesInSubfolder)
          .toBeArray( )
          .toHaveLength( 1 );

        expect( savedEntitiesInSubfolder[1].getId( ) )
          .toBe( other.getId( ) );
      } );

      it( "Expects save( {add_data='{id:123}'}) to be able to add a one-to-many object using pk in json", function( ) {
        var other = entityNew( "other" ).save( );
        var saved = obj.save( { add_entityInSubfolder = serializeJSON( { id = other.getID( )}) } );
        var savedEntitiesInSubfolder = saved.getEntitiesInSubfolder( );

        expect( savedEntitiesInSubfolder)
          .toBeArray( )
          .toHaveLength( 1 );

        expect( savedEntitiesInSubfolder[1].getId( ) )
          .toBe( other.getId( ) );
      } );

      it( "Expects save( {add_data={name='test'}}) to be able to add a NEW one-to-many object", function( ) {
        var saved = obj.save( {
          add_entityInSubfolder = {
            name = "MyNewObject",
            moreother = {
              name = "testMore"
            }
          }
        } );
        var savedEntitiesInSubfolder = saved.getEntitiesInSubfolder( );

        expect( savedEntitiesInSubfolder )
          .toBeArray( )
          .toHaveLength( 1 );

        expect( savedEntitiesInSubfolder[1].getName( ))
          .toBe( "MyNewObject" );
      } );

      it( "Expects save( {add_data=[data]}) to be able to add multiple one-to-many objects", function( ) {
        var first = entityNew( "other" ).save( {name="first"} );
        var second = entityNew( "other" ).save( {name="second"} );

        var saved = obj.save( {
          add_entityInSubfolder = [
            { id = first.getID( ) },
            second.getID( )
          ]
        } );

        var savedEntitiesInSubfolder = saved.getEntitiesInSubfolder( );

        expect( savedEntitiesInSubfolder )
          .toBeArray( )
          .toHaveLength( 2 );

        expect( savedEntitiesInSubfolder[1].getId( ) )
          .toBe( first.getId( ) );

        expect( savedEntitiesInSubfolder[2].getId( ) )
          .toBe( second.getId( ) );
      } );

      it( "Expects save( {set_data=[data]}) to replace all items in a one-to-many relation", function( ) {
        transaction {
          var first   = entityNew( "other" ).save( { name = "first"   } );
          var second  = entityNew( "other" ).save( { name = "second"  } );
          var third   = entityNew( "other" ).save( { name = "third"   } );

          var saveData = {
            "entitiesInSubFolder" = [ first, second ]
          };

          var saved = obj.save( saveData );
          var savedEntitiesInSubfolder = saved.getEntitiesInSubfolder( );

          expect( savedEntitiesInSubfolder )
            .toBeArray( )
            .toHaveLength( 2 );

          expect( savedEntitiesInSubfolder[ 1 ].getId( ) )
            .toBe( first.getId( ) );

          expect( savedEntitiesInSubfolder[ 2 ].getId( ) )
            .toBe( second.getId( ) );
        }


        var overwriteData = {
          "entitiesInSubFolder" = [ third ]
        };

        var newSave = obj.save( overwriteData );
        var savedEntitiesInSubfolder = newSave.getEntitiesInSubfolder( );

        expect( savedEntitiesInSubfolder )
          .toBeArray( )
          .toHaveLength( 1 );

        expect( savedEntitiesInSubfolder[ 1 ].getId( ) )
          .toBe( third.getId( ) );
      } );

      it ( "Expects remove to work", function ( ) {
        var multiple_1 = entityNew( "multiple" ).save( );
        var multiple_2 = entityNew( "multiple" ).save( );

        obj.save(
          {
            "name" = "toManyUpdateTest",
            "multiples" = [ multiple_1, multiple_2 ]
          }
        );

        transaction {
          obj.save(
            {
              "name" = "toManyUpdateTest",
              "remove_multiples" = multiple_1
            }
          );
        }

        var result = obj.getMultiples( );

        expect( result )
          .toHaveLength( 1 );
      } );

      it ( "Expects update multiple items to not remove old items", function ( ) {
        var multiple_1 = entityNew( "multiple" ).save( );
        var multiple_2 = entityNew( "multiple" ).save( );

        obj.save(
          {
            "name" = "toManyUpdateTest",
            "multiples" = [ multiple_1 ]
          }
        );

        transaction {
          obj.save(
            {
              "name" = "toManyUpdateTest",
              "multiples" = [ multiple_1, multiple_2 ]
            }
          );
        }

        var result = obj.getMultiples( );

        expect( result )
          .toHaveLength( 2 );
      } );

      it( "Expects set_ to overwrite add_ in save( )", function( ) {
        var testObjects = [
          entityNew( "multiple" ).save( {name="a"}),
          entityNew( "multiple" ).save( {name="b"}),
          entityNew( "multiple" ).save( {name="c"})
        ];

        obj.save( {
          set_multiples = [ testObjects[1], testObjects[2] ],
          add_multiple = testObjects[3]
        } );

        var result = obj.getMultiples( );

        expect( result )
          .toBeTypeOf( "array" )
          .toHaveLength( 2 );

        expect( result[1].getName( ))
          .toBe( "a" );

        expect( result[2].getName( ))
          .toBe( "b" );
      } );
    } );

    describe( "Test save function with many-to-one relations.", function( ) {
      beforeEach( function( currentSpec ) {
        obj = entityNew( "test" ).save( { name="InvalidName" } );
      } );

      afterEach(function( currentSpec ) {
        structDelete( variables, "obj" );
      } );

      it( "Expects save( {data=obj}) to be able to add a many-to-one object using object", function( ) {
        var more = entityNew( "more" ).save( );
        var savedMore = entityLoadByPK( "more", more.getID( ));
        var saved = obj.save( { more = savedMore } );

        expect( saved ).notToBeNull( );

        expect( saved.getMore( ))
          .notToBeNull( );

        expect( saved.getMore( ).getID( ))
          .toBe( savedMore.getID( ));
      } );

      it( "Expects save( {data=123}) to be able to add a many-to-one object using pk", function( ) {
        var more = entityNew( "more" ).save( );
        var saved = obj.save( { more = more.getID( ) } );

        expect( saved.getMore( ).getId( ) )
          .toBe( more.getId( ) );
      } );

      it( "Expects save( {data={id=123}}) to be able to add a many-to-one object using pk in struct", function( ) {
        var more = entityNew( "more" ).save( );


        var saveData = {
          more = { id = more.getID( )}
        };

        var saved = obj.save( saveData );

        expect( saved.getMore( ).getID( ))
          .toBe( more.getID( ));
      } );

      it( "Expects save( {data='{id:123}'}) to be able to add a many-to-one object using pk in json", function( ) {
        var more = entityNew( "more" ).save( );


        var saveData = {
          more = serializeJSON( { id = more.getID( )})
        };

        var saved = obj.save( saveData );

        expect( saved.getMore( ).getId( ))
          .toBe( more.getId( ) );
      } );

      it( "Expects save( {data={name='test'}}) to be able to add a NEW many-to-one object", function( ) {
        var saveData = {
          more = {
            name = "newMore",
            deeper = {
              name = "deeper"
            }
          }
        };

        var saved = obj.save( saveData );
        var more = saved.getMore( );

        expect( more )
          .notToBeNULL( )
          .toBeInstanceOf( "root.model.beans.more" )
          .toHaveFunction( "getName" );

        expect( more.getName( ))
          .toBe( "newMore" );

        // test the reverse link:
        var linkBack = more.getTests( );
        expect( linkBack )
          .toBeArray( )
          .toHaveLength( 1 );
        expect( linkBack[1].getId( ) )
          .toBe( saved.getId( ) );

        // also check one level deeper:
        var deeper = more.getDeeper( );
        expect( deeper.getName( ))
          .toBe( "deeper" );

        // test the reverse link:
        var deeperLinkBack = deeper.getMores( );
        expect( deeperLinkBack )
          .toBeArray( )
          .toHaveLength( 1 );
        expect( deeperLinkBack[1].getId( ) )
          .toBe( more.getId( ) );
      } );
    } );

    describe( "Test save function with many-to-many relations.", function( ) {
      it( "Expects save( ) to work with many-to-many relations", function( ){
        transaction {
          var sideA = entityNew( "multiple" ).save( {name="sideA"} );
          var sideB = entityNew( "multiple" ).save( {name="sideB"} );

          sideA.save( {
            multiplesB = [ sideB ]
          } );
        }

        entityReload( sideA );
        entityReload( sideB );

        expect( sideA.getMultiplesB( ))
          .toBeTypeOf( "array" )
          .toHaveLength( 1 );

        expect( sideA.getMultiplesB( )[1] )
          .toBeTypeOf( "component" );

        expect( sideB.getMultiplesA( ))
          .toBeTypeOf( "array" )
          .toHaveLength( 1 );

        expect( sideB.getMultiplesA( )[1] )
          .toBeTypeOf( "component" );
      } );
    } );

    describe( "delete and restore tests", function( ) {
      it ( "Expects restore() to set deleted flag to false", function () {
        var entityToDelete = entityNew( "test" );

        entityToDelete.save( { "name" = "entityToDelete", "deleted" = true } );
        var pk = entityToDelete.getId( );

        expect( entityToDelete.getDeleted( ) ).toBeTrue( );

        entityToDelete.restore( );

        var entityToDelete = entityLoadByPK( "test", pk );

        expect( entityToDelete.getDeleted( ) ).toBeFalse( );
      } );

      it ( "Expects delete() to set deleted flag to true", function () {
        var entityToDelete = entityNew( "test" );

        entityToDelete.save( { "name" = "entityToDelete" } );
        var pk = entityToDelete.getId( );

        entityToDelete.delete( );

        var entityToDelete = entityLoadByPK( "test", pk );

        expect( entityToDelete.getDeleted( ) ).toBeTrue( );
      } );

      it ( "Expects delete() and restore() functions to act consistently", function () {
        transaction {
          var entityToDelete = entityNew( "test" );

          entityToDelete.save( { "name" = "entityToDelete" } );
          var pk = entityToDelete.getId( );

          var entityToDelete = entityLoadByPK( "test", pk );

          expect( entityToDelete.getDeleted( ) ).toBeFalse( );

          entityToDelete.delete( );

          var entityToDelete = entityLoadByPK( "test", pk );

          expect( entityToDelete.getDeleted( ) ).toBeTrue( );

          entityToDelete.restore( );

          var entityToDelete = entityLoadByPK( "test", pk );
        }

        expect( entityToDelete.getDeleted( ) ).toBeFalse( );
      } );
    } );

    describe( "Transaction Tests", function( ) {
      beforeEach( function( currentSpec ) {
        var allTests = entityLoad( "test" );
        var allMores = entityLoad( "more" );

        allTests.each( function ( item ) {
          entityDelete( item );
        } );

        allMores.each( function ( item ) {
          entityDelete( item );
        } );
      } );


      it( "Expects objects not to be persisted with transactionRollback", function( ) {
        var obj = entityNew( "test" );

        transaction {
          obj.save( { name = "transactionTest", more = { name = "subItem" } } );

          transactionRollback( );
        }

        var allTests = entityLoad( "test" );
        var allMores = entityLoad( "more" );

        expect( allTests ).toHaveLength( 0 );
        expect( allMores ).toHaveLength( 0 );
      } );

      it( "Expects objects to be persisted without transactionRollback", function( ) {
        var obj = entityNew( "test" );

        transaction {
          obj.save( { name = "transactionTest", more = { name = "subItem" } } );
        }

        var allTests = entityLoad( "test" );
        var allMores = entityLoad( "more" );

        expect( allTests ).toHaveLength( 1 );
        expect( allMores ).toHaveLength( 1 );
      } );
    } );

    describe( "Data type tests", function( ) {
      it( "Expects baseCFC to error using invalid data", function( ) {
        var validator = new root.model.services.validation( );
        var obj = entityNew( "validationtests" );

        transaction {
          obj.save( {
            stringLength = "abcdef" // <-- too long
          }, 0, validator );

          try {
            transactionCommit( );
          } catch ( any e ) {
            transactionRollback( );
          }
        }

        var allValidationtests = entityLoad( "validationtests" );

        expect( allValidationtests ).toHaveLength( 0 );
      } );

      it( "Expects baseCFC to save successfully using validated data", function( ) {
        var validator = new root.model.services.validation( );
        var obj = entityNew( "validationtests" );

        transaction {
          obj.save( {
            stringLength = "abcde" // <-- OK
          }, 0, validator );

          try {
            transactionCommit( );
          } catch ( any e ) {
            transactionRollback( );
          }
        }

        var allValidationtests = entityLoad( "validationtests" );

        expect( allValidationtests ).toHaveLength( 1 );
      } );
    } );

    describe( "Tests mustang logging integration", function( ) {
      it( "Expects baseCFC to save a logentry when an object inherits from logged", function() {
        request.context.config.log = true;

        var logable = entityNew( "logable" );
        var result = logable.save( { "aFieldToTest" = "firstValue", "thisWontChange" = "staticValue" } );
        var result = logable.save( { "aFieldToTest" = "secondValue" } );
        var log = entityLoad( "logentry" );

        expect( log )
          .toBeTypeOf( "array" )
          .toHaveLength( 2 );

        expect( log[ 1 ].getSavedState( ) )
          .toBe( '{"aFieldToTest":"firstValue","thisWontChange":"staticValue"}' );

        expect( log[ 2 ].getSavedState( ) )
          .toBe( '{"aFieldToTest":"secondValue"}' );
      } );
    } );

    describe( "Tests one-to-one connections", function( ) {
      it( "Expects one-to-one connections to work on two objects", function( ) {
        transaction {
          var b = entityNew( "oneB" ).save( { "name" = "1 - object B" } );
        }

        transaction {
          var result = entityNew( "oneA" ).save( { "name" = "1 - object A", "b" = b } );
        }

        var idA = result.getId( );
        var idB = b.getId( );

        var bInA = result.getB( );

        expect( bInA )
          .notToBeNull( );

        var aInB = b.getA( );

        expect( aInB )
          .notToBeNull( );

        expect( bInA.getId( ) )
          .toBe( idB )
          .notToBe( idA );

        expect( aInB.getId( ) )
          .toBe( idA )
          .notToBe( idB );
      } );

      it( "Expects one-to-one connections to work on one object and one PK", function( ) {
        var b = entityNew( "oneB" );

        transaction {
          b.save( { "name" = "2 - object B" } );
        }

        var a = entityNew( "oneA" );

        transaction {
          var result = a.save( { "name" = "2 - object A", b = b.getId( ) } );
        }

        var bInA = result.getB( );

        expect( bInA )
          .notToBeNull( );

        var idA = result.getId( );

        var aInB = bInA.getA( );

        expect( aInB )
          .notToBeNull( );

        var idB = bInA.getId( );

        expect( bInA.getId( ) )
          .toBe( idB )
          .notToBe( idA );

        expect( aInB.getId( ) )
          .toBe( idA )
          .notToBe( idB );

        expect( bInA.getName( ) )
          .toBe( "2 - object B" );
      } );

      it( "Expects one-to-one connections to work on one object and one struct", function( ) {
        var a = entityNew( "oneA" );

        transaction {
          var result = a.save( { "name" = "3 - object A", b = { "name" = "3 - object B" } } );
        }

        var bInA = result.getB( );

        expect( bInA )
          .notToBeNull( );

        var idA = result.getId( );

        var aInB = bInA.getA( );

        expect( aInB )
          .notToBeNull( );

        var idB = bInA.getId( );

        expect( bInA.getId( ) )
          .toBe( idB )
          .notToBe( idA );

        expect( aInB.getId( ) )
          .toBe( idA )
          .notToBe( idB );

        expect( bInA.getName( ) )
          .toBe( "3 - object B" );
      } );
    } );
  }
}