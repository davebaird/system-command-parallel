package System::Command::Parallel ;

use v5.28 ;
use warnings ;

use Types::Standard qw( Int Bool HashRef CodeRef Str Maybe ) ;
use Nice::Try ;

use Moo ;
use namespace::clean ;

use Exporter qw(import) ;

use feature qw(signatures) ;

no warnings qw(experimental::signatures) ;

our @EXPORT_OK = qw(read_lines_nb) ;


=pod

=encoding UTF-8

=head1 NAME

System::Command::Parallel - manage parallel system commands

=head1 SYNOPSIS

    use System::Command::Parallel qw(read_lines_nb);

    my $count_success = 0 ;
    my $count_errors  = 0 ;

    my $run_while_alive = sub {
        my ( $cmd, $id ) = @_ ;
        print STDOUT "$_\n" for read_lines_nb( $cmd->stdout ) ;
        print STDERR "$_\n" for read_lines_nb( $cmd->stderr ) ;
        } ;

    my $run_on_reap = sub {
        my ($cmd, $id) = @_ ;
        $cmd->exit == 0 ? $count_success++ : $count_errors++ ;
        } ;

    my $sp = System::Command::Parallel->new(
        max_kids        => 10,
        timeout         => 60,
        run_on_reap     => $run_on_reap,
        run_while_alive => $run_while_alive,
        debug           => 1,
        ) ;

    my $exe = '/usr/bin/some-prog' ;

    while ( my ($id, @args) = get_id_and_args_from_somewhere() ) {
        $sp->spawn(
            cmdline => [ $exe, @args ],
            id      => $id,             # optional
            extra   => { trace => 3 },  # passed to backend
        }

    $sp->wait($optional_timeout) ;


=head1 DESCRIPTION

The backend (default is C<System::Command>) handles the
forking, while this module keeps track of the kids.

=head2 Backends

The default backend is C<System::Command>. A backend for C<Proc::Background> is also provided.
Other backends can be added very simply.


=head2 Signal handlers

The constructor installs signal handlers for INT and TERM. The original handlers are
preserved and replaced on object destruction.

=head2 METHODS

=over 4

=item new(%args)

    max_kids     - (default 0, probably doesn't make much sense...)
    timeout      - terminate kids after they get too old. Default 0 - don't.


Take care that these do not block:
    run_on_reap  - coderef
    run_on_spawn - coderef
    run_while_alive - coderef

    debug        - default 0

    backend - default 'System::Command'


=item spawn($system_command_args, [$id])

Launches a new child, if there are currently fewer than C<$max_processes> running.
If there are too many processes, C<spawn()> will block until a slot becomes available.

Accepts the same arguments as C<System::Command->new()>, plus an additional
optional C<id>.

Returns the C<System::Command> object, but be careful not to call any blocking
methods on it e.g. C<loop_on()>.

=back

=head2 Constructor attributes

=over 4

=item run_on_spawn($code_ref)

=item run_on_reap($code_ref)

=item run_while_alive($code_ref)

After a child is spawned/reaped, this code_ref is called. It is passed the C<System::Command>
object representing the command/process, and the id (if any) provided in the C<spawn()>
call.

    $code_ref->($cmd, $id) ;

After the C<run_on_reap> code ref completes, C<$cmd->close> is called automatically.

=back

=cut

# ===== PACKAGE GLOBALS ========================================================

# ===== FILE GLOBALS ===========================================================

# ===== ATTRIBUTES =============================================================
has max_kids => ( is => 'ro', isa => Int->where('$_ >= 0'), default => 0 ) ;
has timeout  => ( is => 'ro', isa => Int->where('$_ >= 0'), default => 0 ) ;

# has hard_timeout => ( is => 'ro', isa => Int->where('$_ >= 0'), default => 0 ) ;
has run_on_reap     => ( is => 'ro', isa => Maybe [CodeRef] ) ;
has run_on_spawn    => ( is => 'ro', isa => Maybe [CodeRef] ) ;
has run_while_alive => ( is => 'ro', isa => Maybe [CodeRef] ) ;
has backend         => ( is => 'ro', isa => Str,     default => 'System::Command', required => 1 ) ;
has debug           => ( is => 'ro', isa => Bool,    default => 0 ) ;
has kids            => ( is => 'ro', isa => HashRef, default => sub { {} } ) ;
has _old_sigs       => ( is => 'ro', isa => HashRef, default => sub { {} } ) ;

# ===== ROLES ==================================================================
with 'MooX::Object::Pluggable' ;

# ===== CONSTRUCTORS ===========================================================
around BUILDARGS => sub {
    my ( $orig, $class, %args ) = @_ ;
    return \%args ;
    } ;


sub BUILD ( $self, $args ) {
    foreach my $sig (qw(INT TERM)) {
        $self->_old_sigs->{$sig} = $SIG{$sig} ;

        $SIG{$sig} = sub {
            $self->send_signal($sig) ;
            die "Caught $sig: $!" ;
            } ;
        }

    $self->load_plugins( '+' . __PACKAGE__ . "::Backend::" . $self->backend ) ;
    }


sub DEMOLISH ( $self, $in_global_destruction ) {
    $SIG{$_} = $self->_old_sigs->{$_} for keys $self->_old_sigs->%* ;
    }

# ===== ATTRIBUTE BUILDERS =====================================================

# ===== CLASS METHODS ==========================================================

# ===== METHODS ================================================================


sub count_kids ($self) {
    scalar( keys $self->kids->%* ) // 0 ;
    }


sub spawn ( $self, %args ) {
    $self->_wait_any ;                                            # does not block
    $self->_wait_one if $self->count_kids >= $self->max_kids ;    # blocks

    my $cmd = $self->cmd_new( $args{cmdline}, $args{extra} ) ;
    my $pid = $self->cmd_pid($cmd) ;

    $self->kids->{$pid} = {
        cmd          => $cmd,
        id           => $args{id},
        started      => time(),
        pid          => $pid,
        cmdline_args => $args{cmdline},
        extra        => $args{extra},
        } ;

    $self->_try( 'run_on_spawn', $cmd, $args{id} ) if $self->run_on_spawn ;

    return $cmd ;
    }


sub _try ( $self, $run_on, $cmd, $id ) {
    my $coderef = $self->$run_on ;

    try {
        $coderef->( $cmd, $id ) ;
        }
    catch ($e) {
        warn sprintf "Caught error during $run_on() for %s: $e\n", $id || '[no ID provided]' ;
        }
    }

# blocks
sub _wait_one ($self) {
    my $stop_after_1st = 1 ;

    while (1) {
        return if $self->_wait_any($stop_after_1st) ;
        sleep 1 ;
        }
    }

# does not block - unless $run_on_reap blocks
sub _wait_any ( $self, $stop_after_1st = undef ) {
    $self->_kill_the_old ;

    foreach my $kid ( values $self->kids->%* ) {
        if ( $self->cmd_is_terminated( $kid->{cmd} ) ) {
            $self->_reap( $kid->{pid} ) ;
            return 1 if $stop_after_1st ;
            }
        else {
            $self->_try( 'run_while_alive', $kid->{cmd}, $kid->{id} ) if $self->run_while_alive ;
            }
        }

    return ;    # don't return true accidentally
    }


sub _reap ( $self, $pid ) {
    my $done = delete $self->kids->{$pid} ;

    $self->_try( 'run_on_reap', $done->{cmd}, $done->{id} ) if $self->run_on_reap ;

    $self->cmd_close( $done->{cmd} ) ;

    waitpid $pid, 0 ;    # blocks if $pid is somehow still running, returns $pid if $pid has finished, returns -1 if $pid doesn't exist
    }


sub _kill_the_old ($self) {

    # my %timeouts ;
    # $timeouts{INT} = $self->timeout if $self->timeout ;
    # $timeouts{TERM} = $self->hard_timeout if $self->hard_timeout ;
    return unless $self->timeout ;

    my $cutoff = time() - $self->timeout ;
    $self->cmd_terminate($_) for $self->_older_than($cutoff) ;

    # foreach my $sig ( sort { $timeouts{$a} <=> $timeouts{$b} } keys %timeouts ) {
    #     my $cutoff = time() - $timeouts{$sig} ;
    #     $self->_kill( $sig, $_ ) for $self->_pids_older_than($cutoff) ;
    #     }
    }

# can be overridden in backend roles e.g. S::C::Role::Proc::Bg
sub cmd_terminate ( $self, $cmd, $kill_sequence = [] ) {
    my @kill_sequence = $kill_sequence->@* || $self->_default_kill_sequence ;

    while ( @kill_sequence and !$self->cmd_is_terminated($cmd) ) {
        my ( $sig, $delay ) = ( shift @kill_sequence, shift @kill_sequence ) ;

        kill( $sig, $self->cmd_pid($cmd) ) ;

        while ( $delay-- > 0 ) {
            last if $self->cmd_is_terminated($cmd) ;
            sleep 1 ;
            }
        }
    }


sub _default_kill_sequence ($self) {
    INT => 3, INT => 5, TERM => 2, TERM => 8, KILL => 3, KILL => 7 ;
    }


sub _older_than ( $self, $age ) {
    map { $_->{cmd} } grep { $_->{started} < $age } values $self->kids->%* ;
    }

# sub _kill ( $self, $sig, $pid ) {
#     return if $self->kids->{$pid}->{sent}->{$sig} ;
#     my $id_or_pid = $self->kids->{$pid}->{id} || $pid ;
#     warn "===== Sending $sig to $id_or_pid" if $self->debug ;
#     kill( $sig, $pid ) ;
#     $self->kids->{$pid}->{sent}->{$sig}++ ;
#     }

# sub _pids_older_than ( $self, $age ) {
#     grep { $self->kids->{$_}->{started} < $age } sort keys $self->kids->%* ;
#     }

=pod

=item wait([$timeout])

Blocking wait (with optional timeout) for all remaining child processes.

Returns 1 if all kids were reaped, 0 otherwise, in which case the surviving kids
are available in C<kids>.

=cut

# clean up all remaining procs
sub wait ( $self, $timeout = undef ) {
    my $timed_out = sub {
        return 0 unless $timeout ;
        state $start_at = time ;
        return 0 if ( time - $start_at ) < $timeout ;

        warn "Final timeout - sending TERM to remaining kids\n" if $self->debug ;
        $self->send_signal('TERM') ;    # no pussy-footing around, we've already been sending INTs and TERMs to these guys for ages
        sleep 5 ;
        $self->_wait_any ;              # last chance
        return 1 ;
        } ;

    while ( $self->count_kids and !$timed_out->() ) {
        $self->_wait_any ;
        sleep 1 ;
        }

    return $self->count_kids ? 0 : 1 ;
    }

=pod

=item send_signal( $signal )

Send a signal to all kids.

=cut


sub send_signal ( $self, $sig ) {
    kill( $sig, $_ ) for keys $self->kids->%* ;
    }

# ===== FUNCTIONS ==============================================================

# Code from https://davesource.com/Solutions/20080924.Perl-Non-blocking-Read-On-Pipes-Or-Files.html
# but see also for more info:
# https://flylib.com/books/en/3.214.1.89/1/   - mentions sysread can always do partial reads, even on blocking filehandles
# https://www.cs.ait.ac.th/~on/O/oreilly/perl/cookbook/ch07_14.htm - 1st edition
# https://www.cs.ait.ac.th/~on/O/oreilly/perl/cookbook/ch07_15.htm - 1st edition
# https://docstore.mik.ua/orelly/perl4/cook/ch07_21.htm - 2nd edition
# https://stackoverflow.com/questions/3773867/how-do-i-do-a-non-blocking-read-from-a-pipe-in-perl
sub read_lines_nb ($fh) {
    state %nonblockGetLines_last ;

    my $timeout = 0 ;
    my $rfd     = '' ;
    $nonblockGetLines_last{$fh} = ''
        unless defined $nonblockGetLines_last{$fh} ;

    vec( $rfd, fileno($fh), 1 ) = 1 ;
    return unless select( $rfd, undef, undef, $timeout ) >= 0 ;
    return unless vec( $rfd, fileno($fh), 1 ) ;

    my $buf = '' ;
    my $n   = sysread( $fh, $buf, 1024 * 1024 ) ;

    # If we're done, make sure to send the last unfinished line
    return ( 1, $nonblockGetLines_last{$fh} ) unless $n ;

    # Prepend the last unfinished line
    $buf = $nonblockGetLines_last{$fh} . $buf ;

    # And save any newly unfinished lines
    $nonblockGetLines_last{$fh} = ( substr( $buf, -1 ) !~ /[\r\n]/ && $buf =~ s/([^\r\n]*)$// ) ? $1 : '' ;
    $buf ? ( 0, split( /\n/, $buf ) ) : (0) ;
    }

1 ;
