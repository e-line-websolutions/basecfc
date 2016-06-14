component extends=basecfc.base persistent=true {
  property name="name" type="string" length=128;
  property name="deleted" type="boolean" ORMType="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ORMType="integer" default=0;

  property name="tests" singularName="test" fieldtype="one-to-many" cfc="root.model.test" fkColumn="moreid";
  property name="deeper" fieldtype="many-to-one" cfc="root.model.deeper" fkColumn="deeperid";
}