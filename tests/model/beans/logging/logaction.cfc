component extends="root.model.beans.logging.option" persistent=true table="option" discriminatorValue="logaction" {
  property name="cssclass" length=32;
  property name="logentries" singularName="logentry" fieldType="one-to-many" cfc="root.model.beans.logging.logentry" fkColumn="logactionid";
}