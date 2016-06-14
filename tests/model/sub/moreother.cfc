component extends=basecfc.base persistent=true {
  property name="name" type="string" length=128;
  property name="deleted" type="boolean" ORMType="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ORMType="integer" default=0;

  property name="others" singularName="other" fieldtype="one-to-many" cfc="root.model.sub.other" fkColumn="moreotherid";
}