component extends="basecfc.base" persistent=true {
  property name="name" type="string" length=128;
  property name="deleted" type="boolean" ORMType="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ORMType="integer" default=0;

  property name="a" fieldtype="one-to-one" cfc="root.model.beans.o2o.oneA" fkcolumn="a_id";
}