package Bot::Backbone::Service::OFun::Hailo;
use Bot::Backbone::Service;

with qw(
    Bot::Backbone::Service::Role::Service
    Bot::Backbone::Service::Role::Responder
);

use MooseX::Types::Path::Class;
use Hailo;

service_dispatcher as {
    to_me spoken respond_by_method 'learn_and_reply';
    also not_command spoken not_to_me run_this_method 'learn';
};

has brain_file => (
    is          => 'ro',
    isa         => 'Path::Class::File',
    required    => 1,
    coerce      => 1,
);

has hailo => (
    is          => 'ro',
    isa         => 'Hailo',
    lazy_build  => 1,
);

sub _build_hailo {
    my $self = shift;

    my $brain_file = $self->brain_file;
    return Hailo->new(
        brain => "$brain_file",
    );
}

sub learn_and_reply {
    my ($self, $message) = @_;
    return $self->hailo->learn_reply($message->text);
}

sub learn {
    my ($self, $message) = @_;
    return $self->hailo->learn($message->text);
}

sub initialize { }

__PACKAGE__->meta->make_immutable;
