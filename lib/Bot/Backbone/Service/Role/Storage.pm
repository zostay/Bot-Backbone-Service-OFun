package Bot::Backbone::Service::Role::Storage;
use Moose::Role;

use DBIx::Connector;

# ABSTRACT: Helper for adding storage to standard modules

=head1 SYNOPSIS

    package MyBot::Service::Thing;
    use Bot::Backbone::Service;

    with qw(
        Bot::Backbone::Service::Role::Service
        Bot::Backbone::Service::Role::Responder
        Bot::Backbone::Service::Role::Storage
    );

    sub load_schema {
        my ($self, $conn) = @_;

        $conn->run(fixup => sub {
            $_->do(q[
                CREATE TABLE IF NOT EXISTS things(
                    name varchar(255),
                    PRIMARY KEY (name)
                )
            ]);
        });
    }

    # More bot service stuff...

=head1 DESCRIPTION

Uses L<DBIx::Connector> to deliver a database handle to a bot service. It
provides attributes for configuration the DBI DSN, username, and password and
automatically manages the connection to the database using L<DBIx::Connector>.

It also provides a sort of callback for loading the schema, which happens when
the connection is first used.

=head1 ATTRIBUTES

=head2 db_dsn

This is the DSN to use when connecting to DBI. See your favorite DBD driver for
details.

=cut

has db_dsn => (
    is          => 'ro',
    isa         => 'Str',
    required    => 1,
);

=head2 db_user

This is the username to use to connect.

=cut

has db_user => (
    is          => 'ro',
    isa         => 'Str',
    predicate   => 'has_db_user',
);

=head2 db_password

This is the password to use when connecting.

=cut

has db_password => (
    is          => 'ro',
    isa         => 'Str',
    predicate   => 'has_db_password',
);

=head2 db_conn

Use this to get at the L<DBIx::Connector> object used to connect to your database.

=cut

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

=head1 REQUIRED METHODS

=head2 load_schema

    $service->load_schema($db_conn);

This is called to create the schema for your database. It is passed a reference
to the newly created L<DBIx::Connector> object. You should use it to run any DDL
statements required to setup your schema. It does nothing to help you handle
different flavors of SQL so if you need to do that, the way you do that is
completely up to you.

B<DO NOT> try to call L</db_conn> on the invocant or your bot will lock up, just
use the one passed in.

=cut

requires 'load_schema';

1;
