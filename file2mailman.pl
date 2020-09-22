#!/usr/bin/perl

=begin text

###################################################
# file2mailman.pl
#####################
# Purpose: to keep UW Mailman lists in sync
# with files of email addresses that are built 
# nightly from a departmental database.
# 
# For each list, I created a UWGS group named 
# "uw_mydept_mailinglists_<listname>" and a
# corresponding Mailman list named "mydept_<listname>".
# This script reads email addresses from a file named 
# "<listname>.addrlst" and formats a series 
# PUT requests in $chunksize chunks to populate the
# corresponding group.  The groups are synchronized 
# nightly to the corresponding Mailman lists, by the
# grace of UW-IT.
#
# Invoked from a cron script as 
#
#    for l in `ls *.addrlst |cut -d"." -f1`;
#    do perl file2mailman.pl $l;
#    done
#
# requires (redhat packages)
#    perl-REST-Client
#    perl-LWP-Protocol-https
#    perl-JSON
#
# Replace uw_chem_ in UWGS name with your UWGS 
# stem prefix.
# Adjust $rest_timeout and $chunksize as needed.
#
# author: ketcham@uw.edu
######################################################

=end text
=cut

use warnings ;
use strict ;

use Data::Dumper;
$Data::Dumper::Terse = 1 ;
$Data::Dumper::Indent = 1 ;
$Data::Dumper::Sortkeys = 1 ;

use JSON ;
use REST::Client ;

my $mlist = $ARGV[0] ;
($mlist && $mlist =~ /^\w+$/) || die "usage: $0 <listname>" ;
my $gws_host  = 'https://groups.uw.edu:7443' ;

my $gws_cert    = 'Certs/mlistwriter.crt' ;
my $gws_key = 'Certs/mlistwriter.key' ;
my $uwca = 'Certs/UWServicesCA.cacert' ;
my $rest_timeout = 100 ;
my $gwsclient = REST::Client->new({
	host    => $gws_host,
	cert    => $gws_cert,
	key     => $gws_key,
	timeout => $rest_timeout,
	}) or die ;

my $MLIST_GROUP = 'uw_chem_mailinglists_'.$mlist ;

my $uri = "/group_sws/v3/group/$MLIST_GROUP/member" ;
print "URI: $uri \n" ;
$gwsclient->addHeader ('Accept' => 'application/json') ;
$gwsclient->addHeader ('Content_Type' => 'application/json') ;

# post with empty content to clear the list
print "Deleting all members from group \"$mlist\"\n" ;
$gwsclient->POST($uri, " { data: [ ] } " ) ;	
&checkresponse ;

open MEMBERS, "$mlist.addrlst" ;

my $putlist = "" ;
my $i=0 ;
my $c=0 ;

my $chunksize = 25 ;
print "chunk size $chunksize\n" ;

while (my $addr = <MEMBERS>)
{
	chop $addr;
	#trim
	$addr =~ s/^\s+|\s+$//g;
	#seems that UWGS will only accept foreign email addresses
	#  @uw.edu addrs have to be stripped to uw netids
	if (($addr =~ /(^\w+)\@(uw.edu|u.washington.edu)/))
	{
		$putlist .= "$1,";
	}elsif ($addr =~ /^\S+\@\S+$/)
	{
		$putlist .= "$addr,";
	}else
	{
		print "Invalid email address format: $addr\n";
	}
#chunkify it
	&putto if ($i++ == $chunksize);
}
&putto;

sub putto
{
	#remove hanging comma
	chop $putlist;
	$c++;
	print "Putting chunk $c\n";
	$gwsclient->PUT($uri."/".$putlist);
	&checkresponse;
	#reset for next chunk
	$i = 0;
	my $putlist = "";
}
	
sub checkresponse
{
    if( $gwsclient->responseCode() eq '200' ){
         print "successful (200)\n";
     }
     else {
        print Dumper $gwsclient->responseCode();
        print Dumper $gwsclient->responseContent ();
    }
}
