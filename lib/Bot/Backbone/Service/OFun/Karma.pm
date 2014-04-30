package Bot::Backbone::Service::OFun::Karma;
use Bot::Backbone::Service;

with qw(
    Bot::Backbone::Service::Role::Service
    Bot::Backbone::Service::Role::Responder
    Bot::Backbone::Service::Role::Storage
);

service_dispatcher as {
    command '!score' => given_parameters {
        parameter 'thing' => ( match_original => qr/.+/ );
    } respond_by_method 'score_of_thing';

    command '!best' => respond_by_method 'best_scores';
    command '!score' => respond_by_method 'best_scores';
    command '!worst' => respond_by_method 'worst_scores';

    command '!score_alias' => given_parameters {
        parameter 'this' => ( match => qr/.+/ );
        parameter 'that' => ( match => qr/.+/ );
    } respond_by_method 'alias_this_to_that';
    command '!score_alias' => given_parameters {
        parameter 'this' => ( match => qr/.+/ );
    } respond_by_method 'show_alias_of_this';
    command '!score_unalias' => given_parameters {
        parameter 'this' => ( match => qr/.+/ );
    } respond_by_method 'unalias_this';

    not_command run_this_method 'update_scores';
};

sub load_schema {
    my ($self, $conn) = @_;

    $conn->run(fixup => sub {
        $_->do(q[
            CREATE TABLE IF NOT EXISTS karma_score(
                name varchar(255),
                score int,
                PRIMARY KEY (name)
            )
        ]);

        $_->do(q[
            CREATE TABLE IF NOT EXISTS karma_alias(
                name varchar(255),
                score_as varchar(255),
                PRIMARY KEY (name)
            );
        ]);
    });
}

sub update_scores {
    my ($self, $message) = @_;

    my @args = $message->all_args;
    THING: for my $i (0 .. $#args) {
        my $arg  = $args[$i];
        my $name = $arg->text;

        # word by itself, join it to the previous maybe?
        if ($name eq '++' or $name eq '--') {

            # Can't be postfix ++/-- if it's the first thing
            next THING unless $i > 0;

            # Ignore if there's space between ++/-- and the previous thing
            next THING unless $args[$i-1]->original =~ /\S$/;

            # Looks legit, join the last word to this for the vote
            $name = $args[$i-1]->text . $name;
        }

        if ($name =~ s/(\+\+|--)$//) {
            my $direction = $1 eq '++' ? +1 : -1;

            # No empty string votes
            next THING unless $name;

            # No file permissions
            next THING if $name =~ /^[d-][r-][w-][x-][r-][w-][sx-][r-][w-]?[tx-]?/;

            # And there should be at least a couple word chars
            next THING unless $name =~ /\w.*?\w/;

            $self->db_conn->txn(fixup => sub {
                $_->do(q[
                    INSERT OR IGNORE INTO karma_score(name, score)
                    VALUES (?, ?)
                ], undef, $name, 0);
            
                $_->do(q[
                    UPDATE karma_score
                       SET score = score + ?
                     WHERE name = ?
                ], undef, $direction, $name);
            });
        }
    }
}

sub score_of_thing {
    my ($self, $message) = @_;

    my $thing = $message->parameters->{thing};

    my ($score) = $self->db_conn->txn(fixup => sub {
        my ($score_as) = $_->selectrow_array(q[
            SELECT score_as
              FROM karma_alias
             WHERE name = ?
        ], undef, $thing);

        $thing = $score_as if defined $score_as;
        my $sth = $_->prepare(q[
            SELECT ks.score + COALESCE(SUM(kas.score), 0)
              FROM karma_score ks
         LEFT JOIN karma_alias ka ON ks.name = ka.score_as
         LEFT JOIN karma_score kas ON ka.name = kas.name
             WHERE ks.name = ?
        ]);

        $sth->execute($thing);

        $sth->fetchrow_array;
    });

    $score //= 0;

    return "$thing: $score";
}

sub show_alias_of_this {
    my ($self, $message) = @_;

    my $this = $message->parameters->{this};

    my $aliases = $self->db_conn->run(fixup => sub {
        $_->selectall_arrayref(q[
            SELECT name, score_as
              FROM karma_alias
             WHERE name = ? OR score_as = ?
        ], undef, $this, $this);
    });

    return qq[Nothing aliases to or from "$this".] unless @$aliases;

    my ($scored_as, @included_scores);
    for my $alias (@$aliases) {
        my ($name, $score_as) = @$alias;
        if ($name eq $this) {
            $scored_as = $score_as;
        }
        else {
            push @included_scores, qq["$name"];
        }
    }

    my @messages;
    push @messages, qq[Warning: "$this" has aliases to and from for scoring, which is not supposed to happen.]
        if $scored_as and @included_scores;

    push @messages, qq[Scores for "$this" are counted for "$scored_as" instead.]
        if $scored_as;

    my $comma;
    if (@included_scores == 2) {
        $comma = ' and ';
    }
    elsif (@included_scores > 2) {
        $comma = ', ';
        $included_scores[-1] = 'and ' . $included_scores[-1];
    }

    push @messages, qq[Scores for "$this" also include ].join($comma, @included_scores)."."
        if @included_scores;

    return @messages;
}

sub alias_this_to_that {
    my ($self, $message) = @_;

    my $this = $message->parameters->{this};
    my $that = $message->parameters->{that};

    $self->db_conn->txn(fixup => sub {
        $_->do(q[
            DELETE FROM karma_alias
            WHERE name = ? OR score_as = ? OR name = ?
        ], undef, $this, $this, $that);

        $_->do(q[
            INSERT INTO karma_alias(name, score_as)
            VALUES (?, ?)
        ], undef, $this, $that);
    });

    return qq[Scores for "$this" will count for "$that" instead.];
}

sub unalias_this {
    my ($self, $message) = @_;

    my $this = $message->parameters->{this};

    $self->db_conn->run(fixup => sub {
        $_->do(q[
            DELETE FROM karma_alias
            WHERE name = ?
        ], undef, $this);
    });

    return qq[Scores for "$this" will count for "$this" now.];
}

sub best_scores {
    my ($self, $message) = @_;
    return $self->_n_scores(best => 10);
}

sub worst_scores {
    my ($self, $message) = @_;
    return $self->_n_scores(worst => 10);
}

sub _n_scores {
    my ($self, $which, $n) = @_;

    my $direction = $which eq 'best' ? 'DESC' : 'ASC';
    my ($scores) = $self->db_conn->run(fixup => sub {
        $_->selectall_arrayref(qq[
            SELECT ks.name, ks.score + COALESCE(SUM(kas.score), 0)
              FROM karma_score ks
         LEFT JOIN karma_alias kb ON ks.name = kb.name
         LEFT JOIN karma_alias ka ON ks.name = ka.score_as
         LEFT JOIN karma_score kas ON ka.name = kas.name
             WHERE kb.name IS NULL
          GROUP BY ks.name
          ORDER BY SUM(ks.score) $direction
             LIMIT $n
        ]);
    });

    return "No scores." unless @$scores;

    return map { "$_->[0]: $_->[1]" } @$scores;
}

sub initialize { }

__PACKAGE__->meta->make_immutable;
