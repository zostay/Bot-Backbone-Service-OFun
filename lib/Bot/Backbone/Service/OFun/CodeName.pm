package Bot::Backbone::Service::OFun::CodeName;
use Bot::Backbone::Service;

with qw(
    Bot::Backbone::Service::Role::Service
    Bot::Backbone::Service::Role::Responder
    Bot::Backbone::Service::Role::Storage
);

use File::Slurp qw( read_file );
use MooseX::Types::Path::Class;
use Digest::SHA qw( sha1 );
use List::Util qw( reduce );

service_dispatcher as {
    command '!codename' => given_parameters {
        parameter 'phrase' => ( match_original => qr/.+/ );
    } respond_by_method 'assign_codename';
};

for my $part (qw( adjective noun )) {
    my $part_file = "${part}s_file";
    has $part_file => (
        is         => 'ro',
        isa        => 'Path::Class::File',
        required   => 1,
        coerce     => 1,

    );

    __PACKAGE__->meta->add_method("_build_${part}s" => sub {
        my $self = shift;
        my @words = map { chomp; s/\s+$//; s/^\s+//; $_ } read_file($self->$part_file);
        return \@words;
    });

    has "${part}s" => (
        is         => 'ro',
        isa        => 'ArrayRef[Str]',
        lazy_build => 1,
        traits     => [ 'Array' ],
        handles    => {
            "get_${part}"    => 'get',
            "${part}s_count" => 'count',
        },
    );
}

sub load_schema {
    my ($self, $conn) = @_;

    $conn->run(fixup => sub {
        $_->do(q[
            CREATE TABLE IF NOT EXISTS codenames(
                name varchar(255),
                alias varchar(255),
                is_code_name integer,
                PRIMARY KEY (name)
            )
        ]);
    });
}

sub assign_codename {
    my ($self, $message) = @_;

    my $phrase = lc $message->parameters->{phrase};
    $phrase =~ s/^\s+//;
    $phrase =~ s/\s+$//;
    $phrase =~ s/\s+/ /g;

    my $alias = $self->find_key($phrase);
    if (defined $alias) {
        return $alias;
    }

    my $code_name = $self->generate_code_name($phrase);
    if ($code_name) {
        $self->store_key($code_name => $phrase, 1);
        $self->store_key($phrase => $code_name, 0);

        return $code_name;
    }
    else {
        return "Too many duplicates. Can't come up with a code name for that. Maybe you need to expand your adjectives or nouns list.";
    }
}

sub generate_code_name {
    my ($self, $phrase) = @_;
    my $try_phrase = $phrase;

    my $max_tries = 5;
    TRY: while ($max_tries >= 0) {
        my $inv_phrase = reverse $try_phrase;

        my $raw_adj_index  = reduce { $a ^ $b } unpack "L*", sha1($try_phrase);
        my $raw_noun_index = reduce { $a ^ $b } unpack "L*", sha1($inv_phrase);

        my $adj_index  = $raw_adj_index  % $self->adjectives_count;
        my $noun_index = $raw_noun_index % $self->nouns_count;

        my $adjective = $self->get_adjective($adj_index);
        my $noun      = $self->get_noun($noun_index);
        my $code_name = join ' ', $adjective, $noun;

        # Duplicate check
        my $pair = $self->find_key($code_name);
        if ($pair) {
            $try_phrase = $try_phrase . '\0' . $phrase;
            $max_tries--;
            next TRY;
        }

        return $code_name;
    } 

    return;
}

sub find_key {
    my ($self, $key) = @_;

    my ($alias) = $self->db_conn->run(fixup => sub {
        my $sth = $_->prepare(q[
            SELECT alias
            FROM codenames
            WHERE name = ?
        ]);
        $sth->execute($key);
        $sth->fetchrow_array;
    });

    return $alias;
}

sub store_key {
    my ($self, $key, $alias, $iscn) = @_;

    $self->db_conn->run(fixup => sub {
        $_->do(q[
            INSERT INTO codenames(name, alias, is_code_name)
            VALUES (?, ?, ?)
        ], undef, $key, $alias, $iscn);
    });
}

sub initialize { }

__PACKAGE__->meta->make_immutable;
