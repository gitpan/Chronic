# Constraint-based, opportunistic scheduler.
## Author: Vipul Ved Prakash <mail@vipul.net>.
## $Id: Chronic.pm,v 1.5 2004/05/08 05:19:48 hackworth Exp $

package Schedule::Chronic; 
use base qw(Schedule::Chronic::Base Schedule::Chronic::Tab);
use Schedule::Chronic::Timer;
use Data::Dumper;


sub new { 

    my ($class, %args) = @_;
    my %self = (%args);

    $self{sleep_unit}           ||= 1;      # seconds
    $self{scheduler_wait}       = new Schedule::Chronic::Timer ('down');

    unless (exists $self{debug}) {
        $self{debug} = 1;
    }

    return bless \%self, $class;

}


sub load_cns_for_schedule { 

    my ($self) = @_;

    for my $task (@{$$self{_schedule}}) { 
        unless (exists $task->{_sched_constraints_loaded}) { 
            $self->load_cns_for_task($task);
        } 
    }

}


sub load_cns_for_task { 

    my ($self, $task) = @_;

    my $constraints = $task->{constraints};
    my $n_objects = 0;

    my $prep_args = sub { 

        my $topass = Dumper shift;
        $topass =~ s/\$VAR1 = \[//; 
        $topass =~ s/];\s*//g; 
        return $topass;

    };

    for my $constraint (keys %$constraints) { 

        # Load the module corresponding to the constraint from disk.
        # Die with a FATAL error if the module is not loaded. This
        # behaviour should be configurable through a data member.

        my $module = "Schedule::Chronic::Constraint::$constraint";
        eval "require $module; use $module";
        if ($@) { 
            my $error = join'', $@;
            if ($error =~ m"Can't locate (\S+)") { 
               $self->fatal("Cant' locate constraint module ``$1''");
            }
        }

        # Call the constructor and then the init() method to pass the
        # constraint object a copy of schedule, task and
        # thresholds/parameters supplied by the user. Save the
        # constraint object under the constraint key.

        my $constructor = "$module->new(debug => $$self{debug})";
        $task->{constraints}->{$constraint}->{_object} = eval $constructor or die $!;
        my $object = $task->{constraints}->{$constraint}->{_object};

        my $init = $object->init (
             $$self{_schedule}, $task, 
                @{$task->{constraints}->{$constraint}->{thresholds}}
        );

        unless ($init) { 
            $self->fatal("init() failed for $module")
        }

        $n_objects++;

    }

    # All's good.
    $self->debug("$n_objects constraint objects created.");
    $task->{_sched_constraints_loaded} = 1;
    # print Dumper $self;

    return 1;

}
        


sub schedule { 

    my $self = shift;

    my $schedule = $$self{_schedule};
    my $scheduler_wait = $$self{scheduler_wait};

    # A subroutine to compute a scheduler wait, which
    # is the the smallest of all task waits. We call
    # this routine after we've run through all tasks at
    # least once.

    my $recompute_scheduler_wait = sub { 
        my $sw = $schedule->[0]->{_task_wait}->get();
        for my $task (@$schedule) { 
            if ($$task{_task_wait}->get() < $sw) {
                $sw = $$task{_task_wait}->get();;
            }
        }
        $scheduler_wait->set($sw);
        $self->debug("scheduler_wait: set to $sw");
    };
 
    $self->debug("entering scheduler loop...");

    while (1) { 

        # First, sleep for a unit time.
        sleep($self->{sleep_unit});

        # Check to see if scheduler_wait is positive.  If so, 
        # go to sleep because all constraint waits are larger
        # than scheduler_wait.

        if ($scheduler_wait->get() > 0) { 
            $self->debug("nothing to schedule for " . 
                "@{[$scheduler_wait->get()]} seconds, sleeping...");
            sleep($scheduler_wait->get());
        }

        # Walk over all tasks, checks constraints and execute tasks when
        # all constraints are met. This is section should end in

        TASK: 
        for my $task (@$schedule) { 

            # A task has four components. A set of constraints, a
            # command to run when these constraints are met, the
            # last_ran time and a task wait timer which is the
            # maximum wait time returned by a constraint.

            my $constraints = $$task{constraints};
            my $task_wait   = $$task{_task_wait};
            my $command     = $$task{command};
            my $last_ran    = $$task{last_ran};
            my $uid         = $$task{_uid};

            $self->debug("((-- task = $command, last_ran = $last_ran, for user = $uid --))");

            if ($task_wait->get() > 0) { 

                # Constraints have indicated that they will not be met for
                # at least sched_wait seconds.

                $self->debug("task_wait: " . $task_wait->get() . " seconds");
                next TASK;

            };

            my $all_cns_met = 1;

            for my $constraint (keys %$constraints) { 

                # A constraint has two declarative components and a few
                # derived components. The declarative components are the
                # name of the constraint and the thresholds that
                # parameterize the constraint. The derived components
                # include the corresponding constraint object and other
                # transient data structures used by the scheduler.

                my $cobject = $task->{constraints}->{$constraint}->{_object};

                # Now call met() and wait()

                my $met  = $cobject->met();
                my $wait = $cobject->wait();

                if (not $met) { 

                    # The constraint wasn't met. We'll set all_cns_met to 0
                    # and see if we need to readjust wait time.

                    $self->debug("($constraint) unmet");
                    $all_cns_met = 0;

                    if ($wait != 0 && $wait > $task_wait->get()) { 

                        # Task wait is largest of all constraint waits.
                        # Maybe the recomupute shdeuler wait should be 
                        # done at the end of the task loop? 

                        $self->debug("($constraint) won't be met for $wait seconds");
                        $task_wait->set($wait);
                        &$recompute_scheduler_wait();
                
                    }

                } else { 
 
                    # The constraint has been met. 

                    $self->debug("($constraint) met");
                   
                }

            } # for - iterate over constraints

            if ($all_cns_met) { 

                $$task{last_ran} = time();
                $self->write_chrontab($$task{_chrontab});
                system($$task{command});

            } 
    
        } # for - iterate over tasks

    } # while - scheduler loop

}


1;


