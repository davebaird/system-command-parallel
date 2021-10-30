package System::Command::Parallel::Backend::System::Command ;

use strict ;
use warnings ;

use Moo::Role ;
use namespace::clean ;

use feature qw(signatures) ;

no warnings qw(experimental::signatures) ;

use System::Command ;


sub cmd_new ( $self, $cmdline_args, $extra ) {
    System::Command->new( $cmdline_args->@*, $extra ) ;
    }


sub cmd_pid ( $self, $cmd ) {
    $cmd->pid ;
    }


sub cmd_close ( $self, $cmd ) {
    $cmd->close ;
    }


sub cmd_is_terminated ( $self, $cmd ) {
    $cmd->is_terminated ;
    }



1 ;
