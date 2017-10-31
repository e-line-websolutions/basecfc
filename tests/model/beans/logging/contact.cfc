component extends="root.model.beans.logging.logged" persistent=true joinColumn="id" {
  property email;
  property name="createdObjects" singularname="createdObject" fieldtype="one-to-many" cfc="root.model.beans.logging.logged" FKColumn="createcontactid";
  property name="updatedObjects" singularname="updatedObject" fieldtype="one-to-many" cfc="root.model.beans.logging.logged" FKColumn="updatecontactid";
}