component extends="basecfc.base" persistent=true {
  property name="entitiesInSubfolder" singularName="entityInSubfolder" fieldtype="one-to-many" cfc="root.model.sub.other" fkColumn="testid";
  property name="more" fieldtype="many-to-one" cfc="root.model.more" fkColumn="moreid";
  property name="duplicate" fieldtype="many-to-one" cfc="root.model.more" fkColumn="duplicateid";
  property name="test";
}