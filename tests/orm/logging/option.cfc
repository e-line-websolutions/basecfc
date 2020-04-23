component extends=basecfc.base persistent=true table="option" discriminatorcolumn="type" {
  property name="name" type="string" length=128 inlist=true;
  property name="deleted" type="boolean" ormtype="boolean" default=false inapi=false;
  property name="sortorder" type="numeric" ormtype="integer" default=0;

  property persistent=false name="type" inlist=true;
  property persistent=false name="sourcecolumn" inlist=true;

  function gettype() {
    return variables.instance.meta.discriminatorvalue;
  }
}