component extends=basecfc.base persistent=true {
  property name;
  property type="boolean" name="deleted" default="false";
  property type="numeric" name="sortorder" default=0 ormtype="integer";

  property name="createcontact" fieldtype="many-to-one" fkcolumn="createcontactid" cfc="basecfc.tests.orm.logging.contact";
  property name="createdate" ormtype="timestamp";
  property name="createip"  length=15;

  property name="updatecontact" fieldtype="many-to-one" fkcolumn="updatecontactid" cfc="basecfc.tests.orm.logging.contact";
  property name="updatedate" ormtype="timestamp";
  property name="updateip" length=15;

  property name="logentries" singularname="logentry" fieldtype="one-to-many" inverse="true" cfc="basecfc.tests.orm.logging.logentry" fkcolumn="entityid" cascade="delete-orphan";
}