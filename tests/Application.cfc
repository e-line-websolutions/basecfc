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

  this.ormSettings.datasource = 'basecfc';
  this.ormSettings.CFCLocation = this.mappings[ '/root' ] & 'orm';
  this.ormSettings.DBCreate = 'dropcreate';
  this.ormSettings.secondaryCacheEnabled = false;
  this.ormSettings.useDBForMapping = false;

  this.ormSettings.autoManageSession = false;
  this.ormSettings.flushAtRequestEnd = false;

  // this.ormSettings.cacheConfig = 'ehcache-config_ORM__basecfc.xml';
  this.ormenabled = true;

  // // this.ormsettings.sqlscript = 'nuke.sql';


  function onRequest() {
    var mstng = new mustang.base({});

    request.appName = "basecfc";
    request.context.config.root = 'basecfc.tests';
    ormReload();
    request.allOrmEntities = mstng.listAllOrmEntities( this.ormSettings.CFCLocation );

    param url.reporter="simple";
    param url.directory="root.specs";
    param url.recurse=true;

    include "/testbox/system/runners/HTMLRunner.cfm";
  }
}