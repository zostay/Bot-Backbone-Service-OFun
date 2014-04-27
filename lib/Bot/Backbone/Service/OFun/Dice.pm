package Bot::Backbone::Service::OFun::Dice;
use Bot::Backbone::Service;

with qw(
    Bot::Backbone::Service::Role::Service
    Bot::Backbone::Service::Role::Responder
);

use List::MoreUtils qw( any );
use List::Util qw( shuffle );
use Readonly;

Readonly my $DICE_NOTATION => qr/(?<count>\d+)?d(?<sides>\d+)(?<modifier>[+-]\d+)?/i;
Readonly my @COIN_SIDES => qw( heads tails );

service_dispatcher as {
    command '!roll' => given_parameters {
        parameter 'dice' => (
            match   => $DICE_NOTATION,
            default => 'd6',
        );
    } respond_by_method 'roll_dice';

    command '!flip' => given_parameters {
        parameter 'count' => ( match => qr/\d+/, default => 1 );
    } respond_by_method 'flip_coin';

    command '!choose' => given_parameters {
        parameter 'count' => ( match => qr/\d+/ );
        parameter 'items' => ( match_original => qr/.+/ );
    } respond_by_method 'choose_n';

    command '!choose' => given_parameters {
        parameter 'items' => (match_original => qr/.+/ );
    } respond_by_method 'choose_n';

    command '!shuffle' => given_parameters {
        parameter 'items' => (match_original => qr/.+/ );
    } respond_by_method 'choose_all';
};

sub roll_dice {
    my ($self, $message) = @_;

    my $dice = $message->parameters->{dice} // 'd6';
    my $success = $dice =~ $DICE_NOTATION;
    return "I don't understand those dice." unless $success;

    my $count    = $+{count} // 1;
    my $sides    = $+{sides} // 6;
    my $modifier = $+{modifier} // 0;

    my @messages;

    return "Not sure what to do with a $sides-sided die."
        unless $sides >= 2;

    if ($count > 100) {
        my $verbing = $sides == 2 ? 'flipping' : 'rolling';
        return "You can't be serious. I'm not $verbing $count times."
    }

    unless (any { $sides == $_ } (2, 4, 6, 8, 10, 12, 20, 100)) {
        push @messages, "You have INTERESTING dice.";
    }

    if ($sides eq 2) {
        my @flips;
        for (1 .. $count) {
            push @flips, $COIN_SIDES[ int($sides * rand()) ];
        }

        push @messages, "Flipped $count times: ".join(', ', @flips);
    }

    else {
        my $sum = 0;
        for (1 .. $count) {
            $sum += int($sides * rand()) + 1;
        }
        $sum += $modifier;

        push @messages, "Rolled $sum";
    }

    return @messages;
}

sub flip_coin {
    my ($self, $message) = @_;

    my $count = $message->parameters->{count};
    $message->parameters->{dice} = $count . 'd2';
    return $self->roll_dice($message);
}

sub choose_n {
    my ($self, $message) = @_;

    my $count = $message->parameters->{count} // 1;
    my $items = $message->parameters->{items};
    $items =~ s/^\s+//;
    $items =~ s/\s+$//;

    my @items = shuffle split /\s+/, $items;
    my $n = scalar @items;

    return "Wise-guy, eh? There's only $n items in that set, I can't pick $count items from it."
        if $count > $n;

    return "I choose " . join(', ', @items[ 0 .. $count-1 ]);
}

sub choose_all {
    my ($self, $message) = @_;

    my $items = $message->parameters->{items};
    $items =~ s/^\s+//;
    $items =~ s/\s+$//;
    my @items = split /\s+/, $items;

    $message->parameters->{count} = scalar @items;

    return $self->choose_n($message);
}

sub initialize { }

__PACKAGE__->meta->make_immutable;
