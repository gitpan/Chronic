##
## Load Average Constraint
## Author: Vipul Ved Prakash <mail@vipul.net>.
## $Id: Freq.pm,v 1.2 2004/05/08 05:18:15 hackworth Exp $
##

package Schedule::Chronic::Constraint::Freq;
use Schedule::Chronic::Base;
use base qw(Schedule::Chronic::Base);

# NOTE: This module overloads the concept of wait to store the number of
#       seconds left before execution. Don't let this confuse you,
#       specially if you are looking at this as a an example for your
#       constraint module.


sub new { 
    my ($class, $debug) = @_;
    return bless { 
        debug => $debug, 
    }, $class;
}


sub init { 

    my ($self, $schedule, $task, $seconds) = @_;

    # @args can be: 
    # 86400
    # 86400, Force
    # Force is not implemented
   
    $$self{schedule}  = $schedule; 
    $$self{task}      = $task;
    $$self{seconds}   = $seconds;

    $$self{wait}     = 0;

    return $self;

}


sub met { 

    my ($self) = @_;

    return 1 if $$self{task}{last_ran} == 0;
    $$self{wait} = $$self{task}{last_ran} - (time() - $$self{seconds});
    return 1 if ($$self{wait} < 0);
    return 0;
    
}


sub state { 

    return $_->[0]->{wait};

}

sub wait { 

    return $_[0]->{wait};
}


1;
