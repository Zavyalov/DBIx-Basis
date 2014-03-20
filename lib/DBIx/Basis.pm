package DBIx::Basis;

use Carp;
use Scalar::Util qw( reftype blessed );
use Storable 'dclone';
use Module::Find;

use DBIx::Basis::Object;

our $VERSION = '1.5';

use strict;
use warnings;

# Отработает ровно 1 раз
sub _init_once {
    no warnings 'redefine';
    *_init_once = sub { 0 };
    my $pkg = __PACKAGE__;
    for ( findallmod $pkg ) {
        $_ =~ s/^${pkg}:://;
        $pkg->basis($_);
    }
}

# Внутренности основ
my %BASIS;

# Позволяет использовать запись C<use DBIx::Basis 'Name'>
sub import {
    my ($class, $arg) = @_;
    $class = ref $class || $class;

    _init_once();

    my $caller = (caller)[0];
    return if $caller =~ ('^' . __PACKAGE__);

    croak "Basis name required"
        unless defined $arg;

    croak "Multiple basis definition is not supported"
        if @_ > 2;

    $class .= "::$arg";
    eval "require $class";
    croak "Can't use basis '$arg': $@"
        if $@;

    no strict 'refs';
    push @{"$caller\::ISA"}, 'DBIx::Basis::Object'
        unless $caller->isa('DBIx::Basis::Object');

    $caller->basis($class);
}

# Пытается загрузить нужную основу
# Если не получатеся, делает carp и возвращает undef.
sub basis {
    my ($class, $name) = @_;

    croak "Basis name required"
        unless defined $name;

    $class = "DBIx::Basis::$name";

    unless ( exists $BASIS{$class} ) {
        eval "require $class";
        if ($@) {
            carp $@;
            return undef;
        }
    }

    return $class;
}

# Возвращает имя текущей основы.
sub name {
    $_[0] =~ m/^DBIx::Basis::(.+)$/o; $1;
}

# Устанавливает/возвращает базу данных для основы (см. DBIx::Basis::Handle).
sub db {
    my $class = shift; $class = ref $class || $class;
    $BASIS{$class}{db} = shift if @_ > 0;
    return $BASIS{$class}{db};
}

# Устанавливает/возвращает таблицу с объектами.
sub table {
    my $class = shift; $class = ref $class || $class;
    $BASIS{$class}{table} = shift if @_ > 0;
    return $BASIS{$class}{table};
}

# Устанавливает/возвращает определение для класса.
# Если класс является потомком другого класса с уже заданной основной, новая
# будет получена объединением родительской и переданной.
sub definition {
    my $class = shift; $class = ref $class || $class;

    if (@_ > 0) {
        no strict 'refs';

        my %basises; $basises{$_} = 1 for @{$BASIS{$class}{superbasises}};
        my %primary; $primary{$_} = 1 for @{$BASIS{$class}{primary}};

        # Наследование базовых классов
        for my $super ( @{"$class\::ISA"} )
        {
            next unless exists $BASIS{$super};

            $BASIS{$class}{db}     ||= $BASIS{$super}{db};
            $BASIS{$class}{table}  ||= $BASIS{$super}{table};

            # Запомним все уникальные праосновы текущей основы,
            # а также отметим в них текущую основу как подоснову.
            for ( @{$BASIS{$super}{superbasises}}, $super ) {
                next if $basises{$_};
                $basises{$_} = 1;
                push @{$BASIS{$_}{subbasises}}, $class;
                # FIXME убрать дублирование при множественном наследовании
                push @{$BASIS{$class}{superbasises}}, $super;
            }

            # Запомним все уникальные primary-поля текущей основы
            for ( @{$BASIS{$super}{primary}} ) {
                next if $primary{$_};
                $primary{$_} = 1;
                push @{$BASIS{$class}{primary}}, $_;
            }

            push @{$BASIS{$class}{basis}}, @{$BASIS{$super}{basis}}
                if $BASIS{$super}{basis};

            push @{$BASIS{$class}{defaults}}, @{$BASIS{$super}{defaults}}
                if $BASIS{$super}{defaults};

            push @{$BASIS{$class}{inflators}}, @{$BASIS{$super}{inflators}}
                if $BASIS{$super}{inflators};

            push @{$BASIS{$class}{deflators}}, @{$BASIS{$super}{deflators}}
                if $BASIS{$super}{deflators};

            push @{$BASIS{$class}{columns}}, @{$BASIS{$super}{columns}}
                if $BASIS{$super}{columns};

            @{$BASIS{$class}{column}}{keys %{$BASIS{$super}{column}}} = values %{$BASIS{$super}{column}}
                if $BASIS{$super}{column};
        }

        # Дополнение основы новыми данными
        my $piece = shift;
        push @{$BASIS{$class}{basis}}, @$piece; # TODO Делать переопределение полей
        $class->_traverse_basis($piece);
    }

    return $BASIS{$class}{basis};
}

# Возвращает все подосновы
sub subbasises {
    my $class = shift; $class = ref $class || $class;
    my $subbasises = $BASIS{$class}{subbasises} || [];
    return wantarray ? @$subbasises : [ @$subbasises ];
}

# Возвращает все праосновы
sub superbasises {
    my $class = shift; $class = ref $class || $class;
    my $superbasises = $BASIS{$class}{superbasises} || [];
    return wantarray ? @$superbasises : [ @$superbasises ];
}

# Производит рекурсивный обход, инициализирует внутренности
sub _traverse_basis {
    my $class = shift;
    my @tier = @{+shift};

    while ( my $attr = shift @tier ) {
        if ( ref $tier[0] && reftype $tier[0] eq 'HASH' ) {
            my $opt = shift @tier;

            if ($opt->{primary}) {
                $opt->{column} ||= $attr;
                push @{$BASIS{$class}{primary}}, $attr unless grep { $_ eq $attr } @{$BASIS{$class}{primary}};
            }

            if ($opt->{column}) {
                $opt->{column} = $attr if $opt->{column} eq '1';
                push @{$BASIS{$class}{columns}}, $opt->{column}
                    if !exists $BASIS{$class}{column}{$opt->{column}};
                @{$BASIS{$class}{column}{$opt->{column}}} = (@_, $attr);
            }

            push @{$BASIS{$class}{defaults}}, [ [@_, $attr], $opt->{default} ]
                if defined $opt->{default};

            push @{$BASIS{$class}{inflators}}, [ [@_, $attr], $opt->{inflate} ]
                if defined $opt->{inflate};

            push @{$BASIS{$class}{deflators}}, [ [@_, $attr], $opt->{deflate} ]
                if defined $opt->{deflate};
        }

        if ( ref $tier[0] && reftype $tier[0] eq 'ARRAY' ) {
            $class->_traverse_basis(shift @tier, @_, $attr);
        }
    }
}

sub primary {
    my $class = shift;
    my @primary;
    @primary = @{$BASIS{$class}{primary}} if exists $BASIS{$class};
    return wantarray ? @primary : \@primary;
}

sub columns {
    my $class = shift;
    my @columns;
    @columns = @{$BASIS{$class}{columns}} if exists $BASIS{$class};
    return wantarray ? @columns : \@columns;
}

# "Разворачивает" объект из канонического представления
sub inflate {
    my ($basis, $obj) = @_;

    for ( @{$BASIS{$basis}{inflators}} ) {
        my ($path, $infl) = @$_;
        my $val = _get($obj, $path);

        if (ref $infl && reftype $infl eq 'CODE') {
            _set( $obj, $path, $infl->(local $_ = $val) );
            next;
        }

        unless (ref $infl) {
            _set( $obj, $path, ( blessed $obj ? $obj : $basis )
                                    ->$infl(local $_ = $val) );
            next;
        }

        die "Can't inflate object: infalid inflator '$infl'";
    }

    return $obj;
}

# "Сворачивает" объект в каноническое представление
sub deflate {
    my ($basis, $obj) = @_;

    my @deflated_values;

    for ( @{$BASIS{$basis}{deflators}} ) {
        my ($path, $defl) = @$_;
        my $val = _get($obj, $path);

        if (ref $defl && reftype $defl eq 'CODE') {
            push @deflated_values, [ $path, $defl->(local $_ = $val) ];
            next;
        }

        unless (ref $defl) {
            push @deflated_values, [ $path, ( blessed $obj ? $obj : $basis )
                                                ->$defl(local $_ = $val) ];
            next;
        }

        die "Can't deflate object: infalid deflator '$defl'";
    }

    $obj = $basis->_filter($obj);
    _set( $obj, @$_ ) for @deflated_values;

    return $obj;
}

# Рекурсивно создает "пустой" объект заданной структуры
sub blank {
    my ($basis, $tier) = @_;
    $tier ||= $BASIS{$basis}{basis};

    my $out = {}; my $key = '';
    for ( my $i = 0; $i < @$tier; $i++ ) {
        unless ( ref $tier->[$i] ) {
            $key = $tier->[$i];
            $out->{$key} = undef;
            next;
        }

        if ( reftype $tier->[$i] eq 'ARRAY' ) {
            $out->{$key} = $basis->blank( $tier->[$i] );
        }
    }

    return $out;
}

# Рекурсивно копирует в новый объект из исходного данные, объявленные в основе
sub _filter {
    my ($basis, $raw, $tier) = @_;
    $tier ||= $BASIS{$basis}{basis};

    my $out = {}; my $key = '';
    for ( my $i = 0; $i < @$tier; $i++ ) {
        unless ( ref $tier->[$i] ) {
            $key = $tier->[$i];
            $out->{$key} = $raw->{$key};
            next;
        }

        if ( reftype $tier->[$i] eq 'ARRAY' ) {
            if ( !ref $raw->{$key} || reftype $raw->{$key} ne 'HASH' ) {
                warn "Object '$raw' doesn't match its basis in tier '$tier' - "
                    . "there must be a HASH reference under key '$key'"
                        if exists $raw->{$key};
                $out->{$key} = $basis->blank( $tier->[$i] );
            }
            else {
                $out->{$key} = $basis->_filter( $raw->{$key}, $tier->[$i] );
            }
        }
    }

    return $out;
}

# Устанавливает в объекте все ""-поля в undef, похоже на filter
sub set_undefs {
    my ($basis, $obj, $tier) = @_;
    $tier ||= $BASIS{$basis}{basis};

    my $key = '';
    for ( my $i = 0; $i < @$tier; $i++ ) {
        unless ( ref $tier->[$i] ) {
            $key = $tier->[$i];
            $obj->{$key} = undef if defined $obj->{$key} && $obj->{$key} eq q{};
            next;
        }

        if ( reftype $tier->[$i] eq 'ARRAY' ) {
            if ( !ref $obj->{$key} || reftype $obj->{$key} ne 'HASH' ) {
                croak "There must be a HASH reference under key '$key'"
                        if exists $obj->{$key};
            }
            else {
                $basis->set_undefs( $obj->{$key}, $tier->[$i] );
            }
        }
    }

    return $obj;
}

# Устанавливает в объекте все undef-поля в значения по умолчанию
sub set_defaults {
    my ($basis, $obj) = @_;

    for ( @{$BASIS{$basis}{defaults}} ) {
        my ($p, $v) = @$_;
        next if defined _get( $obj, $p ); # "" более не трактуем как undefined!
        _set( $obj, $p, (ref $v) ? dclone($v) : $v );
    }

    return $obj;
}

# Возвращает значение узла по заданному пути
sub _get {
    my ($self, $path) = @_;
    my $node;

    for ( my $i = 0, $node = $self; defined $node && $i < @$path; $i++ ) {
        my $p = $path->[$i];
        if ( ref $node && reftype $node eq 'HASH' ) {
            $node = $node->{$p};
            next;
        }
        return undef;
    }

    return $node;
}

sub get_column {
    my ($basis, $obj, $col) = @_;
    return _get( $obj, $BASIS{$basis}{column}{$col} );
}

# Присваивает новое значение узлу по заданному пути
sub _set {
    my ($self, $path, $val) = @_;
    my $node;

    for ( my $i = 0, $node = $self; defined $node && $i < $#$path; $i++ ) {
        my $p = $path->[$i];
        $node = $node->{$p} = ( exists $node->{$p} ) ? $node->{$p} : {};
    }

    return $node->{$path->[-1]} = $val;
}

sub set_column {
    my ($basis, $obj, $col, $val) = @_;
    return _set( $obj, $BASIS{$basis}{column}{$col}, $val );
}

# Удаляет узел по заданному пути
sub _del {
    my ($self, $path) = @_;
    my $node;

    for ( my $i = 0, $node = $self; defined $node && $i < $#$path; $i++ ) {
        my $p = $path->[$i];
        $node = $node->{$p} = ( exists $node->{$p} ) ? $node->{$p} : {};
    }

    return delete $node->{$path->[-1]};
}

sub del_column {
    my ($basis, $obj, $col) = @_;
    return _del( $obj, $BASIS{$basis}{column}{$col} );
}

1;

__END__

=head1 NAME

DBIx::Basis - лёгкий ORM на основе SQL::Abstract

=head1 SINOPSYS

  package DBIx::Basis::Foo;
  use base 'DBIx::Basis';

  __PACKAGE__->db('mydata');
  __PACKAGE__->table('foos');
  __PACKAGE__->definition([
    'foo_id' => { primary => 1 },
    'name' => { column => 1 },
    'stuff' => [
      'a', 'b',
      'c' => { column => 'stuff_c' },
    ],
  ]);

  package My::Foo;
  use DBIx::Basis 'Foo';
  # any object methods here

  package main;
  use My::Foo;
  use DBIx::Basis::Handle;
  use Data::Dumper;

  $foo = My::Foo->select({ foo_id => 1 });
  die "Can't load foo" unless defined $foo;

  $foo->{name} = 'Giant foo';
  $foo->{stuff}{c} = 42;
  $foo->update();

  Dumper DBIx::Basis::Handle->mydata->selectrow_hashref(
    'SELECT * FROM foos WHERE food_id = ?', undef, 1
  );

  $VAR1 = {
    'foo_id' => 1,
    'name' => 'Giant foo',
    'stuff_c' => 42,
    'data_basis' => 'Foo',
    'data' => '{"stuff":{"a":null,"b":null}}',
  }

=head1 METHODS

=head2 new( [ \%proto ] )

=head2 select( [ \%cond ] )

=head2 update( [ \%cond ] )

=head2 delete( [ \%cond ] )

=head2 insert( [ \%cond ] )

=head1 DEPENDENCIES

=item * L<SQL::Abstract>

=item * L<JSON>

=head1 TODO

=item * Возможно, написать метод C<update_or_insert>.

=item * Написать POD к методам C<new>, C<select>, C<update>, C<insert> и C<delete>.

=item * Удалять аттрибуты-столбцы при сохранении объектов.

=head1 AUTHOR

Artem S. Vybornov, L<mailto: vibornoff@gmail.com>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
