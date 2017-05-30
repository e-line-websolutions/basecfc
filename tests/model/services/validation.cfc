component accessors=true {
  property component engine;

  public component function init( ) {
    variables.engine = new hyrule.system.core.Hyrule( { stopOnFirstFail = "none" } );
    return this;
  }

  public any function validate( ) {
    return variables.engine.validate( argumentCollection = arguments );
  }
}