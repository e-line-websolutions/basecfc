component extends=basecfc.base persistent=true {
  property name="name" type="string" length=128;
  property name="deleted" type="boolean" ormtype="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ormtype="integer" default=0;

  property name="tests" singularname="test" fieldtype="one-to-many" inverse="true" cfc="basecfc.tests.orm.test" fkcolumn="moreid" cascade="delete-orphan";
  property name="secondtests" singularname="secondtest" fieldtype="one-to-many" inverse="true" cfc="basecfc.tests.orm.test" fkcolumn="duplicateid" cascade="delete-orphan";
  property name="deeper" fieldtype="many-to-one" cfc="basecfc.tests.orm.deeper" fkcolumn="deeperid";
}