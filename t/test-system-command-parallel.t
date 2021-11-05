#!/usr/bin/env perl
use v5.28 ;
use Test2::V0 '!meta' ;

use lib '/home/dave/code/z5.igbot/lib' ;

use Parallel::ForkManager ;
use System::Command::Parallel ;
use Nice::Try ;

my $MAX_PROCESSES = 3 ;
my $SCRIPT        = '/home/dave/code/z5.igbot/t/script.pl' ;

# script.pl:
# my $i = $ARGV[0] ;

# my $kidpid = $$ ;

# foreach my $j ( 1 .. 10 ) {
#     print STDERR $kidpid . ": kid $i: count $j\n" ;
#     sleep 1 ;
#     }

# plan => ;

ok( lives { run_code_kids() }, "Ran code kids OK" ) or note("ERROR: $@") ;

ok( lives { run_script_kid_no_fork() }, "Ran script without fork OK" ) or note("ERROR: $@") ;

ok( lives { run_script_kids() }, "Ran script kids OK" ) or note("ERROR: $@") ;

ok( lives { run_sp_version() }, "Ran Local::System::Command::Parallel version OK" ) or note("ERROR: $@") ;


sub run_script_kid_no_fork {
    my @cmd ;

    foreach my $i ( 1 .. 5 ) {
        push @cmd, System::Command->new( $SCRIPT, $i, { trace => 3 } ) ;
        }

    foreach my $i ( 1 .. 5 ) {
        wait_cmd( shift(@cmd), $i ) ;
        }
    }


sub wait_cmd {
    my $cmd = shift ;
    my $i   = shift ;

    while (1) {
        last if $cmd->is_terminated ;
        sleep 1 ;
        }

    local $/ ;
    my $out_fh = $cmd->stdout ;
    my $err_fh = $cmd->stderr ;
    my $out    = <$out_fh> ;
    my $err    = <$err_fh> ;

    diag "Script kid $i: STDOUT: $_" for split /\n/, $out ;
    diag "Script kid $i: STDERR: $_" for split /\n/, $err ;

    $cmd->close ;
    }


sub run_sp_version {
    my $sp = Local::System::Command::Parallel->new($MAX_PROCESSES) ;

    $sp->run_on_finish(
        sub {
            my ( $cmd, $id ) = @_ ;

            local $/ ;
            my $out_fh = $cmd->stdout ;
            my $err_fh = $cmd->stderr ;
            my $out    = <$out_fh> ;
            my $err    = <$err_fh> ;

            diag "SCP script kid $id: STDOUT: $_" for split /\n/, $out ;
            diag "SCP script kid $id: STDERR: $_" for split /\n/, $err ;
            }
            ) ;

    foreach my $i ( 1 .. 5 ) {
        my $cmd = $sp->spawn( [ $SCRIPT, $i, { trace => 3 } ], $i ) ;
        diag "SysCmdParallel: spawned kid $i - " . $cmd->pid ;
        }

    diag "Done spawning" ;

    $sp->wait ;
    }


sub run_script_kids {
    my $pm = Parallel::ForkManager->new($MAX_PROCESSES) ;

    foreach my $i ( 1 .. 5 ) {

        # Forks and returns the pid for the child:
        my $pid = $pm->start ;    #and next ;

        if ($pid) {
            diag("Forked for script kid $i: $pid") ;
            next ;
            }

        my $cmd ;
        try {
            $cmd = System::Command->new( $SCRIPT, $i, { trace => 3 } ) ;
            }
        catch ($e) {
            die "Error launching script $i: $e" ;

            # die $e ;
            }

        wait_cmd( $cmd, $i ) ;

        $pm->finish ;    # Terminates the child process
        }

    diag("Done fork + spawning") ;
    $pm->wait_all_children ;
    }


sub run_code_kids {
    my $pm = Parallel::ForkManager->new($MAX_PROCESSES) ;

    foreach my $i ( 1 .. 5 ) {

        # Forks and returns the pid for the child:
        my $pid = $pm->start ;    #and next ;

        if ($pid) {
            diag("Forked for code kid $i: $pid") ;
            next ;
            }

        my $kidpid = $$ ;

        foreach my $j ( 1 .. 10 ) {
            print STDERR $kidpid . ": code kid $i: count $j\n" ;
            sleep 1 ;
            }

        $pm->finish ;    # Terminates the child process
        }

    diag("Done forking") ;
    $pm->wait_all_children ;
    }

done_testing ;
