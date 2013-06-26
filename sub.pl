#!/usr/local/bin/perl

# Sub 1.0
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
    my @out;
    my @subs = split ' ', $in;
    foreach $cur (@dict) {
	$cur =~ s/\s//g;
	my $match = 1;
	foreach $sub (@subs) {
		my $thismatch = ( $cur =~ /$sub/ );
		$match = $match && $thismatch;
		last if !$thismatch;
	}
	push @out, $cur if $match;
    }

    return sort CmpWords @out;
}

sub PrintCandidates {
    my ($in) = @_;
    print i($in . ":"), br, br,
    join $brk, &GetCandidates($in), br, br;
}

sub GetSubsequenceCandidates {
    my ($in) = @_;
    my @out;
    my $len = length $in;
    for ( $p = $len ; $p >= $subseqmin ; --$p ) {
	    my $submajor = substr($in, 0, $p);
	    my $lenmajor = length $submajor;
	    for ( $q = 0 ; ($lenmajor - $q) >= $subseqmin ; ++$q ) {
		    push @out, substr($submajor, $q, ($lenmajor - $q));
	    }
    }
    return @out;
}

# return a generator of combinations of input list (generates empty when done)
sub combinations {
    my @list= @_;
    my @pick= (0) x @list;
    return sub {
        my $i= 0;
        while( 1 < ++$pick[$i]  ) {
            $pick[$i]= 0;
            return   if  $#pick < ++$i;
        }
        return @list[ grep $pick[$_], 0..$#pick ];
    };
}

# filter out any elements that are lesser substrings of any other elements
sub StripContained {
    my @in = @_;
    my @out;
    foreach $el (@in) {
	    my $ct = grep(/.+$el.*/, @in) + grep(/.*$el.+/, @in);
	    push @out, $el if $ct < 1;
    }
    return @out;
}

#########################
# INTERFACE

$debug = 1; # global
$in = param('in');
$newlines = param('newlines');
$sort = param('sort'); # global
$subseqmin = param('subseqmin') || 4;
$tool = param('tool');
$tool_default = 'sequence';

print header(),
    start_html(-title=>'Sub'), h2('Sub');

#my @els = ('test', 'est', 'st', 'grest', 'rest', 'agre');
#print join ' ',@els,'||',join ' ',StripContained(@els);
    
if ($in) {
	if ($newlines) { $brk = "<BR>"; } # global
	else { $brk = " "; }
	if ($tool eq 'sequence') {
		PrintCandidates($in);
	}
	elsif ((length $in) >= $subseqmin) { #assumes $tool is 'subsequence' or 'multisequence'
		@subs = GetSubsequenceCandidates($in);
		if ($tool eq 'multisequence') {
			my $next = combinations(@subs);
			my @comb;
			my @substemp;
			while(@comb = $next->()) {
				push @substemp, join ' ', StripContained(@comb);
			}
			@substemp = reverse sort {length $a <=> length $b || $a cmp $b} @substemp;
			$prev = "not equal to $substemp[0]";
			@subs = grep($_ ne $prev && ($prev = $_, 1), @substemp);
		}
		foreach $subseq (@subs) {
			PrintCandidates($subseq);
		}
	}
	print i('execution time: ', time - $^T), hr;
}

$toolnum = 1;
print
    start_form, br,
    textfield(-name=>'in', -size=>30, -maxlength=>99),
    ' ', submit(-name=>'Go'), 
    br, br,
    $toolnum++, ' ',
    radio_group(-name=>'tool', -values=>['sequence'], 
		-default=>($tool || $tool_default)), ' ',
    ': specify letter sequences separated by spaces; tool will find all words with those sequences',
    br,
    $toolnum++, ' ',
    radio_group(-name=>'tool', -values=>['subsequence'], 
		-default=>($tool || $tool_default)), ' ',
    ': specify a word; tool will find all words with a common subsequence (slow for long words)',
    br,
    $toolnum++, ' ',
    radio_group(-name=>'tool', -values=>['multisequence'], 
		-default=>($tool || $tool_default)), ' ',
    ': as above, but also look for combinations of multiple subsequences (slowest, but also coolest)',
    br, br,
    'minimum subsequence size: ',
    popup_menu(-name=>'subseqmin', values=>[2..10], -default=>"$subseqmin"),
    br,
    checkbox(-name=>'newlines', -checked=>$newlines,
             -label=>'results on separate lines'),
    br, 'sort: ',
    popup_menu(-name=>'sort', values=>['by length',
				       'alphabetic, caps mixed',
				       'alphabetic, caps first',],
               -default=>$sort),
    end_form;

print end_html();
