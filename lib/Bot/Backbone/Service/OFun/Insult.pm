package Bot::Backbone::Service::OFun::Insult;
use Bot::Backbone::Service;

with qw(
    Bot::Backbone::Service::Role::Service
    Bot::Backbone::Service::Role::Responder
);

use Acme::Scurvy::Whoreson::BilgeRat;

service_dispatcher as {
    command '!insult' => given_parameters {
        parameter 'thing' => ( match_original => qr/.+/ );
    } respond_by_method 'insult_the_thing';
};

has language => (
    is          => 'ro',
    isa         => 'Str',
    required    => 1,
    default     => 'pirate',
);

has insult_generator => (
    is          => 'ro',
    isa         => 'Acme::Scurvy::Whoreson::BilgeRat',
    lazy_build  => 1,
);

sub _build_insult_generator {
    my $self = shift;
    my $language = $self->language;

    return Acme::Scurvy::Whoreson::BilgeRat->new(
        language => $language,
    );
}

sub insult_the_thing {
    my ($self, $message) = @_;

    my $thing = $message->parameters->{thing};

    my $insult = ''.$self->insult_generator;
    my $a = $insult =~ /^[aeiou]/i ? 'an' : 'a';
    return "$thing is $a $insult.";
}

sub initialize { }

__PACKAGE__->meta->make_immutable;
