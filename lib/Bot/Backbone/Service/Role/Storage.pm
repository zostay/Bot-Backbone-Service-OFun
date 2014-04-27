package Bot::Backbone::Service::Role::Storage;
use Moose::Role;

use DBIx::Connector;

# ABSTRACT: Helper for adding storage to standard modules

has db_dsn => (
    is          => 'ro',
    isa         => 'Str',
    required    => 1,
);

has db_user => (
    is          => 'ro',
    isa         => 'Str',
    predicate   => 'has_db_user',
);

has db_password => (
    is          => 'ro',
    isa         => 'Str',
    predicate   => 'has_db_password',
);

has db_conn => (
    is          => 'ro',
    isa         => 'DBIx::Connector',
    lazy_build  => 1,
);

sub _build_db_conn {
    my $self = shift;

    my $conn = DBIx::Connector->new(
        $self->db_dsn, $self->db_user, $self->db_password, {
            RaiseError => 1,
        },
    );

    $self->load_schema($conn);

    return $conn;
}

requires 'load_schema';

1;
