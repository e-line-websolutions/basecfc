component {
  this.name = 'basecfc_test_1001';
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

  this.datasource = 'basecfc';

  this.ormSettings.dbCreate = 'dropcreate';
  this.ormSettings.cfcLocation = this.mappings[ '/root' ] & 'orm';
  this.ormSettings.sqlScript = 'nuke.sql';

  // this.ormSettings.secondaryCacheEnabled = false;
  // this.ormSettings.useDBForMapping = false;
  // this.ormSettings.autoManageSession = false;
  // this.ormSettings.flushAtRequestEnd = false;
  // this.ormSettings.cacheConfig = 'ehcache-config_ORM__basecfc.xml';

  function onRequest() {
    request.appName = 'basecfc';
    request.context.config.root = 'basecfc.tests';

    ormReload();

    request.allOrmEntities = listAllOrmEntities( this.ormSettings.cfcLocation );

    param url.reporter = "simple";
    param url.directory = "root.specs";
    param url.recurse = true;

    include '/testbox/system/runners/HTMLRunner.cfm';
  }

  private struct function listAllOrmEntities( cfcLocation ) {
    var cacheKey = 'orm-entities';

    var allOrmEntities = {};
    var storedEntityNames = createObject( 'java', 'java.util.Arrays' ).asList( ormGetSessionFactory().getStatistics().getEntityNames() );

    storedEntityNames.each((entityName)=>{
      var entity = getMetadata( entityNew( entityName ) );
      allOrmEntities[ entityName ] = { 'name' = entityName, 'table' = isNull( entity.table ) ? entityName : entity.table };
    });

    return allOrmEntities;
  }


}
