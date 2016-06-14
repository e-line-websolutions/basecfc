component entityName="multiple" extends=basecfc.base persistent=true {
  property name="name" type="string" length=128;
  property name="deleted" type="boolean" ORMType="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ORMType="integer" default=0;

  property name="test" fieldtype="many-to-one" cfc="root.model.test" fkColumn="testid";
  property name="multiplesA" singularname="multipleA" fieldtype="many-to-many" cfc="root.model.multiple" fkColumn="multipleBid" inversejoincolumn="multipleAid" linktable="manytomany";
  property name="multiplesB" singularname="multipleB" fieldtype="many-to-many" cfc="root.model.multiple" fkColumn="multipleAid" inversejoincolumn="multipleBid" linktable="manytomany";
}