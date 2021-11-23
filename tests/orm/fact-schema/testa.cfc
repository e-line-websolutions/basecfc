component extends=basecfc.base persistent=true {
  property name="name" type="string" length=128;
  property name="deleted" type="boolean" ormtype="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ormtype="integer" default=0;

  property name="facttables_a" singularname="facttable_a" fieldtype="one-to-many" inverse="true" cfc="basecfc.tests.orm.fact-schema.facttable" fkcolumn="testaid";
}