package System::Command::Parallel::Backend::Proc::Background ;

use strict ;
use warnings ;

use Moo::Role ;
use namespace::clean ;

use feature qw(signatures) ;

no warnings qw(experimental::signatures) ;

use Proc::Background ;


sub cmd_new ( $self, $cmdline_args, $extra ) {
    Proc::Background->new( { command => $cmdline_args, $extra->%* } ) ;
    }


sub cmd_pid ( $self, $cmd ) {
    $cmd->pid ;
    }


sub cmd_close ( $self, $cmd ) {
    $cmd->wait( $self->timeout ) ;    # not sure about this... maybe should just be a no-op?
    }


sub cmd_is_terminated ( $self, $cmd ) {
    !$cmd->alive ;
    }


sub cmd_terminate ( $self, $cmd ) {
    $cmd->terminate( [ $self->_default_kill_sequence ] ) ;
    }

1 ;
