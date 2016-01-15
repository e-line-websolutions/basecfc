component extends=basecfc.base persistent=true {
  property name="tests" singularName="test" fieldtype="one-to-many" cfc="root.model.test" fkColumn="moreid";
  property name="deeper" fieldtype="many-to-one" cfc="root.model.deeper" fkColumn="deeperid";
}