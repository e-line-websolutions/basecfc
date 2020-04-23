component extends=basecfc.base persistent=true {
  property name="name" type="string" length=128;
  property name="deleted" type="boolean" ormtype="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ormtype="integer" default=0;

  property name="mores" singularname="more" fieldtype="one-to-many" inverse="true" cfc="basecfc.tests.orm.more" fkcolumn="deeperid" cascade="delete-orphan";
}