my class Hash {
    # Has attributes and parent EnumMap declared in BOOTSTRAP
    
    method at_key($key is copy) is rw {
        $key = $key.Str;
        self.exists($key)
          ?? pir::find_method__PPs(EnumMap, 'at_key')(self, $key)
          !! pir::setattribute__0PPsP(my $v, Scalar, '$!whence',
                 -> { pir::find_method__PPs(EnumMap, 'STORE_AT_KEY')(self, $key, $v) } )
    }

    multi method perl(Hash:D \$self:) {
        nqp::iscont($self)
          ?? '{' ~ self.pairs.map({.perl}).join(', ') ~ '}'
          !! '(' ~ self.pairs.map({.perl}).join(', ') ~ ').hash'
    }

    method STORE_AT_KEY(Str \$key, Mu $x is copy) is rw {
        pir::find_method__PPs(EnumMap, 'STORE_AT_KEY')(self, $key, $x);
    }

    method STORE(\$to_store) {
        my $items = $to_store.flat.eager;
        nqp::bindattr(self, EnumMap, '$!storage', pir::new__Ps('Hash'));
        while $items {
            my Mu $x := $items.shift;
            if Enum.ACCEPTS($x) { self.STORE_AT_KEY($x.key.Str, $x.value) }
            elsif EnumMap.ACCEPTS($x) {
                for $x.list { self.STORE_AT_KEY(.key.Str, lvaue) }
            }
            elsif $items { self.STORE_AT_KEY($x.Str, $items.shift) }
            else {
                die 'Odd number of elements found where hash expected'
            }
        }
        self
    }

}


sub circumfix:<{ }>(*@elems) { my $x = Hash.new.STORE(@elems); }
sub hash(*@a, *%h) { my % = @a, %h }
