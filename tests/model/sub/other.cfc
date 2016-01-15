component extends=basecfc.base persistent=true {
  property name="test" fieldtype="many-to-one" cfc="root.model.test" fkColumn="testid";
  property name="moreother" fieldtype="many-to-one" cfc="root.model.sub.moreother" fkColumn="moreotherid";
}