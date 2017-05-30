component extends="basecfc.base" persistent=true {
  property name="name" type="string" length=128;
  property name="deleted" type="boolean" ORMType="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ORMType="integer" default=0;

  property name="stringLength" type="string" length=5;

  this.constraints = {
    stringLength = { size = "1..5" }
  };
}