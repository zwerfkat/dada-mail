package DADA::MailingList::Subscribers;

use lib qw(./ ../ ../../ ../../DADA ../../perllib);


use Carp qw(carp croak);
my $type; 
use DADA::Config qw(!:DEFAULT); 	
BEGIN { 
	$type = $DADA::Config::SUBSCRIBER_DB_TYPE;
	if($type =~ m/sql/i){ 
	 	if ($DADA::Config::SQL_PARAMS{dbtype} eq 'mysql'){ 
			$type = 'MySQL';
		}
		elsif ($DADA::Config::SQL_PARAMS{dbtype} eq 'Pg'){ 		
				$type = 'PostgreSQL';
		}
		elsif ($DADA::Config::SQL_PARAMS{dbtype} eq 'SQLite'){ 
			$type = 'SQLite';
		}
	}
}
use base "DADA::MailingList::Subscribers::$type";


use strict; 

use DADA::Logging::Usage;
my $log = new DADA::Logging::Usage;



sub edit_subscriber { 
	
	my $self = shift; 
    my ($args) = @_;

    if(! exists $args->{-type}){ 
        $args->{-type} = 'list';
    }
	if(! exists $args->{-email}){ 
        croak("You MUST supply an email address in the -email paramater!"); 
    }
	if(length(DADA::App::Guts::strip($args->{-email})) <= 0){ 
        croak("You MUST supply an email address in the -email paramater!"); 		
	}
	
    if(! exists $args->{-fields}){ 
        $args->{-fields} = {};
    }

    if(! exists $args->{-mode}){ 
        $args->{-mode} = 'update';
    }

	if($args->{-mode} !~ /update|writeover/){ 
		croak "The -mode paramater must be set to, 'update', 'writeover' or left undefined!"; 
	}

	my $f_values = {}; 
	
	if($args->{-mode} eq 'update'){ 
		
		$f_values	= $self->get_subscriber(
			{
				-email => $args->{-email},
				-type  => $args->{-type}, 
			}
		);

	}

	$self->remove_subscriber(
		{
			-email => $args->{-email},
			-type  => $args->{-type},
		}
	);

	foreach(keys %{$args->{-fields}}){ 
		$f_values->{$_} = $args->{-fields}->{$_};
	}
	
	$self->add_subscriber(
	     { 
		  -email         => $args->{-email}, 
	      -type          => $args->{-type},
	      -fields        => $f_values,
	    });
	
	return 1; 
}




sub copy_subscriber { 
	
    my $self   = shift; 

    my ($args) = @_;

    if(! exists $args->{-to}){ 
        croak "You must pass a value in the -to paramater!"; 
    }
    if(! exists $args->{-from}){ 
        croak "You must pass a value in the -from paramater!"; 
    }    
    if(! exists $args->{-email}){ 
        croak "You must pass a value in the -email paramater!"; 
    }

    if($self->allowed_list_types->{$args->{-to}} != 1){ 
        croak "list_type passed in, -to is not valid"; 
    }

    if($self->allowed_list_types->{$args->{-from}} != 1){ 
        croak "list_type passed in, -from is not valid"; 
    }

     if(DADA::App::Guts::check_for_valid_email($args->{-email}) == 1){ 
        croak "email passed in, -email is not valid"; 
    }


    my $moved_from_checks_out = 0; 
    if(! exists($args->{-moved_from_check})){ 
        $args->{-moved_from_check} = 1; 
    }

    if($self->check_for_double_email(-Email => $args->{-email}, -Type => $args->{-from}) == 0){ 

        if($args->{-moved_from_check} == 1){ 
            croak "email passed in, -email is not subscribed to list passed in, '-from'";     
        }
        else { 
            $moved_from_checks_out = 0; 
        }
    }
    else { 
        $moved_from_checks_out = 1; 
    }


    if($self->check_for_double_email(-Email => $args->{-email}, -Type => $args->{-to}) == 1){ 
        croak "email passed in, -email ( $args->{-email}) is already subscribed to list passed in, '-to' ($args->{-to})"; 
    }

	my $sub = $self->get_subscriber({-email => $args->{-email}, -type => $args->{-from}}); 
    $self->add_subscriber(
        { 
            -email  => $args->{-email}, 
            -type   => $args->{-to}, 
			-fields => $sub,
        }
    ); 

    if ($DADA::Config::LOG{subscriptions}) { 
        $log->mj_log(
            $self->{list}, 
            'Copy from:  ' . $self->{list} . '.' . $args->{-from} . ' to: ' . $self->{list} . '.' . $args->{-to}, 
            $args->{-email}, 
        );
    }


	return 1;	
}




sub remove_subscriber { 
	
	my $self   = shift;
	my ($args) = @_; 
	
	if(! exists $args->{-type}){ 
        $args->{-type} = 'list';
    }
    if(! exists $args->{-email}){ 
        croak("You MUST supply an email address in the -email paramater!"); 
    }
	if(length(DADA::App::Guts::strip($args->{-email})) <= 0){ 
        croak("You MUST supply an email address in the -email paramater!"); 		
	}
	
	# Kind of a wrapper ATM:
	return $self->remove_from_list(-Email_List => [$args->{-email}], -Type => $args->{-type});
	
}




sub allowed_list_types { 

    my $self = shift; 
    
    return {
    
        list                => 1,       
        black_list          => 1, 
        authorized_senders  => 1, 
        testers             => 1, 
        white_list          => 1, 
        sub_confirm_list    => 1, 
        unsub_confirm_list  => 1, 
        invitelist          => 1, 
        
    } 
       
}






sub subscription_check { 

	my $self = shift; 
	my ($args) = @_; 

	
	if(! exists($args->{-email})){ 
		$args->{-email} = ''; 
	}
	my $email = $args->{-email};

	if(! exists($args->{-type})){ 
		$args->{-type} = 'list'; 
	} 
	
	my %skip; 
	$skip{$_} = 1 foreach @{$args->{-skip}}; 
		
	my %errors = ();
	my $status = 1; 
		
	require DADA::App::Guts; 
	require DADA::MailingList::Settings;
	
	if(!$skip{no_list}){
		if(DADA::App::Guts::check_if_list_exists(-List => $self->{list}) == 0){
			$errors{no_list} = 1;
			return (0, \%errors);
		}
	}
				
	my $ls = DADA::MailingList::Settings->new({-list => $self->{list}}); 
	my $list_info = $ls->get;
	
	if($args->{-type} ne 'black_list'){ 
		if(!$skip{invalid_email}){
			$errors{invalid_email} = 1 if DADA::App::Guts::check_for_valid_email($email)      == 1;
		}
	}
	
	if(!$skip{subscribed}){
			$errors{subscribed} = 1 if $self->check_for_double_email(-Email => $email, -Type => $args->{-type}) == 1; 
	}
	
	if($args->{-type} ne 'black_list' || $args->{-type} ne 'authorized_senders'){ 
		if(!$skip{closed_list}){
			$errors{closed_list}   = 1 if $list_info->{closed_list}                             == 1; 
		}
	}
	
	if($args->{-type} ne 'black_list'){ 
		if(!$skip{mx_lookup_failed}){		
			if($list_info->{mx_check} == 1){ 
				require Email::Valid;
				eval {
					unless(Email::Valid->address(-address => $email,
												 -mxcheck => 1)) {
						$errors{mx_lookup_failed}   = 1;
					};
				carp "mx check error: $@" if $@;
				}; 
			}
		}
	}

	
	if($args->{-type} ne 'black_list'){ 
		if(!$skip{black_listed}){
			if($list_info->{black_list} eq "1"){
				$errors{black_listed} = 1 if $self->check_for_double_email(-Email => $email, 
																		  -Type  => 'black_list')  == 1; 
			}
		}
	}


	if($args->{-type} ne 'white_list'){ 
		if(!$skip{not_white_listed}){
		
			if($list_info->{enable_white_list} == 1){

				$errors{not_white_listed} = 1 if $self->check_for_double_email(-Email => $email, 
																		       -Type  => 'white_list')  != 1; 
			}
		}
	}


	if($args->{-type} ne 'black_list' || $args->{-type} ne 'authorized_senders'){ 
		if(!$skip{over_subscription_quota}){ 
			if($list_info->{use_subscription_quota} == 1){ 
				if(($self->num_subscribers + 1) >= $list_info->{subscription_quota}){ 
					$errors{over_subscription_quota} = 1; 
				}
			}
		}
	}
	
	
	if(!$skip{already_sent_sub_confirmation}){ 
		if($list_info->{limit_sub_confirm } == 1){ 
			$errors{already_sent_sub_confirmation} = 1 if $self->check_for_double_email(-Email => $email, 
																                        -Type  => 'sub_confirm_list')  == 1;
		}
	}
	
	
	
	if(!$skip{settings_possibly_corrupted}){ 
		if(!$ls->perhapsCorrupted){ 
			$errors{settings_possibly_corrupted} = 1; 
		}
	}
	
	
	
	foreach(keys %errors){ 
		$status = 0 if $errors{$_} == 1;
		last;
	}
	
	return ($status, \%errors); 
	

}





sub unsubscription_check {
		 
	my $self = shift; 
	my ($args) = @_; 

	
	if(! exists($args->{-email})){ 
		$args->{-email} = ''; 
	}
	my $email = $args->{-email};

	if(! exists($args->{-type})){ 
		$args->{-type} = 'list'; 
	}  
	
	my %errors = ();
	my $status = 1; 
	
	if(!exists($args->{-skip})){ 
		$args->{-skip} = [];
	}
	my %skip; 
	$skip{$_} = 1 foreach @{$args->{-skip}}; 
	
	require DADA::App::Guts;
	require DADA::MailingList::Settings;
	
	if(!$skip{no_list}){
		$errors{no_list} = 1 if DADA::App::Guts::check_if_list_exists(-List => $self->{list})     == 0;
		return (0, \%errors) if $errors{no_list} == 1;
	}
				
	my $ls = DADA::MailingList::Settings->new({-list => $self->{list}}); 
		
	if(!$skip{invalid_email}){
		$errors{invalid_email} = 1 if DADA::App::Guts::check_for_valid_email($email)      == 1;
	}
	
	if(!$skip{not_subscribed}){
		$errors{not_subscribed}    = 1 if $self->check_for_double_email(-Email => $email)     != 1; 
	}
	
	if(!$skip{already_sent_unsub_confirmation}){ 
		my $li = $ls->get; 
		if($li->{limit_unsub_confirm } == 1){ 
			$errors{already_sent_unsub_confirmation} = 1 if $self->check_for_double_email(-Email => $email, 
																                          -Type  => 'unsub_confirm_list')  == 1;
		}
	}
	
	
	if(!$skip{settings_possibly_corrupted}){ 
		if(!$ls->perhapsCorrupted){ 
			$errors{settings_possibly_corrupted} = 1; 
		}
	}

		
	foreach(keys %errors){ 
		$status = 0 if $errors{$_} == 1;
		last;
	}
	
	

	return ($status, \%errors); 
	

}






sub subscription_check_xml { 

	my $self = shift; 
	my ($args) = @_; 
	my ($status, $errors) = $self->subscription_check($args); 
	
	my $errors_array_ref = []; 
	push(@$errors_array_ref, {error => $_}) 
		foreach keys %$errors; 
	
	require    DADA::Template::Widgets;
	my $xml =  DADA::Template::Widgets::screen({-screen => 'subscription_check_xml.tmpl', 
		                                  -vars   => {
		                                               email  => $args->{-email}, 
		                                               errors => $errors_array_ref,
		                                               status => $status, 
		                                               
		                                              },
	
	            });
	
	$xml =~ s/\n|\r|\s|\t//g;
	
	
	return ($xml, $status, $errors); 
}




sub unsubscription_check_xml { 

	my $self = shift; 
	my ($args) = @_; 
	my ($status, $errors) = $self->unsubscription_check($args); 
	
	my $errors_array_ref = []; 
	push(@$errors_array_ref, {error => $_}) 
		foreach keys %$errors; 

	require    DADA::Template::Widgets;
	my $xml =  DADA::Template::Widgets::screen({-screen => 'unsubscription_check_xml.tmpl', 
		                                  	   -vars   => {
		                                               email  => $args->{-email}, 
		                                               errors => $errors_array_ref,
		                                               status => $status, 
		                                               
		                                              },
		                                     }); 
	$xml =~ s/\n|\r|\s|\t//g;
	
	return ($xml, $status, $errors); 
}




sub filter_subscribers { 

	my $self   = shift; 
	my ($args) = @_; 
	
	my $new_addresses = $args->{-emails}; 

	if(! exists($args->{-type})){ 
		$args->{-type} = 'list'; 
	}
	my $type = $args->{-type}; 
		
	require  DADA::MailingList::Settings; 
	my $ls = DADA::MailingList::Settings->new({-list => $self->{list}}); 
	my $li = $ls->get; 

	require DADA::App::Guts;

	my @good_emails   = (); 
	my @bad_emails    = (); 

	my $invalid_email;

    my $num_subscribers = $self->num_subscribers;
    
	foreach my $check_this_address(@$new_addresses) { 


        my $errors = {};
        my $status = 1; 
        
        if($type eq 'black_list'){ 
            # Yeah... nothing... 
        }
        elsif($type eq 'white_list'){ 
            # Yeah... nothing...             
        }
        else { 
            if(DADA::App::Guts::check_for_valid_email($check_this_address) == 1){ 
                $errors->{invalid_email} = 1;
            }
            else { 
                $errors->{invalid_email} = 0;
            }
        }
        
        if($type ne 'black_list' || $type ne 'authorized_senders' || $type ne 'white_list'){ 
                if($li->{use_subscription_quota} == 1){ 
                    if(($num_subscribers + 1) >= $li->{subscription_quota}){ 
                        $errors->{over_subscription_quota} = 1; 
                    }
                }
            }
        
        if( $errors->{invalid_email} == 1 || $errors->{over_subscription_quota} == 1){ 
            $status = 0; 
        }
        
		if ($status != 1){
			  push(@bad_emails, $check_this_address);
		}else{    
			$check_this_address = DADA::App::Guts::lc_email($check_this_address); 
			push(@good_emails, $check_this_address);
		}
	}
  
 # warn  time .  "done!"; 
  
	my %seen = (); 
	my @unique_good_emails = grep { ! $seen{$_}++} @good_emails; 
	
	%seen = (); 
	my @unique_bad_emails = grep { ! $seen{$_}++} @bad_emails; 
	
	@unique_good_emails = sort(@unique_good_emails); 
	@unique_bad_emails  = sort(@unique_bad_emails); 
	
		
	# figure out what unique emails we have from the new list when compared to the old list
	my ($unique_ref, $not_unique_ref) = $self->unique_and_duplicate(-New_List  => \@unique_good_emails, 
																	-Type      => $type, 
													   				);
		
	#initialize 
	my @black_list; 
	my $found_black_list_ref; 
	my $clean_list_ref; 
	my $black_listed_ref = []; 
	my $black_list_ref   = [];
	
	my $white_list_ref;     # file handle?
	
	my $found_white_list_ref = [];
	
	if($li->{black_list} == 1 && $type eq 'list'){ 
	
		#open the black list  
		# TODO: "open_email_list" needs to be gone, as it pulls the entire list in memory - 
		# BAD BAD BAD - this is also the ONLY place it's used!!!
		
		$black_list_ref = $self->open_email_list(-Type => "black_list", -As_Ref=>1);
		
		# now, from that new list of clean emails, see which ones are black listed 
		($found_black_list_ref) = $self->get_black_list_match($black_list_ref, $unique_ref);
		
		#now, tell me which ones still are ok. 
		($clean_list_ref, $black_listed_ref) = $self->find_unique_elements($unique_ref, $found_black_list_ref); 
									  
	}else{ 

		$clean_list_ref = $unique_ref; 

	}
	
	
	# The entire white list stuff is pure messed. 
	
	if($li->{enable_white_list} == 1 && $type eq 'list'){
	
	    
	   $white_list_ref = $self->open_email_list(-Type => "white_list", -As_Ref=>1);
	
		# now, from that new list of clean emails, see which ones are black listed 
		($found_white_list_ref) = $self->get_black_list_match($white_list_ref, $clean_list_ref);
	    
       # now, tell me which ones still are ok. 
	   ($found_white_list_ref, $clean_list_ref) = $self->find_unique_elements($clean_list_ref, $found_white_list_ref); 
	   
	}else{ 
	    # nothing, really. 
	    $found_white_list_ref = []; 
	    
	}
	   
	      # $subscribed,     $not_subscribed, $black_listed,    $not_white_listed, $invalid
	return ($not_unique_ref, $clean_list_ref, $black_listed_ref, $found_white_list_ref, \@unique_bad_emails); 

   

}




sub filter_subscribers_w_meta { 

	my $self   = shift; 
	my ($args) = @_; 

	if(! exists($args->{-type})){ 
		$args->{-type} = 'list'; 
	}
	my $type = $args->{-type}; 

	
	my $emails = [];
	my $lt     = {};
	
	my $info = $args->{-emails}; 

	my $fields = $self->subscriber_fields(); 
	
	#require Data::Dumper; 
	require Text::CSV; 
	#my $csv = Text::CSV->new;
	my $csv = Text::CSV->new($DADA::Config::TEXT_CSV_PARAMS);
    
	# What's this for, again?
	foreach my $sub(@$info){
        push(@$emails, $sub->{email});        
        $lt->{$sub->{email}} = $sub; 
    }	
	# These only include the email address. 
    my ($subscribed, $not_subscribed, $black_listed, $not_white_listed, $invalid) 
		= $self->filter_subscribers(
			{
				-emails => $emails, 
				-type   => $type
			}
		);
    
    # So... now they're sorted... we gotta...
    
    my $subscribed_info       = [];
    my $not_subscribed_info   = [];
    my $black_listed_info     = [];
    my $not_white_listed_info = [];
    my $invalid_info          = [];
    
	# This is tmp copy of ALL the passed subscribers. 
    foreach(@$subscribed){    
        push(@$subscribed_info, $lt->{$_});
    }
    
    foreach(@$not_subscribed){ 

		###
		my $flattened_info = []; 
		push(@$flattened_info, $lt->{$_}->{email}); 
		
		my $tmp_info = {}; 
		foreach my $d(@{$lt->{$_}->{fields}}){ 
            $tmp_info->{$d->{name}} = $d->{value};
        }
		foreach my $f(@$fields){ 
			push(@$flattened_info, $tmp_info->{$f}); 
		}	
		
		if ($csv->combine(@$flattened_info)) {
	        $lt->{$_}->{csv_info} = $csv->string;
	    } else {
	        carp "combine() failed on argument: ", $csv->error_input;
	    }
       
		push(@$not_subscribed_info, $lt->{$_});
 	   ###/

   }
    
    foreach(@$black_listed){
    
		###
		my $flattened_info = []; 
		push(@$flattened_info, $lt->{$_}->{email}); 

		my $tmp_info = {}; 
		foreach my $d(@{$lt->{$_}->{fields}}){ 
            $tmp_info->{$d->{name}} = $d->{value};
        }
		foreach my $f(@$fields){ 
			push(@$flattened_info, $tmp_info->{$f}); 
		}	

		if ($csv->combine(@$flattened_info)) {
	        $lt->{$_}->{csv_info} = $csv->string;
	    } else {
	        carp "combine() failed on argument: ", $csv->error_input;
	    }

		push(@$black_listed_info, $lt->{$_});
 	   ###/
    }
    
    foreach(@$not_white_listed){ 
    
        	###
			my $flattened_info = []; 
			push(@$flattened_info, $lt->{$_}->{email}); 

			my $tmp_info = {}; 
			foreach my $d(@{$lt->{$_}->{fields}}){ 
	            $tmp_info->{$d->{name}} = $d->{value};
	        }
			foreach my $f(@$fields){ 
				push(@$flattened_info, $tmp_info->{$f}); 
			}	

			if ($csv->combine(@$flattened_info)) {
		        $lt->{$_}->{csv_info} = $csv->string;
		    } else {
		        carp "combine() failed on argument: ", $csv->error_input;
		    }

			push(@$not_white_listed_info, $lt->{$_});
	 	   ###/
    }    
    
    foreach(@$invalid){ 
        
			###
			my $flattened_info = []; 
			push(@$flattened_info, $lt->{$_}->{email}); 

			my $tmp_info = {}; 
			foreach my $d(@{$lt->{$_}->{fields}}){ 
	            $tmp_info->{$d->{name}} = $d->{value};
	        }
			foreach my $f(@$fields){ 
				push(@$flattened_info, $tmp_info->{$f}); 
			}	

			if ($csv->combine(@$flattened_info)) {
		        $lt->{$_}->{csv_info} = $csv->string;
		    } else {
		        carp "combine() failed on argument: ", $csv->error_input;
		    }

			push(@$invalid_info, $lt->{$_});
	 	   ###/
    }
    

    # WHEW!
    
    return ($subscribed_info, $not_subscribed_info, $black_listed_info, $not_white_listed_info, $invalid_info); 
    
}





sub get_fallback_field_values { 

    my $self = shift; 
    my $v    = {}; 
    
    return $v if  $self->can_have_subscriber_fields == 0; 
    require  DADA::MailingList::Settings; 
    my $ls = DADA::MailingList::Settings->new({-list => $self->{list}});
    my $li = $ls->get; 
    
    
    my @fallback_fields = split("\n", $li->{fallback_field_values}); 
    foreach(@fallback_fields){ 
        my ($n, $val) = split(':', $_); 
        $v->{$n} = $val; 
    }
    
    return $v; 
}




sub _save_fallback_value { 

    my $self = shift; 
    my ($args) = @_; 
    
    if(! exists $args->{-field}){ 
        croak "You MUST pass a value in the -field paramater!"; 
    }

    if(! exists $args->{-fallback_value}){ 
        croak "You must pass a value in the -fallback_value paramater!"; 
    }
    
 	require  DADA::MailingList::Settings; 
    my $ls = DADA::MailingList::Settings->new({-list => $self->{list}});

    my $fallback_field_values = $self->get_fallback_field_values;
    
    my $fallback_field_clump = ''; 
	
	foreach(keys %$fallback_field_values){ 
		$fallback_field_clump .= $_ . ':' . $fallback_field_values->{$_} . "\n";
	}

    $args->{-fallback_value} =~ s/\r|\n/ /g;
    $args->{-fallback_value} =~ s/\://g;
    
    $fallback_field_clump .= $args->{-field} . ':' . $args->{-fallback_value} . "\n";
    
    $ls->save({fallback_field_values => $fallback_field_clump});
    
    return 1; 
}



sub _remove_fallback_value { 

    my $self = shift; 
    my ($args) = @_; 
    
    if(! exists $args->{-field}){ 
        croak "You MUST pass a value in the -field paramater!"; 
    }

    require DADA::MailingList::Settings; 
    my $ls = DADA::MailingList::Settings->new({-list => $self->{list}}); 
    my $li = $ls->get; 
    
    
    my $fallback_field_values = $self->get_fallback_field_values;
    

    my $new_fallback_field_values = '';
    foreach(keys %$fallback_field_values){ 
        next if $_ eq $args->{-field}; 
        $new_fallback_field_values .= $_ . ':' . $fallback_field_values->{$_} . "\n";
    }
    $ls->save({fallback_field_values => $new_fallback_field_values}); 
    
    return 1; 
}










sub write_plaintext_list { 
	
	require DADA::App::Guts; 
	
	my $self = shift; 
	
	# DEV: Needs ot be changed to hashref file paramater passing
	my %args = (-Type => 'list', 
	            @_); 
	my $type     = $args{-Type};
	my $path     = $DADA::Config::TMP ; 
	my $tmp_id   = DADA::App::Guts::message_id();
	my $ln       = $self->{list}; 
	my $tmp_file = DADA::App::Guts::make_safer($path . '/' . $ln . '.' . $type . '.' . $tmp_id); 
	
	# DEV: needs to be changed to an anonymous file handle. 
	open(TMP_LIST, ">$tmp_file") or croak $!;		  
		$self->print_out_list(-Type => $args{-Type}, 
							  -FH   => \*TMP_LIST);
	close(TMP_LIST); 
	return $tmp_file;

}









sub find_unique_elements { 

	my $self = shift; 
	
	my $A = shift || undef; 
	my $B = shift || undef; 
	
	if($A and $B){ 	
		#lookup table
		my %seen = ();     
		# we'll store unique things in here            
		my @unique = ();
		#we'll store what we already got in here
		my @already_in = ();                 
		# build lookup table
		foreach my $item (@$B) { $seen{$item} = 1 }
		# find only elements in @$A and not in @$B
		foreach my $item (@$A) {
			unless ($seen{$item}) {
				# it's not in %seen, so add to @aonly
				push(@unique, $item);
			}else{
				push(@already_in, $item);
				}
		}
		
		return (\@unique, \@already_in); 
	
	}else{ 
		carp 'I need two arrary refs!';
		return ([], []); 
	}
}




sub csv_to_cds { 
	my $self     = shift; 
	my $csv_line = shift; 
	my $cds      = {};
	
	my $subscriber_fields = $self->subscriber_fields;
	
	require   Text::CSV; 
	#my $csv = Text::CSV->new; 
	my $csv = Text::CSV->new($DADA::Config::TEXT_CSV_PARAMS);
    
	require DADA::App::Guts;
	
	#die '$csv_line ' . $csv_line; 
	
	if ($csv->parse($csv_line)) {
	    
        my @fields = $csv->fields;
        my $email  = shift @fields; 

        $email =~ s{^<}{};
        $email =~ s{>$}{};
        $email =  DADA::App::Guts::strip($email); 
        $email =  DADA::App::Guts::xss_filter($email); 
        $email =  DADA::App::Guts::cased($email); 

        $cds->{email}  = $email;
		$cds->{fields} = {};
		
		my $i = 0; 
        foreach(@$subscriber_fields){ 
			$cds->{fields}->{$_} = $fields[$i];
			$i++; 
		}
       
    } else {
        carp $DADA::Config::PROGRAM_NAME . " Error: CSV parsing error: parse() failed on argument: ". $csv->error_input() . ' ' . $csv->error_diag ();;         

    }
	
	#require Data::Dumper; 
	#die 'hello ' . Data::Dumper::Dumper($cds); 
	
	return $cds; 
	
}








1;

__END__

=pod

=head1 NAME 

DADA::MailingList::Subscribers - API for the Dada Mailing List Subscribers

=head1 SYNOPSIS

 # Import
 use Dada::MailingList::Subscribers; 
  
 # Create a new object
 my $lh = DADA::MailingList::Subscribers->new({-list => 'mylist'}); 
 
 # Check if this can be a valid subscription: 
 
 my ($status, $errors) = $lh->subscription_check(
	{
		-email => 'user@example.com', 
	}
 );
 
 # How about to unsubscribe: 
 
 my ($status, $errors) = $lh->unsubscription_check(
	{
		-email => 'user@example.com', 
	}
  );
 
 # Add
 $lh->add_subscriber(
	{
		-email => 'user@example.com',
		-type  => 'list', 
	}
 );
 
 # Move
 $lh->move_subscriber(
	{
		-email => 'user@example.com',
		-from  => 'list', 
		-to    => 'black_list', 
	}
  );
 
 # Copy
 $lh->copy_subscriber(
	{
		-email => 'user@example.com',
		-from  => 'black_list', 
		-to    => 'list', 
	}
  );
 
 # Remove
 $lh->remove_subscriber(
	{
		-email => 'user@example.com',
		-type  => 'list', 
	}
  );

=head1 DESCRIPTION

This module represents the API for Dada Mail's subscriptions lists. 

=head2 Subscription List Model

Dada Mail's Subscription List system is currently fairly simple:

=head3  A subscriber is mostly identified by their email address

Usually, when we talk of a, "Subscriber", we're talking about a email address that has been included
in a Dada Mail Subscription List. 

=head3 The Subscription List is made up of Sublists.

A sublist is a list of subscribers. Each sublist is completely separated from each other sublist. 

Each sublist is known because of its type. 

The types of sublists are as follows: 

=over

=item * list

This is your main subscription list and is the most important type of sublist. It holds a Mailing List's B<subscribers>. 
When a mailing list message is sent out, this is the list whose addresses are used. 

=item * black_list

This is the sublist of addresses that are not allowed to join the sublist, B<list> 

The addresses in this sublist do not have to be fully qualified email addresses, 
but can be simple strings, which are then used to match on other addresses, 
for verification. 

=item * white_list

This is the sublist of addresses that are allowed to join the sublist, B<list> 

The addresses in this sublist do not have to be fully qualified email addresses, 
but can be simple strings, which are then used to match on other addresses, 
for verification.

=item * authorized_senders

This is the sublist of addresses that can be allowed to post to a mailing list, from an email client, via the 
B<Dada Bridge> plugin, if this feature has been enabled. 

=item * sub_confirm_list

This is the sublist that keeps subscription information on potential subscribers, 
when they've asked to join a list, but have not yet been verified via an email 
confirmation to subscribe. 

=item * unsub_confirm_list

This is the sublist that keeps unsubscription information on potential unsubscribers, 
when they've asked to leave a list, but have not yet been verified via an email 
confirmation to unsubscribe.

=item * invitelist

This is a sublist of temporary subscribers, who've been invited to join a mailing list. 
It's only used internally and is removed shortly after sending out a list invitation has begun. 

=back

=head3 A Subscription List can have Subscriber Fields

The Subscriber Fields are information that's separate than the email address of a subscriber. 
Their values are arbitrary and can be set to most anything you'd like. 

Internally, the subscriber fields are mapped almost exactly to SQL columns - adding a subscriber 
field will add a column in an SQL table. Removing a field will remove a column.

=head3 Restrictions are enforced by Dada Mail to only allow correct information to be saved in the Subscription List

The most obvious enforcement is that the subscriber has to have a valid email address. 

Another enforcement is that a subscriber cannot be subscribed to a sublist twice. 

A subscriber can be on more than one sublist at the same time. 

Some sublists are used to enforce subscription on other sublists. For example, a subscriber in the B<black_list> 
sublist will not be allowed to joing the, B<list> sublist. 

These enforcements are currently lazy - You I<can> easily break these rules, but you don't want to, 
and checking the validation of a subscriber is easy. The easiest way to break these rules is to work with the backend that 
the subscribers are saved in directly. 

=head3 The Subscription List has various backend options

The Subscription List can either be saved as a series of PlainText files (one file for each type of sublist), 
or as an SQL table. 

Each type of backend has different features that are available. The most notable feature is that the SQL 
backend supports arbitrary Subscriber Fields and the PlainText backend does not. 

Currently, the following SQL flavors are supported: 

=over

=item * MySQL

=item * PostgreSQL

=item * SQLite

=back

Except for being able to change the name of a Subscriber Field in SQLite, every SQL flavor has the same feature set. 

=head1 Public Methods

Below are the list of I<Public> methods that we recommend using when manipulating a Dada Mail Subscription List:

Every method has its paramaters, if required (and when it's stated that they're required, I<they are>), passed as a hashref. 

=head2 Initializing

=head2 new

 my $lh = DADA::MailingList::Subscribers->new({-list => 'mylist'}); 

C<new> requires you to pass a B<listshortname> in, C<-list>. If you don't, your script will die. 

A C<DADA::MailingList::Subscribers> object will be returned. 

=head2 Add/Get/Edit/Move/Copy/Remove a Subscriber

=head2 add_subscriber

 $lh->add_subscriber(
	{
		-email  => 'user@example.com', 
		-type   => 'list',
		-fields => {
					# ...
				   },
	}
);

C<add_subscriber> adds a subscriber to a sublist. 

C<-email> is required and should hold a valid email address in form of: C<user@example.com>

C<-type> holds the sublist you want to subscribe the address to, if no sublist is passed, B<list> is used as a default.

C<-fields> holds the subscription fields you'd like associated with the subscription, passed as a hashref. 

For example, if you have two fields, B<first_name> and, B<last_name>, you would pass the subscriber fields like this: 

 $lh->add_subscriber(
	{
		-email  => 'user@example.com', 
		-type   => 'list',
		-fields => {
					first_name => "John", 
					last_name  => "Doe", 
				   },
	}
 );

Passing field values is optional.

Fields that are not actual fields that are being passed will be ignored. 

=head3 Diagnostics

=over

=item * You must pass an email in the -email paramater!

You forgot to pass an email in the, -email paramater, ie: 

 # DON'T do this:
 $lh->add_subscriber();

=item * cannot do statement (at add_subscriber)!

Something went wrong in the SQL side of things.

=back

=head2 get_subscriber

 my $sub_info = $lh->get_subscriber(
		{
			-email => 'user@example.com', 
			-type  => 'list', 
		}
	);

Returns the subscriber fields information in the form of a hashref. 

C<-email> is required and should hold a valid email address in form of: C<user@example.com>. The address should also be subscribed
and no check is done if the address you passed isn't. 

C<-type> holds the sublist you want to work with. If no sublist is passed, B<list> is used as a default.

=head3 Diagnostics

=over

=item * You must pass an email in the -email paramater!

You forgot to pass an email in the, -email paramater, ie: 

 # DON'T do this:
 $lh->get_subscriber();

=item * cannot do statement (at get_subscriber)!

Something went wrong in the SQL side of things.

=back

=head2 edit_subscriber

 $lh->edit_subscriber(
	{
		-email  => 'user@example.com', 
		-type   => 'list', 
		-fields => 
			{
				# ...
			},
		-method => 'writeover',
	}
 );		

returns C<1> on success. 

Internally, this method removes a subscriber and adds the same subscriber again to the same list.

C<-email> is required and should hold a valid email address in form of: C<user@example.com>

C<-type> holds the sublist you want to subscribe the address to, if no sublist is passed, B<list> is used as a default.

C<-fields> holds the subscription fields you'd like associated with the subscription, passed as a hashref. 

For example, if you have two fields, B<first_name> and, B<last_name>, you would pass the subscriber fields like this: 

 $lh->edit_subscriber(
	{
		-email  => 'user@example.com', 
		-type   => 'list',
		-fields => {
					first_name => "Jon", 
					last_name  => "Doh", 
				   },
	}
 );

Passing field values is optional, although you probably would want to, as this is the point of the entire method.

Fields that are not actual fields that are being passed will be ignored.

C<-method> holds the type of editing you want to do. Currently, this can be either, C<update>, or, C<writeover>. 

C<update> will only save the fields you pass - any other fields saved for this subscriber will not be erased. 

C<writeover> will save only the fields you pass - any other fields will be removed from the subscriber. 

If no C<-method> is passed, B<update> is used as a default.

=head3 Diagnostics

Internally, the subscriber is first removed, than added, using the C<add_subscriber> and, C<remove_subscriber> methods. 
Those diagnostics may pop up, if you use this method incorrectly

=over

=item * The -mode paramater must be set to, 'update', 'writeover' or left undefined!

You didn't set the -mode paramater correctly.

=back

=head2 move_subscriber

 $lh->move_subscriber(
 	{
		-email => 'user@example.com', 
		-from  => 'list', 
		-to    => 'black_list',
	}
 );

C<-email> holds the email address of the subscriber you want to move. 

C<-from> holds the sublist you're moving from. 

C<-to> holds the sublist you're moving to. 

All paramaters are required. No other paramaters will be honored. 

This method will C<die> if the subscriber isn't actually subscribed to the sublist set in, C<-from> or, 
B<is> already subscribed in the sublist set in, C<-to>. 

=head3 Diagnostics

=over

=item * email passed in, -email is not subscribed to list passed in, '-from'

The subscriber isn't actually subscribed to the sublist set in, C<-from> 

=item * email passed in, -email ( ) is already subscribed to list passed in, '-to'

The Subscriber is already subscribed in the sublist set in, C<-to>. 

=item * list_type passed in, -to is not valid

=item * list_type passed in, -from is not valid

=item * email passed in, -email is not valid

=item * cannot do statement (at move_subscriber)!

Something went wrong in the SQL side of things.

=back




=head2 copy_subscriber

 $lh->copy_subscriber(
 	{
		-email => 'user@example.com', 
		-from  => 'list', 
		-to    => 'black_list',
	}
 );

C<-email> holds the email address of the subscriber you want to copy. 

C<-from> holds the sublist you're copying from. 

C<-to> holds the sublist you're copying to. 

All paramaters are required. No other paramaters will be honored. 

This method will C<die> if the subscriber isn't actually subscribed to the sublist set in, C<-from> or, 
B<is> already subscribed in the sublist set in, C<-to>.

=head3 Diagnostics

=over

=item * email passed in, -email is not subscribed to list passed in, '-from'

The subscriber isn't actually subscribed to the sublist set in, C<-from> 

=item * email passed in, -email ( ) is already subscribed to list passed in, '-to'

The Subscriber is already subscribed in the sublist set in, C<-to>. 

=item * list_type passed in, -to is not valid

=item * list_type passed in, -from is not valid

=item * email passed in, -email is not valid

=item * cannot do statement (at move_subscriber)!

Something went wrong in the SQL side of things.

=back

=head2 remove_subscriber

 $lh->remove_subscriber(
	{
		-email => 'user@example.com', 
		-type  => 'list', 
	}
 ); 

C<remove_subscriber> removes a subscriber from a sublist. 

C<-email> is required and should hold a valid email address in form of: C<user@example.com>

C<-type> holds the sublist you want to subscribe the address to, if no sublist is passed, B<list> is used as a default.

No other paramaters are honored.

=head3 Diagnostics

=over

=item * You must pass an email in the -email paramater!

You forgot to pass an email in the, -email paramater, ie: 

 # DON'T do this:
 $lh->remove_subscriber();

=back

=head2 Validating a Subscriber

=head2 allowed_list_types

 my $list_types = $lh->allowed_list_types

Returns a hashref of the allowed sublist types. The keys are the actual sublist types, the value is simply set to, C<1>, for 
easy lookup tabling. 

Takes no paramaters. 

The current list of allowed sublist types are: 

=over

=item * list  

=item * black_list

=item * authorized_senders

=item * testers

=item * white_list

=item * sub_confirm_list

=item * unsub_confirm_list

=item * invitelist

=back

=head2 check_for_double_email

B<Note!> The naming, coding and paramater style is somewhat old and crufty and this method is on the chopping block for a re-write

 my $is_subscribed = $lh->check_for_double_email(
	-Email          => 'user@example.com,
	-Type           => 'list',
	-Match_Type     => 'sublist_centric',
	);

Returns B<1> if the email address passed in, C<-Email> is subscribed to the sublist passed in, C<-Type>.


C<-Email> should hold a string that I<usually> is an email address, although can be only a part of an email address. 

C<-Type> should hold a valid sublist name. 

C<-Type> will default to, C<list> if no C<-Type> is passed.

C<-Status> 

C<-Match_Type> controls the behavior of how a email address is looked for and is usualy something you want to override for the, C<black_list> and C<white_list> sublists. 

The sublists have different matching behaviors. For example, if, C<bad> is subscribed to the C<black_list> sublist, this will return C<1>

 my $is_subscribed = $lh->check_for_double_email(
	-Email          => 'bad@example.com,
	-Type           => 'list',
	-Match_Type     => 'sublist_centric',
	);

Since the black list is not simply a list of addresses that are black listed, it's a list of patterns that are black listed. 

C<-Match_Type> can also be set to, C<exact>, in which case, this would return, C<0>

 my $is_subscribed = $lh->check_for_double_email(
	-Email          => 'bad@example.com,
	-Type           => 'list',
	-Match_Type     => 'exact',
	);

C<-Match_Type> will default to, C<sublist_centric> id no C<-Math_Type> is passed. 

=head2 subscription_check

	my ($status, $errors) =  $lh->subscription_check(
		{
			-email => 'user@example.com', 
			-type  => 'list'
			-skip  => []
		}
	); 


C<-email> holds the address you'd like to validate. It is required. 

C<-type> holds the sublist you want to work on. If not passed, C<list> will be used as the default.

C<-skip> holds an arrary ref of checks you'd like not to have done. The checks are named the same as the errors.

For example:

 my ($status, $errors) = $lh->subscription_check(
								{
                               	-email => 'user@example.com', 
                        			-skip => [qw(black_listed closed_list)],
                       		}
							); 

This method returns an array with two elements. 

The first element is the status of the validation. B<1> will be set if the validation was successful, B<0> if there was
an error. 

The second element is a list of the errors that were found when validating, in the form of a hashref, with its name
as the name of the error and the value set to, B<1> if that error was found. 

The errors, which are fairly self-explainitory are as follows: 

=over

=item * invalid_email

=item * subscribed

=item * closed_list

=item * mx_lookup_failed

=item * black_listed

=item * not_white_listed

=item * over_subscription_quota

=item * already_sent_sub_confirmation

=item * settings_possibly_corrupted

=item * no_list

=back

Unless you have a special case, always use this method to validate an email subscription. 

=head2 subscription_check_xml

	my ($xml, $status, $errors) =  $lh->subscription_check_xml({-email => $email}); 

Same as B<subscription_check> but also returns an simplified XML-esque document describing the same 
thing.This was initially used to talk to Adobe Flash Apps. It hasn't been updated in a while. 

The XML-esque doc is as so: 

 <subscription>
  <email>some@where.com</email>
  <status>1</status>
  <errors>
   <error>no_list</error>
  </errors>
 </subscription>

=head2 unsubscription_check

 my ($status, $errors) =  $lh->unsubscription_check(
								{
									-email => 'user@example.com',
									-type  => 'list', 
									-skip  => [],
									
								}
						   ); 

Like the subscription_check method, this method returns a $status and a hashref of $%errors
when checking the validity of an unsubscription. The following errors may be returned: 

=over

=item * no_list

=item * invalid_email

=item * not_subscribed

=item * settings_possibly_corrupted

=item * already_sent_unsub_confirmation

=back

Again, any of these tests can be skipped using the -skp argument. 

=head2 Add/Get/Edit/Remove a Subscription Field

As noted, Subscriber Fields are only available in the SQL backends.

It should be also noted that future revisions of Dada Mail may see these types of methods in their own object, ie: 

C<DADA::MailingList::Subscribers::Fields>

or, whatever.

=head2 filter_subscribers

 my (
	$subscribed, 
	$not_subscribed, 
	$black_listed, 
	$not_white_listed, 
	$invalid
	) = $lh->filter_subscribers(
		{
			-emails => [], 
			-type   => 'list',
		}
	);

This is a very powerful and complex method. There's dragons in the code, but the API is pretty simple. 

Used to validated a large amount of addresses at one time. Similar to C<subscripton_check> but is meant for more than one
address. It's also meant to be  bit faster than looping a list of addresses through C<subscripton_check>. 

Accepts two paramaters. 

C<-email> is an array ref of email addresses . 

C<-type> is the sublist we want to validate undef. 

Depending on the type of sublist we're working on, validation works slightly different. 

Returns a 5 element array, each element contains an array ref of email addresses. 

This method also sets the precendence of black listed and white listed addresses, since an address can be a member of both sublists. 

The precendence is the same as what's returned: 

=over

=item * black_list

=item * white_list

=item * invalid

=back

In other words, if someone is both black listed and white listed, during validation, it'll be returned that they're black listed. 

=head2 filter_subscribers_w_meta

 my (
 	$subscribed, 
 	$not_subscribed, 
 	$black_listed, 
 	$not_white_listed, 
 	$invalid
 	) = $lh->filter_subscribers(
 		{
 			-emails => [], 
 			-type   => 'list',
 		}
 	);

Similar to C<filter_subscribers>, but allows you to pass the subscriber field information with the email address.

The, C<-email> paramater should hold an arrayref of hashrefs, instead of just an array ref. The hashref itself should have the form of: 

 {
	-email => 'user@example.com',
	-fields => { 
		-field1 => 'blah', 
		-field2 => 'blahblah', 
	}
 }

No validation is done on the subscriber fields - they're simply passed through and returned. 

Returns a 5 element array of hashrefs, in the same format as what's passed.

=head2 add_subscriber_field

 $lh->add_subscriber_field(
	-field          => 'myfield', 
	-fallback_value => 'My Fallback Value', 
 ); 

C<add_subscriber_field> adds a new subscriber field. 

C<-field> Should hold the name of the subscriber field you'd like to add. It is required. 

C<-fallback_value> holds what's known as the, B<fallback value>, which is a value used in some instances of Dada Mail, 
if no value is saved in this field for a particular subscriber. It is optional. 

=head3 Diagnostics

=over

=item * You must pass a value in the -field paramater!

You forget to name your new field.

=item * Something's wrong with the field name you're trying to pass (yourfieldname). Validate the field name before attempting to add the field with, 'validate_subscriber_field_name'
You forgot to validate the field name you passed in, C<-field>. 

This will only be a warning and won't be fatal.

This error should actually be followed by more warnings, looking like this:

C<Field Error:>

Which will tell you exactly which test you failed.

=item * cannot do statement (at add_subscriber_field)!

Something went wrong in the SQL side of things.

=back

=head2 subscriber_fields

 my $fields = $lh->subscriber_fields;
 
 # or: 
 
 foreach(@{$lh->subscriber_fields}){
  # ...	
 }

Returns the subscriber fields in the Subscription List, in the form of an array ref. 

Takes no arguments... usually. 

Internally (and privately), it does accept the, C<-dotted> paramater. This will prepend, 'subscriber.' to every field name.

=head3 Diagnostics

None that I can think of. 

=head2 edit_subscriber_field

 $lh->edit_subscriber_field(
 	{ 
		-old_name => 'old', 
		-new_name => 'new', 
		
	}
 ); 

Changes the name of a Subscriber Field. 

Returns 1 on success. 

C<-old_name> holds the name of the field you want to rename.

C<-new_name> holds what you'd like to rename the field in C<-old_name> to. 

Both paramaters are required.

=head3 Diagnostics

=over

=item * You MUST supply the old field name in the -old_name paramater!

You forgot to pass the old field name.

=item * You MUST supply the new field name in the -new_name paramater!

You forgot to pass the new field name.

=back

=head2 remove_subscriber_field

 $lh->remove_subscriber_field(
	{
		-field => 'myfield', 
	},
 ); 

Removes the field specified in, C<-field>. C<-field> is required.

Returns C<1> upon success. 

=head3 Diagnostics

=over

=item * You MUST pass a field name in, -field! 

You forgot to set, C<-field>

=item * cannot do statement! (at: remove_subscriber_field)

Something went wrong on the SQL side of things. 

=back

=head2 subscriber_field_exists

 my $exists = $lh->subscriber_field_exists(
	{
		-field => 'myfield', 
	}
 ); 

Checks the existance of a subscriber field name. 

=head3 Diagnostics

=over

=item * You MUST pass a field name in, -field! 

You forgot to set, C<-field>

=item * cannot do statement! (at: remove_subscriber_field)

Something went wrong on the SQL side of things. 

=back

=head2 validate_subscriber_field_name

 my ($status, $errors) = $lh->validate_subscriber_field_name(
							{
								-field => $field,
								-skip  => [],
							}
						); 

Used to validate a subscriber field name and meant to be used before a subscriber field is added. 

Returns a two element array, 

The first element is either C<1> or C<0> and is the status of the validation. A status of, B<1>
means the validation was successful; B<0> means the validation had problems. 

The second element is a list of the errors that were found when validating, in the form of a hashref, with the name
of the error set as the key and the value set to, B<1> if this error was found. 

C<-field> is required and should be the name of the field you're attempting to validate. 

C<-skip> is an optional paramater and is used to list the errors you're not so interested in. It should be set to an array ref. 

=head3 Subscriber Validation Requirements

Subscriber fields are validated mostly to make sure they're also valid SQL column names for all the SQL backends that are 
supported and also that the fields are not already used for internal SQL fields used by the program for other purposes. 
Validation is also done sparingly for reserved words. 

The entire list of errors that can be reported back are as follows: 

=over

=item * field_blank

=item * field_name_too_long

length of 64

=item * slashes_in_field_name

C</> or, C<\>

=item * spaces

=item * weird_characters

Basically anything that's not alpha/numeric

=item * quotes

C<'> and, C<">

=item * field_exists 

=item * field_is_special_field

The field name is one of the following: 

=over

=item * email_id    

=item * email       

=item * list        

=item * list_type   

=item * list_status 

=item * email_name  

=item * email_domain

=back

=back

=head2 validate_remove_subscriber_field_name

 my ($status, $errors) = $lh->validate_remove_subscriber_field_name(
 							{ 
 								-field      => $field,
 								-skip       => [],
 								-die_for_me => 0, 
 							}
 						); 
  

Similar to, C<validate_subscriber_field_name> is used to validate a subscriber field name 
and is meant to be used before a subscriber field is I<removed>. 

Returns a two element array, 

The first element is either C<1> or C<0> and is the status of the validation. A status of, B<1>
means the validation was successful; B<0> means the validation had problems. 

The second element is a list of the errors that were found when validating, in the form of a hashref, with the name
of the error set as the key and the value set to, B<1> if this error was found. 

C<-field> is required and should be the name of the field you're attempting to validate. 

C<-skip> is an optional paramater and is used to list the errors you're not so interested in. It should be set to an array ref. 

C<-die_for_me> is another optional paramater. If set to, C<1>, an error found in validation will prove fatal. 

The entire list of errors that can be reported back are as follows: 

=over


=item * field_is_special_field

The field name is one of the following: 

=over

=item * email_id    

=item * email       

=item * list        

=item * list_type   

=item * list_status 

=item * email_name  

=item * email_domain

=back

=item * field_exists

=item * number_of_fields_limit_reached

=back

=head2 get_fallback_field_values

 my $field_values = $lh->get_fallback_field_values;

Returns the name of every subscriber field and its fallback value in the form of a hashref. 

The fallback values are actually saved in the List Settings. 

Take no arguments.

=head2 _save_fallback_value

 $lh->_save_fallback_value(
		{
			-field          => $field, 
			-fallback_value => $fallback_field_value, 
		}
 );

B<Currently marked as a private method>. 

Used to save a new fallback field value for the field set in, C<-field>. I<usually> shouldn't be used alone, but there is 
actually no way to edit a fallback field value, without using this method. 

If used on an existing field, make sure to remove the fallback field value first, using, C<_remove_fallback_value>, ala: 

 $lh->_remove_fallback_value({-field => 'myfield'});
 $lh->_save_fallback_value({-field => 'myfield'}, -fallback_value => 'new_value');
 
Is called internally, when creating a new field via, C<add_subscriber_field>, so make sure not to call it twice. 

=head3 Diagnostics

=over

=item * You MUST pass a value in the -field paramater!

=back

=head2 _remove_fallback_value

 $lh->_remove_fallback_value(
		{
			-field => 'myfield', 
		}
 ); 

B<Currently marked as a private method>. 

Used to remove a fallback field value. Used internally.

=head3 Diagnostics

=over

=item * You MUST pass a value in the -field paramater!

=back


=head1 AUTHOR

Justin Simoni http://dadamailproject.com

=head1 LICENCE AND COPYRIGHT

Copyright (c) 1999-2008 Justin Simoni All rights reserved. 

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, 
Boston, MA  02111-1307, USA.

=cut 

