component extends=basecfc.base persistent=true {
  property name="name" type="string" length=128;
  property name="deleted" type="boolean" ormtype="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ormtype="integer" default=0;

  property name="entitiesinsubfolder" singularname="entityinsubfolder" fieldtype="one-to-many" inverse="true" cfc="basecfc.tests.orm.sub.other" fkcolumn="testid" cascade="delete-orphan";
  property name="multiples" singularname="multiple" fieldtype="one-to-many" inverse="true" cfc="basecfc.tests.orm.multiple" fkcolumn="testid" cascade="delete-orphan";
  property name="more" fieldtype="many-to-one" cfc="basecfc.tests.orm.more" fkcolumn="moreid";
  property name="duplicate" fieldtype="many-to-one" cfc="basecfc.tests.orm.more" fkcolumn="duplicateid";
  property name="test";

  property name="testm2mAs" singularname="testm2mA" fieldtype="many-to-many" cfc="basecfc.tests.orm.test" fkcolumn="testm2mAid" linktable="test2test" inversejoincolumn="testm2mBid";
  property name="testm2mBs" singularname="testm2mB" fieldtype="many-to-many" cfc="basecfc.tests.orm.test" fkcolumn="testm2mBid" linktable="test2test" inversejoincolumn="testm2mAid" inverse=true;

  property name="jsontest" datatype="json" length="8000";
}