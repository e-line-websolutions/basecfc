component extends=basecfc.base persistent=true {
  property name="others" singularName="other" fieldtype="one-to-many" cfc="root.model.sub.other" fkColumn="moreotherid";
}