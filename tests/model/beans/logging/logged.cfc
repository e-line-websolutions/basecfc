component extends="basecfc.base" persistent=true {
  property name;
  property type="boolean" name="deleted" default="false";
  property type="numeric" name="sortorder" default=0 ormType="integer";

  property name="createContact" fieldType="many-to-one" FKColumn="createcontactid" cfc="root.model.beans.logging.contact";
  property name="createDate" ORMType="timestamp";
  property name="createIP"  length=15;

  property name="updateContact" fieldType="many-to-one" FKColumn="updatecontactid" cfc="root.model.beans.logging.contact";
  property name="updateDate" ORMType="timestamp";
  property name="updateIP" length=15;

  property name="logEntries" singularName="logEntry" fieldType="one-to-many" cfc="root.model.beans.logging.logentry" FKColumn="entityid";
}