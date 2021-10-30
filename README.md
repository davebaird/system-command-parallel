# NAME

System::Command::Parallel - manage parallel system commands

# SYNOPSIS

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
        ) ;

    my $exe = '/usr/bin/some-prog' ;

    while ( my ($id, @args) = get_id_and_args_from_somewhere() ) {
        $sp->spawn(
            cmdline => [ $exe, @args ],
            id      => $id,             # optional
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

## METHODS

- new(%args)

        max_kids        - (default 0, probably doesn't make much sense...)
        timeout         - terminate kids after they get too old. Default 0 - don't.
        run_on_reap     - coderef
        run_on_spawn    - coderef
        run_while_alive - coderef
        debug           - default 0
        backend         - default 'System::Command'

    After a child is spawned/reaped, or intermittently while it lives, the code ref is called.
    It is passed the backend object (default uses `System::Command`)
    representing the command/process, and the id (if any) provided in the `spawn()`
    call.

        $code_ref->($cmd, $id) ;

- spawn(%args)

    Launches a new child, if there are currently fewer than `$max_processes` running.
    If there are too many processes, `spawn()` will block until a slot becomes available.

    Accepts the same arguments as `System::Command->new()`, plus an additional
    optional `id`.

    Returns the `System::Command` object, but be careful not to call any blocking
    methods on it e.g. `loop_on()`.

- wait(\[timeout\])

    Blocking wait (with optional timeout) for all remaining child processes.

    Returns 1 if all kids were reaped, 0 otherwise, in which case the surviving kids
    are available in `kids`.

- send\_signal( signal )

    Send a signal to all kids.

- count\_kids

    Currently alive kids.

## Utility function

- read\_lines\_nb(fh)

    Non-blocking read. Fetches any available lines from the filehandle, without
    blocking for EOF.

# POD ERRORS

Hey! **The above document had some coding errors, which are explained below:**

- Around line 117:

    '=item' outside of any '=over'

- Around line 138:

    &#x3d;over without closing =back
