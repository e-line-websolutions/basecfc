component extends=basecfc.base persistent=true {
  property name="name" type="string" length=128;
  property name="deleted" type="boolean" ormtype="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ormtype="integer" default=0;

  property name="testa" fieldtype="many-to-one" cfc="basecfc.tests.orm.fact-schema.testa" fkcolumn="testaid";
  property name="testb" fieldtype="many-to-one" cfc="basecfc.tests.orm.fact-schema.testb" fkcolumn="testbid";
}