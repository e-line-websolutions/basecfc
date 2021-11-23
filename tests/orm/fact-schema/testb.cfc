component extends=basecfc.tests.orm.fact-schema.testa joinColumn="id" persistent=true {
  property name="facttables_b" singularname="facttable_b" fieldtype="one-to-many" inverse="true" cfc="basecfc.tests.orm.fact-schema.facttable" fkcolumn="testbid";
}