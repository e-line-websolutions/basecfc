component accessors=true {
  property component engine;

  public component function init( ) {
    variables.engine = new hyrule.system.core.hyrule( { stoponfirstfail = "none" } );
    return this;
  }

  public any function validate( ) {
    return variables.engine.validate( argumentcollection = arguments );
  }
}