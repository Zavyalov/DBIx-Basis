package DBIx::Basis::Object;

use Carp;
use Scalar::Util qw( refaddr );
use List::Util qw( first );
use List::MoreUtils qw( all );
use Sub::Name;

use DBIx::Basis::Handle;
require DBIx::Basis;

use strict;
use warnings;

# Основы объектов и классов
my %BASISES;

# Возвращает основу, ассоциированную с данным объектом или классом.
sub basis {
    my ($self, $basis) = @_;
    my $class = ref $self || $self;

    if (@_ > 1) {
        croak "Can't set basis for '$self': '$basis' is not a valid DBIx::Basis"
            unless $basis->isa('DBIx::Basis');

        $BASISES{refaddr $self || $class} = $basis; # refaddr нужен чтобы не потерять память
                                                     # при повторном bless объекта
    }

    $basis = $BASISES{ref $self ? refaddr $self : $class} || $BASISES{$class};
    return $basis if $basis;

    no strict 'refs';
    my $super = first { $basis = $_->basis } @{"$class\::ISA"};
    $class->basis($basis) if defined $basis;

    return $basis;
}

# Конструирует объект по прототипу.
# Объект может быть повторно переконструирован.
sub new {
    my ($self, $data) = @_;
    my $class = ref $self || $self;

    my $basis = $self->basis || $class->basis || DBIx::Basis->basis( $data->{data_basis} );

    croak "Object basis required"
        unless defined $basis;

    $self = $basis->blank unless ref $self;
    $data = {} unless defined $data;

    bless $self, $class;
    $self->_override($data);

    $basis->set_defaults($self);
    $basis->inflate($self);

    $self->basis($basis);

    return $self;
}

# Не забываем удалять для избежания утечек памяти
sub DESTROY {
    my $self = shift;
    delete $BASISES{refaddr $self};
}

# Этот кусок кода с небольшими изменениями был позаимствован из CPAN-модуля Hash::Merge::Simple.
# Переопределяет содержимое объекта переданными данными.
sub _override {
    my ($self, $data) = @_;

    return $self unless $data;

    for my $key (keys %$data) {
        my $hr = (ref $data->{$key} || '') eq 'HASH';
        my $hl  = ((exists $self->{$key} && ref $self->{$key}) || '') eq 'HASH';

        if ($hr and $hl){
            _override( $self->{$key}, $data->{$key} );
        }
        else {
            $self->{$key} = $data->{$key};
        }
    }

    return $self;
}

# Возвращает идентификатор (primary-ключ) текущего объекта как скаляр/хеш/undef в
# зависимости от количества primary-столбцов, контекста вызова и наличия ключа.
sub id {
    my ($self) = @_;

    my $basis = $self->basis;

    croak "Object basis not set"
        unless defined $basis;

    my @primary = $basis->primary;
    return wantarray ? () : undef unless @primary > 0;

    if (@primary == 1) {
        return $basis->get_column( $self, @primary );
    }

    my %id = map { $_ => $basis->get_column( $self, $_ ) } @primary;
    return wantarray ? %id : \%id;
}

# Выбирает объект из БД по переданному условию (см. SQL::Abstract).
# Если условие не указано, будет попытка его автогенерации по primary-ключам.
# Если ничего не выбралось, вернет пустой список
sub select {
    my ($self, $cond, $columns) = @_;
    my $class = ref $self || $self;

    my $basis = $self->basis || DBIx::Basis->basis( $cond->{data_basis} );

    croak "Object basis required"
        unless defined $basis;

    croak "Bad 'columns' argument"
        if defined $columns && ref $columns ne 'ARRAY';

    # Если условие не передано, сгенерим его по primary-ключам или основе
    if ( !defined $cond && ref $self && ( my @primary = $basis->primary ) > 0 ) {
        $cond = { map { $_ => $basis->get_column($self, $_) } @primary };
    }

    croak "Condition required"
        unless defined $cond;

    my @objs = map $class->new($_), DBIx::Basis::Handle->select_objects($cond, $basis, $columns);

    return wantarray ? @objs : $objs[0];
}

# Обновляет объект в БД по переданному условию (см. SQL::Abstract).
# Если условие не указано, будет обновление по primary-ключу или croak.
# Возвращает результат выполнения запроса.
sub update {
    my ($self, $cond, $columns) = @_;
    my $class = ref $self || $self;

    my $basis = $self->basis || DBIx::Basis->basis( $cond->{data_basis} );

    croak "Object basis required"
        unless defined $basis;

    croak "Bad 'columns' argument"
        if defined $columns && ref $columns ne 'ARRAY';

    # Если условие не передано, сгенерим его по primary-ключам
    if ( !defined $cond && ref $self && ( my @primary = $basis->primary ) > 0 ) {
        $cond = { map { $_ => $basis->get_column($self, $_) } @primary };
    }

    croak "Condition required"
        unless defined $cond;

    return $self->new( DBIx::Basis::Handle->update_object($basis->deflate($self), $cond, $basis, $columns) );
}

# Удаляет объект из БД по переданному условию (см. SQL::Abstract).
# Если условие не указано, будет удаление по primary-ключу или croak.
# Возвращает результат выполнения запроса.
sub delete {
    my ($self, $cond) = @_;
    my $class = ref $self || $self;

    my $basis = $self->basis || DBIx::Basis->basis( $cond->{data_basis} );

    croak "Object basis required"
        unless defined $basis;

    # Если условие не передано, сгенерим его по primary-ключам
    if ( !defined $cond && ref $self && ( my @primary = $basis->primary ) > 0 ) {
        $cond = { map { $_ => $basis->get_column($self, $_) } @primary };
    }

    croak "Condition required"
        unless defined $cond;

    return DBIx::Basis::Handle->delete_object($cond, $basis);
}

# Вставляет новую запись в БД. (см. SQL::Abstract).
# Возвращает объект, сконструированный из новой записи.
sub insert {
    my ($self, $data) = @_;
    my $class = ref $self || $self;

    my $basis = defined $data && defined $data->{data_basis}
               ? DBIx::Basis->basis( $data->{data_basis} )
               : $self->basis || $class->basis;

    croak "Object basis required"
        unless defined $basis;

    unless ( defined $data ) {
        $data = ref $self ? $basis->deflate($self) : {};
    }

    $basis->set_defaults($data);

    return $self->new( DBIx::Basis::Handle->insert_object($data, $basis) );
}

# Заменяет/вставляет новую запись в БД.
# Возвращает объект, сконструированный из новой записи.
sub replace {
    my $self = shift;
    my $class = ref $self || $self;

    my $basis = $self->basis || DBIx::Basis->basis( $self->{data_basis} );

    croak "Object basis required"
        unless defined $basis;

    my @primary = $basis->primary;
    croak "Can't replace object having no primary columns"
        unless @primary > 0;

    my $cond = { map { $_ => $basis->get_column($self, $_) } @primary };
    croak "All primary columns must be defined"
        unless all { defined $_ } values %$cond;

    my $flat;
    unless ( $flat = DBIx::Basis::Handle->update_object( $basis->deflate($self), $cond, $basis ) ) {
        $flat = DBIx::Basis::Handle->insert_object( $basis->deflate($self), $basis );
    }

    return $self->new($flat);
}

# Перехватывает обращения к аксессорам полей объекта.
# Пытается перенаправить вызов соответствующему методу основы и создать
# shortcut в классе объекта.
our $AUTOLOAD;
sub AUTOLOAD {
    my ($self) = @_;
    my ($package, $accessor) = ( $AUTOLOAD =~ /^(.*)::([^:]*)$/ );
    my $basis = $self->basis;

    croak "Can't locate object method \"$accessor\" via package \"$package\""
        unless $basis && $basis->can($accessor);

    my $sub = subname $AUTOLOAD => sub { $basis->$accessor(@_) };

    no strict 'refs';
    *$AUTOLOAD = $sub;

    goto &$sub;
}

1;
