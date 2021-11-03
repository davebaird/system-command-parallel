# NAME

System::Command::Parallel - manage parallel system commands

# SYNOPSIS

    use System::Command::Parallel qw(read_lines_nb);

    my $flush_std_handles = sub {
        my ( $cmd, $id ) = @_ ;
        print STDOUT "$id: $_\n" for read_lines_nb( $cmd->stdout ) ;
        print STDERR "$id: $_\n" for read_lines_nb( $cmd->stderr ) ;
        } ;

    my ($count_success, $count_errors) = (0, 0) ;

    my $run_on_reap = sub {
        my ($cmd, $id) = @_ ;

        $cmd->exit == 0 ? $count_success++ : $count_errors++ ;

        # flush remaining lines
        $flush_std_handles->($cmd, $id) ;
        } ;

    my $sp = System::Command::Parallel->new(
        max_kids        => 10,
        timeout         => 60,
        run_while_alive => $flush_std_handles,
        run_on_reap     => $run_on_reap,
        ) ;

    my $exe = '/usr/bin/some-prog' ;

    while ( my $name = get_name_from_somewhere() ) {
        my @args = get_args_from_somewhere( $name ) ;

        $sp->spawn(
            cmdline => [ $exe, @args ],
            id      => $name,             # optional
            extra   => { trace => 3 },  # passed to backend
        }

    $sp->wait($optional_timeout) ;

# DESCRIPTION

The backend (default is `System::Command`) handles the
forking, while this module keeps track of the kids.

## Backends

The default backend is `System::Command`. A backend for `Proc::Background` is also provided.
Other backends can be added very simply.

## Signal handlers

The constructor installs signal handlers for INT and TERM. The original handlers are
preserved and replaced on object destruction.

## Methods

- `new( %args )`

        max_kids        - (default 0, probably doesn't make much sense...)
        timeout         - terminate kids after they get too old. Default 0 - don't.
        run_on_reap     - coderef
        run_on_spawn    - coderef
        run_while_alive - coderef
        debug           - default 0
        backend         - default 'System::Command'

    After a child is spawned/reaped, or intermittently while it lives, the relevant code ref is called.
    It is passed the backend object (default uses `System::Command`)
    representing the command/process, and the id (if any) provided in the `spawn()`
    call.

        $code_ref->($cmd, $id) ;

- `spawn( %args )`

    Launches a new child, if there are currently fewer than `$max_processes` running.
    If there are too many processes, `spawn()` will block until a slot becomes available.

    Arguments are passed to the backend to instantiate an object representing the command.

    The optional `id` is passed to the callbacks.

    Returns the backend object (`System::Command` by default). Be careful not to call any blocking
    methods on it e.g. `loop_on()` for `System::Command`.

- `wait( $timeout )`

    Blocking wait (with optional timeout) for all remaining child processes.

    Returns 1 if all kids were reaped, 0 otherwise, in which case the surviving kids
    are available in `kids`.

- `send_signal( $signal )`

    Send a signal to all kids.

- `kids`

    Hashref storing backend objects representing the kids, keyed by PID.

- `count_kids`

    Currently alive kids.

## Helpers

- `read_lines_nb( $fh )`

    A function, not a method.

    Non-blocking read. Fetches any available lines from the filehandle, without
    blocking for EOF.
