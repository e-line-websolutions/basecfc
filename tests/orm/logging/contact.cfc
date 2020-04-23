component extends=basecfc.tests.orm.logging.logged persistent=true joincolumn="id" {
  property email;
  property name="createdobjects" singularname="createdobject" fieldtype="one-to-many" inverse="true" cfc="basecfc.tests.orm.logging.logged" fkcolumn="createcontactid" cascade="delete-orphan";
  property name="updatedobjects" singularname="updatedobject" fieldtype="one-to-many" inverse="true" cfc="basecfc.tests.orm.logging.logged" fkcolumn="updatecontactid" cascade="delete-orphan";
  property name="contactlogentries" singularname="contactlogentry" fieldtype="one-to-many" inverse=true cfc="basecfc.tests.orm.logging.logentry" fkcolumn="contactid";
}