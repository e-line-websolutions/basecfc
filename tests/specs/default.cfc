component extends="testbox.system.basespec" {
  variables.bf = new framework.ioc( [ '/mustang/services', '/root/model' ], { 'constants' = { 'config' = {} } } );
  variables.dataservice = bf.getbean( 'dataService' );
  variables.validationService = bf.getbean( 'validationService' );

  function beforeall() {
    addmatchers( {
      tobejson = function( expectation, args = {} ) {
        return isJSON( expectation.actual );
      },
      nottobejson = function( expectation, args = {} ) {
        return !isJSON( expectation.actual );
      },
      tohavefunction = function( expectation, args = {} ) {
        return structKeyExists( expectation.actual, args[ 1 ] );
      },
      nottohavefunction = function( expectation, args = {} ) {
        return !structKeyExists( expectation.actual, args[ 1 ] );
      },
      tobeinstanceof = function( expectation, args = {} ) {
        return isInstanceOf( expectation.actual, args[ 1 ] );
      },
      nottobeinstanceof = function( expectation, args = {} ) {
        return !isInstanceOf( expectation.actual, args[ 1 ] );
      }
    } );
  }

  function run() {
    describe( title = 'test object instantiation',
      body = function() {
        it( 'expects basecfc objects to throw an error when missing mandatory properties', function() {
          expect( function() {
            var newobject = entityNew( 'test' ).save();
          } ).nottothrow();

          expect( function() {
            var newobject = entityNew( 'invalid' );
          } ).tothrow();

          expect( function() {
            var newobject = entityNew( 'invalid' ).init();
          } ).tothrow();

          expect( function() {
            var newobject = entityNew( 'invalid' ).save();
          } ).tothrow( 'basecfc.init.invalidpropertieserror' );
        } );
      }
    );

    describe( title = 'test helper methods.',
      body = function() {
        beforeeach( function( currentspec ) {
          obj = entityNew( 'test' );
          obj.save( { name = 'helpermethods' } );
        } );

        aftereach( function( currentspec ) {
          obj = javacast( 'null', 0 );
        } );

        it( 'expects tojson( ) to return a json representation of the entity.', function() {
          expect( obj.tojson() ).tobestring()
            .nottobenull()
            .tobejson();
        } );

        it( 'expects tojson( ) to contain all properties of the entity.', function() {
          expect( obj.tojson() ).toinclude( '"sortorder"' )
            .toinclude( '"id"' )
            .toinclude( '"deleted"' )
            .toinclude( '"name"' );
        } );

        it( 'expects propertyexists( ) to return true when the entity has the provided property and false when it doesn''t.', function() {
          expect( obj.propertyexists( 'name' ) ).tobeboolean().tobetrue();
          expect( obj.propertyexists( 'droids' ) ).tobeboolean().tobefalse();
        } );

        it( 'expects getinheritedproperties( ) to return a struct containing all inherited properties of the entity.', function() {
          expect( obj.getinheritedproperties() ).tobestruct()
            .tohavekey( 'entitiesinsubfolder' )
            .tohavekey( 'id' )
            .tohavekey( 'name' )
            .tohavekey( 'deleted' )
            .tohavekey( 'sortorder' )
            .nottohavekey( 'droid' );
        } );

        it( 'expects getentityname( ) to return the name of the entity.', function() {
          expect( obj.getentityname() ).tobestring()
            .tobe( 'test' )
            .nottomatch( '^.+\.test' )
            .nottobe( 'droid' );
        } );

        it( 'expects getclassname( ) to return the full cfc name/path of the entity.', function() {
          expect( obj.getclassname() ).tobestring()
            .tobe( 'basecfc.tests.orm.test' )
            .nottobe( 'droid' );

          var other = entityNew( 'other' );

          expect( other.getclassname() ).tobestring()
            .tobe( 'basecfc.tests.orm.sub.other' )
            .nottobe( 'droid' );
        } );

        it( 'expects getreversefield( ) to return the field linking two entities together.', function() {
          // test one-to-many
          expect( obj.getreversefield( 'basecfc.tests.orm.multiple', 'testid' ) ).tobestring().tobe( 'multiple' );

          // test many-to-one
          expect( obj.getreversefield( 'basecfc.tests.orm.more', 'moreid' ) ).tobestring().tobe( 'more' );

          expect( function() {
            obj.getreversefield( 'basecfc.tests.orm.more', 'moreid' );
          } ).nottothrow();

          expect( function() {
            obj.getreversefield( 'basecfc.tests.orm.more', 'notanexistingfk' );
          } ).tothrow( type = 'basecfc.getreversefield', regex = 'no reverse field found' );
        } );

        it( 'expects getreversefield( ) to work on sub folders.', function() {
          // root to sub folder (one-to-many)
          expect( obj.getreversefield( 'basecfc.tests.orm.sub.other', 'testid' ) ).tobestring().tobe( 'entityinsubfolder' );

          // from sub folder to root (many-to-one)
          var other = entityNew( 'other' );

          expect( other.getreversefield( 'basecfc.tests.orm.test', 'testid' ) ).tobestring().tobe( 'test' );
        } );

        it( 'expects getreversefield( ) to work with multiple fks of the same name.', function() {
          // test another link to same entity, different fk
          expect( obj.getreversefield( 'basecfc.tests.orm.more', 'duplicateid' ) ).tobestring()
            .tobe( 'duplicate' )
            .nottobe( 'more' );

          // test many-to-one
          expect( obj.getreversefield( 'basecfc.tests.orm.more', 'moreid' ) ).tobestring()
            .tobe( 'more' )
            .nottobe( 'duplicate' );
        } );
      }
    );

    describe( title = 'test basic save function.',
      body = function() {
        beforeeach( function( currentspec ) {
          obj = entityNew( 'test' ).save( { name = 'invalidnamebasicsave' } );
        } );

        aftereach( function( currentspec ) {
          structDelete( variables, 'obj' );
        } );

        it( 'expects save( ) to return the entity', function() {
          var result = obj.save();
          expect( result ).tobetypeof( 'component' ).tobeinstanceof( 'basecfc.tests.orm.test' );
        } );

        it( 'expects save( {name=''test''}) to change name (a string) to ''test''', function() {
          expect( obj.getname() ).tobe( 'invalidnamebasicsave' );

          var savedata = { name = 'test' };

          var alteredobj = obj.save( savedata );

          expect( alteredobj.getname() ).tobe( 'test' ).nottobe( 'invalidnamebasicsave' );
        } );

        it( 'expects save( ) to prioritize first level values', function() {
          var tests = [ { testid = obj.getid(), name = 'renamed' } ];
          var more = entityNew( 'more' ).save( { name = 'more', tests = tests } );
          obj.save( { 'name' = 'prio name', 'more' = more } );
          expect( obj.getname() ).tobe( 'prio name' ).nottobe( 'renamed' );
        } );
      }
    );

    describe( title = 'test save function with one-to-many relations.',
      body = function() {
        beforeeach( function( currentspec ) {
          obj = entityNew( 'test' ).save( { name = 'invalidname' } );
        } );

        aftereach( function( currentspec ) {
          structDelete( variables, 'obj' );
        } );

        it( 'expects save( {add_data=obj}) to be able to add a one-to-many object using object', function() {
          var other = entityNew( 'other' ).save();
          var saved = obj.save( { add_entityinsubfolder = other } );
          var savedentitiesinsubfolder = saved.getentitiesinsubfolder();

          expect( savedentitiesinsubfolder ).tobearray().tohavelength( 1 );

          expect( savedentitiesinsubfolder[ 1 ].getid() ).tobe( other.getid() );
        } );

        it( 'expects save( {add_data=123}) to be able to add a one-to-many object using pk', function() {
          var other = entityNew( 'other' ).save();
          var saved = obj.save( { add_entityinsubfolder = other.getid() } );
          var savedentitiesinsubfolder = saved.getentitiesinsubfolder();

          expect( savedentitiesinsubfolder ).tobearray().tohavelength( 1 );

          expect( savedentitiesinsubfolder[ 1 ].getid() ).tobe( other.getid() );
        } );

        it( 'expects save( {add_data={id:123}}) to be able to add a one-to-many object using pk in struct', function() {
          var other = entityNew( 'other' ).save();
          var saved = obj.save( { add_entityinsubfolder = { id = other.getid() } } );
          var savedentitiesinsubfolder = saved.getentitiesinsubfolder();

          expect( savedentitiesinsubfolder ).tobearray().tohavelength( 1 );

          expect( savedentitiesinsubfolder[ 1 ].getid() ).tobe( other.getid() );
        } );

        it( 'expects save( {add_data=''{id:123}''}) to be able to add a one-to-many object using pk in json', function() {
          var other = entityNew( 'other' ).save();
          var saved = obj.save( { add_entityinsubfolder = serializeJSON( { id = other.getid() } ) } );
          var savedentitiesinsubfolder = saved.getentitiesinsubfolder();

          expect( savedentitiesinsubfolder ).tobearray().tohavelength( 1 );

          expect( savedentitiesinsubfolder[ 1 ].getid() ).tobe( other.getid() );
        } );

        it( 'expects save( {add_data={name=''test''}}) to be able to add a new one-to-many object', function() {
          var saved = obj.save( { add_entityinsubfolder = { name = 'mynewobject', moreother = { name = 'testmore' } } } );
          var savedentitiesinsubfolder = saved.getentitiesinsubfolder();

          expect( savedentitiesinsubfolder ).tobearray().tohavelength( 1 );

          expect( savedentitiesinsubfolder[ 1 ].getname() ).tobe( 'mynewobject' );
        } );

        it( 'expects save( {add_data=[data]}) to be able to add multiple one-to-many objects', function() {
          var first = entityNew( 'other' ).save( { name = 'first' } );
          var second = entityNew( 'other' ).save( { name = 'second' } );

          var saved = obj.save( {
            add_entityinsubfolder = [
              { id = first.getid() },
              second.getid()
            ]
          } );

          var savedentitiesinsubfolder = saved.getentitiesinsubfolder();

          expect( savedentitiesinsubfolder ).tobearray().tohavelength( 2 );

          expect( savedentitiesinsubfolder[ 1 ].getid() ).tobe( first.getid() );

          expect( savedentitiesinsubfolder[ 2 ].getid() ).tobe( second.getid() );
        } );

        it( 'expects save( {set_data=[data]}) to replace all items in a one-to-many relation', function() {
          transaction {
            var first = entityNew( 'other' ).save( { name = 'first' } );
            var second = entityNew( 'other' ).save( { name = 'second' } );
            var third = entityNew( 'other' ).save( { name = 'third' } );

            var savedata = {
              'entitiesinsubfolder' = [ first, second ]
            };

            var saved = obj.save( savedata );
            var savedentitiesinsubfolder = saved.getentitiesinsubfolder();

            expect( savedentitiesinsubfolder ).tobearray().tohavelength( 2 );

            expect( savedentitiesinsubfolder[ 1 ].getid() ).tobe( first.getid() );

            expect( savedentitiesinsubfolder[ 2 ].getid() ).tobe( second.getid() );
          }


          var overwritedata = { 'entitiesinsubfolder' = [ third ] };

          var newsave = obj.save( overwritedata );
          var savedentitiesinsubfolder = newsave.getentitiesinsubfolder();

          expect( savedentitiesinsubfolder ).tobearray().tohavelength( 1 );

          expect( savedentitiesinsubfolder[ 1 ].getid() ).tobe( third.getid() );
        } );

        it( 'expects remove to work', function() {
          transaction {
            var multiple_1 = entityNew( 'multiple' ).save();
            var multiple_2 = entityNew( 'multiple' ).save();
            obj.save( {
              'name' = 'tomanyupdatetest',
              'multiples' = [ multiple_1, multiple_2 ]
            } );
          }

          expect( obj.getmultiples() ).tohavelength( 2 );

          transaction {
            obj.save( { 'name' = 'tomanyupdatetest', 'remove_multiples' = multiple_1 } );
          }

          expect( obj.getmultiples() ).tohavelength( 1 );
        } );

        it( 'expects update multiple items to not remove old items', function() {
          transaction {
            var multiple_1 = entityNew( 'multiple' ).save();
            var multiple_2 = entityNew( 'multiple' ).save();
            obj.save( { 'name' = 'tomanyupdatetest', 'multiples' = [ multiple_1 ] } );
          }

          expect( obj.getmultiples() ).tohavelength( 1 );

          transaction {
            obj.save( {
              'name' = 'tomanyupdatetest',
              'multiples' = [ multiple_1, multiple_2 ]
            } );
          }

          expect( obj.getmultiples() ).tohavelength( 2 );
        } );

        it( 'expects set_ to overwrite add_ in save( )', function() {
          var testobjects = [
            entityNew( 'multiple' ).save( { name = 'a' } ),
            entityNew( 'multiple' ).save( { name = 'b' } ),
            entityNew( 'multiple' ).save( { name = 'c' } )
          ];

          obj.save( {
            set_multiples = [ testobjects[ 1 ], testobjects[ 2 ] ],
            add_multiple = testobjects[ 3 ]
          } );

          var result = obj.getmultiples();

          expect( result ).tobetypeof( 'array' ).tohavelength( 2 );

          expect( result[ 1 ].getname() ).tobe( 'a' );

          expect( result[ 2 ].getname() ).tobe( 'b' );
        } );
      }
    );

    describe( title = 'test save function with many-to-one relations.',
      body = function() {
        beforeeach( function( currentspec ) {
          obj = entityNew( 'test' ).save( { name = 'invalidname' } );
        } );

        aftereach( function( currentspec ) {
          structDelete( variables, 'obj' );
        } );

        it( 'expects save( {data=obj}) to be able to add a many-to-one object using object', function() {
          var more = entityNew( 'more' ).save();
          var savedmore = entityLoadByPK( 'more', more.getid() );
          var saved = obj.save( { more = savedmore } );

          expect( saved ).nottobenull();

          expect( saved.getmore() ).nottobenull();

          expect( saved.getmore().getid() ).tobe( savedmore.getid() );
        } );

        it( 'expects save( {data=123}) to be able to add a many-to-one object using pk', function() {
          var more = entityNew( 'more' ).save();
          var saved = obj.save( { more = more.getid() } );

          expect( saved.getmore().getid() ).tobe( more.getid() );
        } );

        it( 'expects save( {data={id=123}}) to be able to add a many-to-one object using pk in struct', function() {
          var more = entityNew( 'more' ).save();


          var savedata = { more = { id = more.getid() } };

          var saved = obj.save( savedata );

          expect( saved.getmore().getid() ).tobe( more.getid() );
        } );

        it( 'expects save( {data=''{id:123}''}) to be able to add a many-to-one object using pk in json', function() {
          var more = entityNew( 'more' ).save();


          var savedata = { more = serializeJSON( { id = more.getid() } ) };

          var saved = obj.save( savedata );

          expect( saved.getmore().getid() ).tobe( more.getid() );
        } );

        it( 'expects save( {data={name=''test''}}) to be able to add a nested many-to-one object', function() {
          var savedata = { more = { name = 'newmore', deeper = { name = 'deeper' } } };

          var saved = obj.save( savedata );
          var more = saved.getmore();

          expect( more ).nottobenull()
            .tobeinstanceof( 'basecfc.tests.orm.more' )
            .tohavefunction( 'getname' );

          expect( more.getname() ).tobe( 'newmore' );

          // test the reverse link:
          var linkback = more.gettests();
          expect( linkback ).tobearray().tohavelength( 1 );
          expect( linkback[ 1 ].getid() ).tobe( saved.getid() );

          // also check one level deeper:
          var deeper = more.getdeeper();
          expect( deeper.getname() ).tobe( 'deeper' );

          // test the reverse link:
          var deeperlinkback = deeper.getmores();
          expect( deeperlinkback ).tobearray().tohavelength( 1 );
          expect( deeperlinkback[ 1 ].getid() ).tobe( more.getid() );
        } );
      }
    );

    describe( title = 'test save function with many-to-many relations.',
      body = function() {
        beforeeach( function( currentspec ) {
          transaction {
            entityLoad( 'multiple' ).each( function( entity ) {
              entityDelete( entity );
            } );
          }
        } );

        it( 'expects save( ) to work with many-to-many relations', function() {
          transaction {
            var sidea = entityNew( 'multiple' ).save( { name = 'sidea' } );
            var sideb = entityNew( 'multiple' ).save( { name = 'sideb' } );

            sidea.save( { multiplesb = [ sideb ] } );
          }

          expect( sidea.getmultiplesb() ).tobetypeof( 'array' ).tohavelength( 1 );
          expect( sidea.getmultiplesb()[ 1 ] ).tobetypeof( 'component' );
          expect( sideb.getmultiplesa() ).tobetypeof( 'array' ).tohavelength( 1 );
          expect( sideb.getmultiplesa()[ 1 ] ).tobetypeof( 'component' );
        } );
      }
    );

    describe( title = 'delete and restore tests',
      body = function() {
        it ( 'expects restore() to set deleted flag to false', function() {
          var entitytodelete = entityNew( 'test' );

          entitytodelete.save( { 'name' = 'entitytodelete', 'deleted' = true } );
          var pk = entitytodelete.getid();

          expect( entitytodelete.getdeleted() ).tobetrue();

          entitytodelete.restore();

          var entitytodelete = entityLoadByPK( 'test', pk );

          expect( entitytodelete.getdeleted() ).tobefalse();
        } );

        it ( 'expects delete() to set deleted flag to true', function() {
          var entitytodelete = entityNew( 'test' );

          entitytodelete.save( { 'name' = 'entitytodelete' } );
          var pk = entitytodelete.getid();

          entitytodelete.delete();

          var entitytodelete = entityLoadByPK( 'test', pk );

          expect( entitytodelete.getdeleted() ).tobetrue();
        } );

        it ( 'expects delete() and restore() functions to act consistently', function() {
          transaction {
            var entitytodelete = entityNew( 'test' );

            entitytodelete.save( { 'name' = 'entitytodelete' } );
            var pk = entitytodelete.getid();

            var entitytodelete = entityLoadByPK( 'test', pk );

            expect( entitytodelete.getdeleted() ).tobefalse();

            entitytodelete.delete();

            var entitytodelete = entityLoadByPK( 'test', pk );

            expect( entitytodelete.getdeleted() ).tobetrue();

            entitytodelete.restore();

            var entitytodelete = entityLoadByPK( 'test', pk );
          }

          expect( entitytodelete.getdeleted() ).tobefalse();
        } );
      }
    );

    describe( title = 'transaction tests',
      body = function() {
        beforeeach( function( currentspec ) {
          transaction {
            entityLoad( 'test' ).each(function(entity){
              entityReload(entity);
              entityDelete(entity);
            });
            entityLoad( 'more' ).each(function(entity){
              entityReload(entity);
              entityDelete(entity);
            });
          }
        } );

        afterEach( function( currentspec ) {
          ormCloseAllSessions();
        } );

        it( 'expects objects not to be persisted with transactionrollback', function() {
          expect( entityLoad( 'test' ) ).tohavelength( 0 );
          expect( entityLoad( 'more' ) ).tohavelength( 0 );

          var obj = entityNew( 'test' );

          transaction {
            obj.save( { 'name' = 'transactiontest 1', 'more' = { 'name' = 'subitem' } } );
            transactionRollback();
          }

          var alltests = entityLoad( 'test' );
          var allmores = entityLoad( 'more' );

          expect( alltests ).tohavelength( 0 );
          expect( allmores ).tohavelength( 0 );
        } );

        it( 'expects objects to be persisted without transactionrollback', function() {
          expect( entityLoad( 'test' ) ).tohavelength( 0 );
          expect( entityLoad( 'more' ) ).tohavelength( 0 );

          transaction {
            entityNew( 'test' ).save( { 'name' = 'transactiontest 2', 'more' = { 'name' = 'subitem' } } );
          }

          var alltests = entityLoad( 'test' );
          var allmores = entityLoad( 'more' );

          expect( alltests ).tohavelength( 1 );
          expect( allmores ).tohavelength( 1 );
        } );
      }
    );

    describe( title = 'data type tests',
      body = function() {
        beforeEach( function() {
          entityLoad( 'validationtests' ).each(function(entity){try{entityDelete(entity);}catch(any e){}});
        } );

        afterEach( function() {
          ormCloseAllSessions();
        } );

        it( 'expects basecfc to error using invalid data', function() {
          var obj = entityNew( 'validationtests' );
          var testValue = 'abcdef';

          transaction {
            obj.save( { stringlength = testValue }, 0, validationService );
            var report = obj.getValidationReport();
            if ( report.len() ) transactionRollback();
          }

          var allvalidationtests = entityLoad( 'validationtests' );
          expect( allvalidationtests ).tohavelength( 0 );
          expect( report ).notToBeEmpty();
          expect( report[ 1 ].errortype ).toBe( 'validationServiceError.stringlength' );
        } );

        it( 'expects basecfc to save successfully using validated data', function() {
          var obj = entityNew( 'validationtests' );
          var testValue = 'abcde';

          transaction {
            obj.save( { stringlength = testValue }, 0, validationService );
            var report = obj.getValidationReport();
            if ( report.len() ) transactionRollback();
          }

          var allvalidationtests = entityLoad( 'validationtests' );
          expect( allvalidationtests ).tohavelength( 1 );
          expect( report ).toBeEmpty();
        } );

        xit( 'expects basecfc to save successfully using json data', function() {
          var testdata = serializeJSON( { 'hello' = 'world' } );

          transaction {
            var obj = entityNew( 'test' );
            entitySave( obj );
            obj.save( { jsontest = testdata } );
          }

          var result = queryExecute(
            'select jsontest->>''hello''::varchar as test from test where jsontest @> ''#testdata#''',
            {},
            { datasource = 'basecfc' }
          );

          expect( result.test[ 1 ] ).tobe( 'world' );
        } );

        xit( 'expects basecfc to work with complex json data', function() {
          var testdata = '
                {
                  "arr": [
                    {
                      "id": "myid",
                      "ids": ["anotherid"],
                      "items": [
                        {
                          "id": "lastid"
                        }
                      ]
                    }
                  ]
                }
              ';

          transaction {
            var obj = entityNew( 'test' );
            entitySave( obj );
            obj.save( { jsontest = testdata } );
          }

          var result = queryExecute(
            'select jsontest ##>> ''{arr,0,id}'' as test from test where jsontest @> ''{"arr":[]}''',
            {},
            { datasource = 'basecfc' }
          );

          expect( result.test[ 1 ] ).tobe( 'myid' );
        } );
      }
    );

    describe( title = 'tests mustang logging integration',
      body = function() {
        beforeEach( function() {
          entityLoad( 'logentry' ).each(function(entity){try{entityDelete(entity);}catch(any e){}});
        } );

        it( 'expects basecfc to save a logentry when an object inherits from logged', function() {
          request.context.config.log = true;

          var logable = entityNew( 'logable' );
          var result = logable.save( { 'afieldtotest' = 'firstvalue', 'thiswontchange' = 'staticvalue' } );
          var result = logable.save( { 'afieldtotest' = 'secondvalue' } );
          var log = entityLoad( 'logentry' );

          expect( log ).tobetypeof( 'array' ).tohavelength( 2 );

          expect( log[ 1 ].getsavedstate() ).tobejson();

          var savedstate = deserializeJSON(log[ 1 ].getsavedstate());

          expect( savedstate ).toHaveKey( 'afieldtotest' );
          expect( savedstate ).toHaveKey( 'thiswontchange' );
          expect( savedstate.afieldtotest ).toBe( 'firstvalue' );
          expect( savedstate.thiswontchange ).toBe( 'staticvalue' );

          expect( log[ 2 ].getsavedstate() ).tobejson();

          var savedstate = deserializeJSON(log[ 2 ].getsavedstate());

          expect( savedstate ).toHaveKey( 'afieldtotest' );
          expect( savedstate.afieldtotest ).toBe( 'secondvalue' );
        } );
      }
    );

    describe( title = 'tests one-to-one connections',
      body = function() {
        it( 'expects one-to-one connections to work on two objects', function() {
          transaction {
            var b = entityNew( 'oneb' ).save( { 'name' = '1 - object b' } );
          }

          transaction {
            var result = entityNew( 'onea' ).save( { 'name' = '1 - object a', 'b' = b } );
          }

          var ida = result.getid();
          var idb = b.getid();

          var bina = result.getb();

          expect( bina ).nottobenull();

          var ainb = b.geta();

          expect( ainb ).nottobenull();

          expect( bina.getid() ).tobe( idb ).nottobe( ida );

          expect( ainb.getid() ).tobe( ida ).nottobe( idb );
        } );

        it( 'expects one-to-one connections to work on one object and one pk', function() {
          var b = entityNew( 'oneb' );

          transaction {
            b.save( { 'name' = '2 - object b' } );
          }

          var a = entityNew( 'onea' );

          transaction {
            var result = a.save( { 'name' = '2 - object a', b = b.getid() } );
          }

          var bina = result.getb();

          expect( bina ).nottobenull();

          var ida = result.getid();

          var ainb = bina.geta();

          expect( ainb ).nottobenull();

          var idb = bina.getid();

          expect( bina.getid() ).tobe( idb ).nottobe( ida );

          expect( ainb.getid() ).tobe( ida ).nottobe( idb );

          expect( bina.getname() ).tobe( '2 - object b' );
        } );

        it( 'expects one-to-one connections to work on one object and one struct', function() {
          var a = entityNew( 'onea' );

          transaction {
            var result = a.save( { 'name' = '3 - object a', b = { 'name' = '3 - object b' } } );
          }

          var bina = result.getb();

          expect( bina ).nottobenull();

          var ida = result.getid();

          var ainb = bina.geta();

          expect( ainb ).nottobenull();

          var idb = bina.getid();

          expect( bina.getid() ).tobe( idb ).nottobe( ida );

          expect( ainb.getid() ).tobe( ida ).nottobe( idb );

          expect( bina.getname() ).tobe( '3 - object b' );
        } );
      }
    );
  }
}