component extends=basecfc.base persistent=true {
  property name="mores" singularName="more" fieldtype="one-to-many" cfc="root.model.more" fkColumn="deeperid";
}