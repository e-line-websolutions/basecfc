component {
  this.name = 'basecfc_tests';
  this.root = getDirectoryFromPath( getCurrentTemplatePath() ).replace( '\', '/', 'all' );
  this.basecfcRoot = this.root.listDeleteAt( this.root.listLen( '/' ), '/' );

  this.mappings = {
    '/root' = this.root,
    '/basecfc' = this.basecfcRoot,
    '/framework' = expandPath( '../../thirdparty/frameworks' ),
    '/mustang' = expandPath( '../../mustang-shared' ),
    '/testbox' = expandPath( '../../testbox' ),
    '/hyrule' = expandPath( '../../hyrule' )
  };

  this.javaSettings.loadPaths = [ this.mappings[ '/mustang' ] & '/lib/java' ];

  this.ormEnabled = true;

  this.datasource = 'basecfc'; // need global ds, not just in orm

  this.ormSettings.dbCreate = 'dropcreate';
  this.ormSettings.cfcLocation = this.mappings[ '/root' ] & 'orm';
  this.ormSettings.sqlScript = 'nuke.sql';

  function onRequest() {
    request.appName = this.name;
    request.context.config.root = 'basecfc.tests';

    setupORM();

    param url.reporter = "simple";
    param url.directory = "root.specs";
    param url.recurse = true;

    include '/testbox/system/runners/HTMLRunner.cfm';
  }

  private void function setupORM() {
    ormReload();

    request.allOrmEntities = {};

    var cacheKey = 'orm-entities';

    createObject( 'java', 'java.util.Arrays' ).asList( ormGetSessionFactory().getStatistics().getEntityNames() ).each( ( entityName )=>{
      try {
        var entity = getMetadata( entityNew( entityName ) );
        request.allOrmEntities[ entityName ] = { 'name' = entityName, 'table' = isNull( entity.table ) ? entityName : entity.table };
      } catch ( basecfc.init.invalidPropertiesError e ) {
        // allow this error on entity with name "invalid", because that's used for testing
        if ( entityName != 'invalid' ) rethrow;
      }
    } );
  }
}