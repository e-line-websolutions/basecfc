component{
  this.name = "basecfctests";
  this.mappings = {
    "/root" = getDirectoryFromPath( getCurrentTemplatePath()),
    "/testbox" = "G:\Dropbox\Projects\thirdparty\testbox"
  };
  this.datasource = "basecfc";
  this.ORMEnabled = true;
  this.ORMSettings = {
    CFCLocation = "/root/model",
    dbcreate = "dropcreate",
    flushatrequestend = false,
    automanageSession = false
  };
}