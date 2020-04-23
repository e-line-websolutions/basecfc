component extends=basecfc.base persistent=true {
  property name="name" type="string" length=128;
  property name="deleted" type="boolean" ormtype="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ormtype="integer" default=0;

  property name="entitiesinsubfolder" singularname="entityinsubfolder" fieldtype="one-to-many" inverse="true" cfc="basecfc.tests.orm.sub.other" fkcolumn="testid" cascade="delete-orphan";
  property name="multiples" singularname="multiple" fieldtype="one-to-many" inverse="true" cfc="basecfc.tests.orm.multiple" fkcolumn="testid" cascade="delete-orphan";
  property name="more" fieldtype="many-to-one" cfc="basecfc.tests.orm.more" fkcolumn="moreid";
  property name="duplicate" fieldtype="many-to-one" cfc="basecfc.tests.orm.more" fkcolumn="duplicateid";
  property name="test";
  property name="jsontest" datatype="json" length="8000";
}