=head2 Red::HiddenFromSQLCommenting

#| Trait for not adding SQL comments for this function
multi trait_mod:<is>(Method $r, Bool :$hidden-from-sql-commenting!) is export {
    $r does role {
        method is-hidden-from-sql-commenting { True }
    }
}
