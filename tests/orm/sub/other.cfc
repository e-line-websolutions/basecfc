component extends=basecfc.base persistent=true {
  property name="name" type="string" length=128;
  property name="deleted" type="boolean" ormtype="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ormtype="integer" default=0;

  property name="test" fieldtype="many-to-one" cfc="basecfc.tests.orm.test" fkcolumn="testid";
  property name="moreother" fieldtype="many-to-one" cfc="basecfc.tests.orm.sub.moreother" fkcolumn="moreotherid";
}