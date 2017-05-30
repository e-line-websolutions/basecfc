component extends="basecfc.base" persistent=true {
  property name="name" type="string" length=128;
  property name="deleted" type="boolean" ORMType="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ORMType="integer" default=0;

  property name="entitiesInSubFolder" singularName="entityInSubFolder" fieldtype="one-to-many" cfc="root.model.beans.sub.other" fkColumn="testid";
  property name="multiples" singularName="multiple" fieldtype="one-to-many" cfc="root.model.beans.multiple" fkColumn="testid";
  property name="more" fieldtype="many-to-one" cfc="root.model.beans.more" fkColumn="moreid";
  property name="duplicate" fieldtype="many-to-one" cfc="root.model.beans.more" fkColumn="duplicateid";
  property name="test";
}