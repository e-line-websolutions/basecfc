component extends=basecfc.tests.orm.logging.option persistent=true table="option" discriminatorvalue="logaction" {
  property name="cssclass" length=32;
  property name="logentries" singularname="logentry" fieldtype="one-to-many" inverse="true" cfc="basecfc.tests.orm.logging.logentry" fkcolumn="logactionid" cascade="delete-orphan";
}