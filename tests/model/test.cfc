component extends="basecfc.base" persistent=true {
  property name="entitiesInSubFolder" singularName="entityInSubFolder" fieldtype="one-to-many" cfc="root.model.sub.other" fkColumn="testid";
  property name="multiples" singularName="multiple" fieldtype="one-to-many" cfc="root.model.multiple" fkColumn="testid";
  property name="more" fieldtype="many-to-one" cfc="root.model.more" fkColumn="moreid";
  property name="duplicate" fieldtype="many-to-one" cfc="root.model.more" fkColumn="duplicateid";
  property name="test";
}