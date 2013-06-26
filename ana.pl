#!/usr/local/bin/perl

# Ana 1.0
# copyright me so gityerstinkinhandsoff

#########################
# INIT

use CGI qw(:standard);

my $dictloc = "words";

# doesn't return correctly
sub debug {$debug?print '|',@_:0;@_;}

sub CmpWords {
    if ($sort eq 'by length') {
	my $diff = (length $a) - (length $b);
	$diff /= abs $diff if $diff != 0;
	return $diff;
    } elsif ($sort eq 'alphabetic, caps mixed') {
	return (uc($a) cmp uc($b));
    } else {
	return $a cmp $b;
    }
}

sub GetCandidates {
    my ($in) = @_;
    open (dictfile, $dictloc);
    my @dict = <dictfile>;
    my %inlet, @out;

    if ($limit) {
	for ( $p = 0 ; $p < length $in ; ++$p ) {
	    my $ch = substr($in, $p, 1);
	    if ($inlet{uc($ch)}) { $inlet{uc($ch)}++; }
	    else { $inlet{uc($ch)} = 1; }
	}
    }

    while (@dict) {
	my $cur = shift @dict;
	my $c = 0;
	my %curlet;

	$cur =~ s/\s//g;
	my $found = 1;

	for ( $p = 0 ; $p < length $cur ; ++$p ) {
	    my $ch = substr($cur, $p, 1);
	    
	    if ($limit) {
		if ($curlet{uc($ch)}) { $curlet{uc($ch)}++; }
		else { $curlet{uc($ch)} = 1; }
	    }
	    
	    if (($case && ($in !~ /$ch/i)) ||
		((not $case) && ($in !~ /$ch/)) ||
		($limit && ($curlet{uc($ch)} > $inlet{uc($ch)}))) {
		$found = 0;
		last;
	    }
	}
	push @out, $cur if $found;
    }

    return sort CmpWords @out;
}

#########################
# INTERFACE

$debug = 1; # global
$in = param('in');
$newlines = param('newlines');
$limit = param('limit'); # global
$case = param('case'); # global
$sort = param('sort'); # global

print header(),
    start_html(-title=>'Ana'), h2('Ana');

if ($in) { 
    if ($newlines) { $brk = "<BR>"; } # global
    else { $brk = " "; }
    print i($in . ":"), br, br,
    join $brk, &GetCandidates($in), br, br, hr; 
}

print start_form, br,
    textfield(-name=>'in', -size=>30, -maxlength=>99),
    ' ', submit(-name=>'Go'), 
    br,
    checkbox(-name=>'case', -checked=>$case,
             -label=>'case insensitive'),
    br,
    checkbox(-name=>'newlines', -checked=>$newlines,
             -label=>'results on separate lines'),
    br,
    checkbox(-name=>'limit', -checked=>$limit,
             -label=>'limit to letter count of source'),
    br, 'sort ',
    popup_menu(-name=>'sort', values=>['by length',
				       'alphabetic, caps mixed',
				       'alphabetic, caps first',],
               -default=>$sort),
    end_form;

print end_html();
