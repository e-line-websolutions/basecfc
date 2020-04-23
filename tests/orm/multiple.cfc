component extends=basecfc.base persistent=true {
  property name="name" type="string" length=128;
  property name="deleted" type="boolean" ormtype="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ormtype="integer" default=0;

  property name="test" fieldtype="many-to-one" cfc="basecfc.tests.orm.test" fkcolumn="testid";
  property name="multiplesa" singularname="multiplea" fieldtype="many-to-many" cfc="basecfc.tests.orm.multiple" fkcolumn="multiplebid" inversejoincolumn="multipleaid" linktable="manytomany";
  property name="multiplesb" singularname="multipleb" fieldtype="many-to-many" cfc="basecfc.tests.orm.multiple" fkcolumn="multipleaid" inversejoincolumn="multiplebid" linktable="manytomany";
}