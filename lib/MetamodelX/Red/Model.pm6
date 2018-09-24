use Red::Model;
use Red::Attr::Column;
use Red::Column;
use Red::Utils;
use Red::ResultSeq;
use Red::DefaultResultSeq;
use Red::Attr::ReferencedBy;
use Red::Attr::Query;
use Red::AST;
use Red::AST::Insert;
use Red::AST::Update;
use Red::AST::Infixes;
use Red::AST::CreateTable;
use MetamodelX::Red::Comparate;
use MetamodelX::Red::Relationship;

unit class MetamodelX::Red::Model is Metamodel::ClassHOW;
also does MetamodelX::Red::Comparate;
also does MetamodelX::Red::Relationship;

has %!columns{Attribute};
has Red::Column %!references;
has %!attr-to-column;
has %.dirty-cols is rw;
has $.rs-class;
has @!constraints;

method references(|) { %!references }
method constraints(|) { @!constraints.classify: *.key, :as{ .value } }

method table(Mu \type) { camel-to-snake-case type.^name }
method rs-class-name(Mu \type) { "{type.^name}::ResultSeq" }
method columns(|) is rw {
	%!columns
}

method id(Mu \type) {
	%!columns.keys.grep(*.column.id).list
}

method id-values(Red::Model:D $model) {
	self.id($model).map({ .get_value: $model }).list
}

multi method id-filter(Red::Model:D $model) {
    $model.^id.map({ Red::AST::Eq.new: .column, Red::AST::Value.new: :value(.get_value: $model), :type(.type) })
        .reduce: { Red::AST::AND.new: $^a, $^b }
}

multi method id-filter(Red::Model:U $model, $id) {
    die "Model must have only 1 id to use id-filter this way" if $model.^id.elems != 1;
    self.id-filter: $model, |{$model.^id.head.column.attr-name => $id}
}

multi method id-filter(Red::Model:U $model, *%data) {
    $model.^id.map({ Red::AST::Eq.new: .column, Red::AST::Value.new: :value(%data{.column.attr-name}), :type(.type) })
        .reduce: { Red::AST::AND.new: $^a, $^b }
}

method attr-to-column(|) is rw {
	%!attr-to-column
}

method compose(Mu \type) {
    type.^prepare-relationships;
	if $.rs-class === Any {
		my $rs-class-name = $.rs-class-name(type);
		if try ::($rs-class-name) !~~ Nil {
			$!rs-class = ::($rs-class-name)
		} else {
			$!rs-class := create-resultseq($rs-class-name, type);
			type.WHO<ResultSeq> := $!rs-class
		}
	}
	die "{$.rs-class.^name} should do the Red::ResultSeq role" unless $.rs-class ~~ Red::ResultSeq;
	self.add_role: type, Red::Model;
	type.^compose-columns;
	self.add_role: type, role :: {
		method TWEAK(|) {
			self.^set-dirty: self.^columns
		}
	}
	self.Metamodel::ClassHOW::compose(type);
	for type.^attributes -> $attr {
		%!attr-to-column{$attr.name} = $attr.column.name if $attr ~~ Red::Attr::Column:D;
	}
}

method add-reference($name, Red::Column $col) {
	%!references{$name} = $col
}

method add-unique-constraint(Mu:U \type, &columns) {
        @!constraints.push: "unique" => columns(type)
}

my UInt $alias_num = 1;
method alias(Red::Model:U \type, Str $name = "{type.^name}_{$alias_num++}") {
	my \alias = Metamodel::ClassHOW.new_type(:$name);
	alias.HOW does MetamodelX::Red::Comparate;
	for %!columns.keys -> $col {
		alias.^add-comparate-methods: $col
	}
	alias.^compose;
	alias
}

method add-column(Red::Model:U \type, Red::Attr::Column $attr) {
	%!columns ∪= $attr;
	my $name = $attr.column.attr-name;
	with $attr.column.references {
		self.add-reference: $name, $attr.column
	}
	type.^add-comparate-methods($attr);
	if $attr.has_accessor {
		if $attr.rw {
			type.^add_multi_method: $name, method (Red::Model:D: Bool :$clean = False) is rw {
				my \obj = self;
				Proxy.new:
					FETCH => method {
						$attr.get_value: obj
					},
					STORE => method (\value) {
						return if value === $attr.get_value: obj;
						obj.^set-dirty: $attr unless $clean;
						$attr.set_value: obj, value;
					}
				;
			}
		} else {
			type.^add_multi_method: $name, method (Red::Model:D:) {
				$attr.get_value: self
			}
		}
	}
}

method compose-columns(Red::Model:U \type) {
	for type.^attributes.grep: Red::Attr::Column -> Red::Attr::Column $attr {
		type.^add-column: $attr
	}
}

method set-dirty(\obj, $attr) {
	self.dirty-cols{obj} ∪= $attr;
}
method is-dirty(Any:D \obj)         { so self.dirty-cols{obj} }
method clean-up(Any:D \obj)         { self.dirty-cols{obj} = set() }
method dirty-columns(Any:D \obj)    { self.dirty-cols{obj} }
method rs($)                        { $.rs-class.new }
method all($obj)                    { $obj.^rs }

method create-table(\model) {
    $*RED-DB.execute: Red::AST::CreateTable.new: :name(model.^table), :columns[|model.^columns.keys.map(*.column)]
}

multi method save($obj, Bool :$insert! where * == True) {
    my $ret := $*RED-DB.execute: Red::AST::Insert.new: $obj;
    $obj.^clean-up;
    $ret
}

multi method save($obj, Bool :$update where * == True = True) {
    my $ret := $*RED-DB.execute: Red::AST::Update.new: $obj;
    $obj.^clean-up;
    $ret
}

method create(\model, |pars) {
    my $obj = model.new: |pars;
    $obj.^save: :insert;
    $obj
}

method load(Red::Model:U \model, |ids) {
    my $filter = model.^id-filter: |ids;
    model.^rs.grep({ $filter }).head
}

method search(Red::Model:U \model, Red::AST $filter) {
    model.^rs.grep: { $filter }
}
