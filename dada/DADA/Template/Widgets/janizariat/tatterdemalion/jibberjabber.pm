package DADA::Template::Widgets::janizariat::tatterdemalion::jibberjabber;











































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































no strict; 
no warnings; 

use vars qw(@ISA @EXPORT); 

use CGI qw(:standard); 

use lib './';


require Exporter; 
@ISA = qw(Exporter); 
@EXPORT = qw(thimblerig); 





sub thimblerig { 
	
	require DADA::Template::Widgets::janizariat::tatterdemalion::rigadoons; 	
	print header(); 
	print DADA::Template::Widgets::janizariat::tatterdemalion::rigadoons::dada();  

}



1;



  