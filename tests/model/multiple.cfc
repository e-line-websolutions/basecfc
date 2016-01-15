component entityName="multiple" extends=basecfc.base persistent=true {
  property name="test" fieldtype="many-to-one" cfc="root.model.test" fkColumn="testid";
}