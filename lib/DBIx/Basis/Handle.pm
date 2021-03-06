package DBIx::Basis::Handle;

use DBI;
use Carp;
use Sub::Name;
use SQL::Abstract;
use JSON;
use Scalar::Util 'reftype';
use Data::Dumper;

require DBIx::Basis;

use strict;
use warnings;
no warnings 'once';

use constant DEBUG => $ENV{DBIX_BASIS_DEBUG} || 0;

# Источники данных
my %CONFIG;

# Кеш открытых соединений с БД
my %DBH;

# Время последнего ping
my %PING;

# Генератор SQL-запросов и JSON-сериализатор
my $SQL = SQL::Abstract->new();
my $JSON = JSON->new->ascii;

my $init_complete = 0;
sub init {
    my ($class, $conf) = @_;
    return if $init_complete;

    if (defined $conf) {
        my $data;

        if (ref $conf) {
            $data = $conf;
        }
        else {
            # TODO: придумать хороший способ читать файл с конфигом
            die "$conf should be hashref";
        }

        $CONFIG{$_} = $data->{$_}
            for keys %$data;
    }
    else {
        warn "Empty init";
    }

    $init_complete = 1;
}

sub connect {
    my ($self, $dbname, @dbi_args) = @_;

    $self->init() unless $init_complete;

    if ( @dbi_args > 0 ) {
        $self->disconnect($dbname);
        $CONFIG{$dbname} = \@dbi_args;
    }

    croak "Can't connect to database: Invalid shortcut '$dbname'"
        unless exists $CONFIG{$dbname};

    if ( !defined $DBH{$dbname} || !$self->ping($dbname) ) {
        my ($url, $user, $pass, $attr, $do) = @{$CONFIG{$dbname}};
        $attr ||= {};
        $do   ||= [];

        $DBH{$dbname} = DBI->connect(
            $url, $user, $pass,
            { RaiseError => 1, AutoCommit => 1, %$attr }
        );

        croak("Can't connect to '$url' as '$user:$pass': ${DBI::errstr}")
            unless $DBH{$dbname};

        $DBH{$dbname}->do($_) for @$do;
    }

    return $DBH{$dbname};
}

sub ping {
    my ($self, $dbname) = @_;
    return 1 if $PING{$dbname} && $PING{$dbname} == time;
    return 0 if !$DBH{$dbname}->ping();

    $PING{$dbname} = time;
    return 1;
}

sub disconnect {
    my ($self, $dbname) = @_;

    return if !defined $DBH{$dbname};

    $DBH{$dbname}->disconnect();

    delete $DBH{$dbname};
}

my %txn_count;
sub txn_do {
    my ($self, $dbname, $code) = @_;
    my $dbh = $self->connect($dbname);
    local $dbh->{RaiseError} = 1;

    $txn_count{$dbname} ||= 0;
    $dbh->begin_work() unless $txn_count{$dbname}++;

    my $result = eval { $code->($dbh) };
    if ( $@ ||= $dbh->errstr ) {
        if ( $txn_count{$dbname} ) {
            $dbh->rollback();
            $txn_count{$dbname} = 0;
            carp "Transaction rolled back: $@";
        }
        return $result;
    }

    $dbh->commit() unless --$txn_count{$dbname};

    return $result;
}

sub select_object {
    my ($self, $cond, $basis, $columns) = @_;

    $cond ||= {};

    croak "Can't select object: basis required"
        unless defined $basis || defined $cond->{data_basis};

    croak "Can't select object: invalid 'columns' argument"
        if defined $columns && ref $columns ne 'ARRAY';

    $basis ||= DBIx::Basis->basis( $cond->{data_basis} );

    $cond->{data_basis} = [ map { $_->name } $basis, $basis->subbasises ];

    # Генерация и выполнение запроса
    my $dbh = $self->connect( $basis->db );
    my ($stmt, @bind) = $SQL->select( $basis->table , ($columns||'*'), $cond );
    my $sth = $dbh->prepare_cached( $stmt, { dbi_dummy => __PACKAGE__ }, 1 ); $sth->execute(@bind);
    my $rows = $sth->fetchall_arrayref({});
    unless (defined $rows) {
        $@ = $dbh->errstr;
        return wantarray ? () : undef;
    }

    # Десериализация объектов и установка значений по умолчанию в пустые поля
    my @objs = map _object($_, (defined $_->{data_basis} ? () : $basis), $columns), @$rows;

    return wantarray ? @objs : \@objs;
}

*select_objects = *select_object;

sub update_object {
    my ($self, $obj, $cond, $basis, $columns) = @_;

    croak "Can't update object: Object required"
        unless defined $obj;

    croak "Can't update object: invalid 'columns' argument"
        if defined $columns && ref $columns ne 'ARRAY';

    $cond ||= {};

    croak "Can't update object: Schema required"
        unless defined $basis || defined $cond->{data_basis};

    $basis ||= DBIx::Basis->basis( $cond->{data_basis} );

    $cond->{data_basis} = [ map { $_->name } $basis, $basis->subbasises ];

    # Сериализация объекта в запись БД
    my $row = _row($obj, (defined $obj->{data_basis} ? () : $basis), $columns);

    # Генерация и выполнение запроса
    my $dbh = DBIx::Basis::Handle->connect( $basis->db );
    my ($stmt, @bind) = $SQL->update( $basis->table, $row, $cond );
    my $sth = $dbh->prepare_cached( $stmt, { dbi_dummy => __PACKAGE__ }, 1 );
    my $res = $sth->execute(@bind);
    if (!$res || $res == 0) {
        $@ = $dbh->errstr;
        return undef;
    }
    if(defined wantarray) {
        return $self->select_object($cond, $basis, $columns)->[0];
    }
    return;
}

sub insert_object {
    my ($self, $data, $basis) = @_;

    $data ||= {};

    croak "Can't insert object: Schema required"
        unless defined $basis || defined $data->{data_basis};

    $basis ||= DBIx::Basis->basis( $data->{data_basis} );

    my @primary   = $basis->primary;
    my $data_cond = @primary ? { map { $_ => $data->{$_} } @primary } : {};
    croak "Can't return inserted for non-primary basises" if defined wantarray && scalar @primary < 1;

    # Сериализация объекта в запись БД
    my $row = _row($data, defined $data->{data_basis} ? () : $basis);
    for (@primary) {
        delete $row->{$_} unless defined $row->{$_};
    }

    my $dbh = DBIx::Basis::Handle->connect( $basis->db );
    my ($stmt, @bind) = $SQL->insert( $basis->table, $row );
    my $sth = $dbh->prepare_cached( $stmt, { dbi_dummy => __PACKAGE__ }, 1 );
    my $res = $sth->execute(@bind);
    unless ($res) {
        $@ = $dbh->errstr;
        return undef;
    }
    return unless defined wantarray;

    # Автозаполнение для 'auto_increment'-ных первичных ключей
    $basis->set_column( $data_cond, $primary[0], $dbh->last_insert_id(undef, undef, $basis->table, undef) )
        if @primary == 1 && !defined $row->{ $primary[0] };

    return $self->select_object($data_cond, $basis)->[0];
}

sub delete_object {
    my ($self, $cond, $basis) = @_;

    $cond ||= {};

    croak "Can't delete object: Schema required"
        unless defined $basis || defined $cond->{data_basis};

    $basis ||= DBIx::Basis->basis( $cond->{data_basis} );

    $cond->{data_basis} = [ map { $_->name } $basis, $basis->subbasises ];

    # Генерация и выполнение запроса
    my $dbh = DBIx::Basis::Handle->connect( $basis->db );
    my ($stmt, @bind) = $SQL->delete( $basis->table, $cond );
    my $sth = $dbh->prepare_cached( $stmt, { dbi_dummy => __PACKAGE__ }, 1 );
    my $res = $sth->execute(@bind);
    unless ($res) {
        $@ = $dbh->errstr;
        return undef;
    }

    return $res;
}

*delete_objects = *delete_object;

# Сериализация объекта в запись БД
sub _row {
    my ($obj, $basis, $columns) = @_;
    my $row = {};

    croak "Can't serialize object: basis required"
        unless defined $basis || defined $obj->{data_basis};

    $basis ||= DBIx::Basis->basis( $obj->{data_basis} );

    my %allcols = map { $_ => 1 } $basis->columns;
    croak "Can't serialize object: column not in the basis"
        if $columns && grep { !$allcols{$_} } @$columns;

    my %rowcols = $columns ? map { $_ => 1 } @$columns : %allcols;
    for my $col ( keys %allcols ) {
        next unless $rowcols{$col};
        my $val = $basis->del_column( $obj, $col ); # это get + delete
        $row->{$col} = $val;
    }

    if ( !$columns ) {
        $row->{data_basis} = $basis->name;
        $row->{data} = eval { $JSON->encode($obj) };
        die "Can't serialize object: $@" . ( DEBUG ? "\nObj: " . Dumper($obj) : '' ) if $@;
    }
    elsif ( !keys %$row ) {
        die "Can't serialize object: row is empty";
    }

    return $row;
}

# Десериализация объекта из записи БД
sub _object {
    my ($row, $basis, $columns) = @_;
    my $obj = {};

    croak "Can't deserialize object: basis required"
        unless defined $basis || defined $row->{data_basis};

    $basis ||= DBIx::Basis->basis( $row->{data_basis} );

    my %allcols = map { $_ => 1 } $basis->columns;
    croak "Can't deserialize object: column not in the basis"
        if $columns && grep { !$allcols{$_} } @$columns;

    if ( defined $row->{data} ) {
        $obj = eval { $JSON->decode( $row->{data} ) };
        die "Can't deserialize object: $@" . ( DEBUG ? "\nRow: " . Dumper($row) : '' ) if $@;
    }

    my %rowcols = $columns ? map { $_ => 1 } @$columns : %allcols;
    for my $col ( keys %allcols ) {
        next unless $rowcols{$col};
        $basis->set_column( $obj, $col, $row->{$col} );
    }

    $obj->{data_basis} = $basis->name;

    return $obj;
}

our $AUTOLOAD;
sub AUTOLOAD {
    my ($dbname) = ( $AUTOLOAD =~ /([^:]*)$/ );
    my $sub = subname $AUTOLOAD =>
        sub { shift->connect($dbname, @_) };

    no strict 'refs';
    *$AUTOLOAD = $sub;

    goto &$sub;
}

1;

__END__

=head1 NAME

DBIx::Basis::Handle - модуль работы с БД

=head1 SYNOPSIS

  use DBIx::Basis::Handle;

  $dbh = DBIx::Basis::Handle->connect('dbname');
  # or
  $dbh = DBIx::Basis::Handle->dbname();

=head1 DESCRIPTION

Работа с базами данных. Выдаёт соответствующие handles по запросу.
Лениво соединяется с БД.

=head1 METHODS

=head2 connect($dbname[, \%attr])

Лениво соединяется с БД C<$dbname>, или если соединение уже установлено, просто
отдаст хендл из кеша.

Можно дополнительно передать аттрибуты C<\%attr>, которые будут установлены
для возвращаемого хендла.

=head2 AUTOLOAD([\%attr])

Автоматически генерирует метод-синоним C<$dbname> для вызова C<connect($dbname)>
и тут же передает в него управление. Все последующие вызову будут обрабатываться
сгенерированной процедурой.

=head1 OBJECT MANIPULATION METHODS

TODO Написать документацию к методам DBIx::Basis::Handle для манипулирования объектами.

=back

=cut
