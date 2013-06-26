#!/usr/local/bin/perl

# Chaos Tools 2.1
# copyright me so gityerstinkinhandsoff

#########################
# INIT

use lib ".";

use CGI qw(:standard);
use WordNet::QueryData;

#########################
# CONSTANTS

$sp = ' ';
$brk = "\n";
$brk2 = "\n\n";

# $dictdir = "/home/knox/home/amdavis/cgi/ptools/dict";
$dictdir = "dict";
sub debug {$debug?print @_:0;@_;}

#########################
# UTIL

#pick random member of list
sub Pick {
    my @lst = @_;
    return $lst[int rand scalar @lst];
}

#########################
# REARRANGE

# pulls substring from string & randomly redistributes it over string
# - source $str, substring to redist $sub, redist at points matching $pt,
#   $type is [same, random, exactly], $num quantifies random limit and exactly
# - note that occurences of $sub become redist points
sub StringRedistribute {
    
    my ($str, $sub, $pt, $type, $num) = @_;
    my $c;

    if ($type eq 'same') {
	$c = 0;
	while ($str =~ /$sub/g) { $c++ } } # search for sub
    elsif ($type eq 'random') {
	$c = int rand ($num + 1); }
    elsif ($type eq 'exactly') {
	$c = $num; }

    $str =~ s/$sub/$pt/g; # repl sub with pt
    my @parts = split $pt, $str; # split on redist pts
    my @interstices = ($pt) x ((scalar @parts) - 1);
    if ($c > scalar @interstices) { $c = scalar @interstices; }

    for (1 .. $c) {
	do { $r = int rand scalar @interstices;
	 } until (@interstices[$r] ne $sub);
	splice(@interstices, $r, 1, $sub);
    }
    
    push my @distributed, shift @parts;
    while (@parts) { push @distributed, shift @interstices, shift @parts; }

    return join '', @distributed;
}

#########################
# SCATTER
#  a page is a list of (coord,word), where coord is a location in linearized 2D

# return 1 if word poses no spatial conflicts on page
sub ScatterPageWordNoOverlap {

    my ($pagein, $word, $begw) = @_;
    my @page = @$pagein;

    while (@page) {
	my $endw = $begw + length $word;
	my $begk = shift @page;
	my $endk = $begk + length shift @page;
	if (($endw >= $begk && $endw <= $endk) 
	    || ($endk >= $begw && $endk <= $endw))
	{return 0;}
    }
    return 1;
}

# return new page with words scattered randomly
sub Scatter {
    my ($pagein, $wordsin, $dimx, $dimy) = @_;
    my @page = @$pagein;
    my @words = @$wordsin;
    my $c;

    while (@words) {
	my $word = shift @words;
	
	# pick a point
	if ($scat_order) { # blank spot after (and near) most recent word
	    do {
		my $beg = @page ? $page[0] + length $page[1] : 0;
		$c = int rand ($dimx * $dimy - $beg) / (scalar @words + 1)
		    + $beg;
	    } until ($c % $dimx <= ($dimx - length $word)); # no line overrun
	} else { # any blank spot
	    do {
		my $x = int rand $dimx - length $word; # no line overrun
		my $y = int rand $dimy;
		$c = $dimx * $y + $x;
	    } until &ScatterPageWordNoOverlap(\@page, $word, $c);
	}

	# place the word at the point picked
	unshift @page, $c, $word;
    }

    return @page;
}

sub ScatterPageGenPrintString {

    # initialize
    my($pagein, $dimx, $dimy) = @_;
    my @page = @$pagein;
    my @prinpage = ($sp) x ($dimx * $dimy);

    # insert words
    while (@page) {
	splice @prinpage, shift @page, length ($wrd = shift @page),
	split("", $wrd);
	}

    # insert linebreaks
    for (0 .. ($dimy - 1)) {
	splice @prinpage, ($dimy - $_) * $dimx, 0, $brk;
    }

    return join '', @prinpage;
}

#########################
# SHUFFLE

sub Shuffle {
    my @toshuf = @_;
    my @shuf = ();

    while (@toshuf) {
	splice @shuf , ($i = int rand scalar @shuf + 1), 0, shift @toshuf;
    }

    return @shuf;
}

#########################
# WORDNET

# bad solution. rather need to prohibit certain results (e.g. 'atomic number XX')
my @constantwords = ('a','are','as','in','me','no','i','on','am','an');

sub WNStrip {
    my ($word) = @_;
    my $out = substr($word, 0, index($word, '#'));
    $out =~ s/\_/$sp/g;
    return $out;
}

# also strips WN markup
sub RemoveFrom {
    my ($item, $lstin) = @_;
    my @lst = @$lstin;
    my @out = ();
    while (@lst) {
	my $member = &WNStrip(shift @lst);
	if( uc($member) ne uc($item) ) { 
	    push @out, $member;
	}
    }
    return @out;
}

# fix this sensetypes stuff (then concat over all types)
sub WNGetAltSense {
    my($wn, $word, $sensetypesin) = @_;
    my @sensetypes = @$sensetypesin;
    my @POS = $wn->querySense($word);
    my @pop = ();
#print '|',@sensetypes[0],'|';
    while (@POS) {
	my $POS_item = shift @POS;
	my @senses = $wn->querySense($POS_item);
	map {
#	    my @syns = $wn->querySense($_, shift @sensetypes);
	    my @syns = $wn->querySense($_, "syns");
	    map { push @pop, $_; } @syns;
	} @senses;
    }
    my @popuniq = &RemoveFrom($word, \@pop);
    if (scalar @popuniq > 0) {
	return &Pick(@popuniq);
    }
    else { return $word; }
}

# todo:
# preserve punctuation
# deal with plurals somehow...
# choices:
#  sense types (synonyms; hyponyms; hypernyms; holonyms...)
#  show candidates...
sub WNGetAltSenseAll {
    my ($in) = @_;
    my $wn = WordNet::QueryData->new($dictdir);
    my @sensetypes = ("syns", "hypo");

    return join $brk,
    map { join $sp, map {
# membership check; make a fn
	my $word = $_;
	my @prohibited = grep { uc($word) eq uc($_); } @constantwords;
	if (scalar @prohibited == 0) {
	    &WNGetAltSense($wn, lc($word), \@sensetypes); 
	} else {
	    $word;
	}
    }
	  (split $sp, $_); }
    (split $brk, $in);
}

#  print "Synset: ", join(", ", $wn->querySense("cat#n#7", "syns")), "\n";
#  print "Hyponyms: ", join(", ", $wn->querySense("cat#n#1", "hypo")), "\n";
#  print "Parts of Speech: ", join(", ", $wn->querySense("run")), "\n";
#  print "Senses: ", join(", ", $wn->querySense("run#v")), "\n";
#  print "Forms: ", join(", ", $wn->validForms("lay down#v")), "\n";
#  print "Noun count: ", scalar($wn->listAllWords("noun")), "\n";
#  print "Antonyms: ", join(", ", $wn->queryWord("dark#n#1", "ants")), "\n";

#########################
# PRINT

###############
# vars & params

$tool_default = 'scatter';
$scat_dimmax = 60;
$rearr_nummax = 50;
$holdchar = "\f"; # be careful with //m regexps; this is a placeholder

$tool = param('tool');
$text = param('text');
$result = "Replace\nthis text\nwith yours,\n\nchoose a tool below, " .
    "and\n\nthen click\nGo.";
$rearrange = param('rearrange') || 'stanzificaton';
$rearr_typ = param('rearr_typ') || 'same';
$rearr_num = param('rearr_num') || 10;
$shuffle = param('shuffle') || 'lines';
$scat_dimx = param('scat_dimx') || 40;
$scat_dimy = param('scat_dimy') || 15;
$scat_order = param('scat_order') || 0;
$debug = param('debug') || 0;
$randomnum = param('randomnum') || 100;

###############
# HTML

print header(),
    start_html(-title=>'Chaos'),
    h2('Chaos');

if ($tool && $text) {

    print i($debug?'DEBUGGING ':'', "$tool result:"), br;
    $result = $text;
    $result =~ s/\r//g;
    chomp $result;

    if ($tool eq 'rearrange') { #rearrange
	if (($rearrange eq 'stanzification') || ($rearrange eq 'both')) {
	    $result = StringRedistribute($result, $brk2, $brk, 
					 $rearr_typ, $rearr_num); 
	}

	if (($rearrange eq 'lineation') || ($rearrange eq 'both')) {
	    $result =~ s/$brk2/$holdchar/g; # save stanzas
	    $result = StringRedistribute($result, $brk, $sp, 
					 $rearr_typ, $rearr_num);
	    $result =~ s/$holdchar/$brk2/g; # restore stanzas
	}
    }

    elsif ($tool eq 'shuffle') { # shuffle 
	
	if ($shuffle eq 'lines') {
	    $result = join $brk, &Shuffle(split $brk, $result);
	}

	elsif ($shuffle eq 'words') {
	    $result = join $brk,
	    map { join $sp, &Shuffle(split $sp, $_); }
	    (split $brk, $result);
	}

	elsif ($shuffle eq 'both') {
	    # maintain number of stanzas and lines
	    my $numstanzas = ($result =~ s/$brk2/ /g);
	    my $numlines = ($result =~ s/$brk/ /g);
	    @toshuf = ((map { $_ . $sp } split $sp, $result),
		       (($brk) x $numlines),
		       (($brk2) x $numstanzas));
	    $result = join '', &Shuffle(@toshuf);
	}

    } # shuffle

    elsif ($tool eq 'scatter') { # scatter
	$result =~ s/[$brk\s]+/ /g;
	my @words = split $sp, $result;
	my @page = ();
	my @s = &Scatter(\@page, \@words, $scat_dimx, $scat_dimy);
	$result = &ScatterPageGenPrintString(\@s, $scat_dimx, $scat_dimy);

    } # scatter

    elsif ($tool eq 'syn') { # wordnet syn
	$result = &WNGetAltSenseAll($result);
    }

    elsif ($tool eq 'test') { #test
	$result =~ s/[$brk\s]+/ /g;
	$result = join '+', split $sp, $result;
	$result .= "$brk2<i>you're testing me, aren't you?<i>";
    } # test

    elsif ($tool eq 'randomnum') { #randomnum
	$result = (int rand $randomnum) + 1;
    } # randomnum

    print table({border=>3}, Tr(td(pre($result)))),
    br, hr, a({href=>self_url}, 'Try the same text again'), ', or', br;
}

# new form
$toolnum = 1;
print start_form,

    # new input
    textarea(-name=>'text', -default=>$result, -override=>1,
	     -rows=>10, -cols=>($scat_dimmax + 1)),
    br, br, 'Tools:', br,

    # scatter config
    $toolnum++, ' ',
    radio_group(-name=>'tool', -values=>['scatter'], 
		-default=>($tool || $tool_default)),
    ': horizontal ',
    popup_menu(-name=>'scat_dimx', values=>[1..$scat_dimmax],
	       -default=>"$scat_dimx"),
    ', vertical ',
    popup_menu(-name=>'scat_dimy', values=>[1..$scat_dimmax],
	       -default=>"$scat_dimy"),
    ', ',
    checkbox(-name=>'scat_order', -checked=>$scat_order,
	     -label=>'maintain word order'),
    br,

    # rearrange
    $toolnum++, ' ',
    radio_group(-name=>'tool', -values=>['rearrange'],
		-default=>($tool || $tool_default)),
    ': ',
    popup_menu(-name=>'rearrange', values=>['stanzification','lineation',
					    'both'],
	       -default=>$rearrange),
    ', number of breaks ',
    radio_group(-name=>'rearr_typ', -values=>['same', 'random', 'exactly'],
	     -default=>$rearr_typ),
    ' ',
    popup_menu(-name=>'rearr_num', values=>[1..$rearr_nummax],
	       -default=>"$rearr_num"),
    br,

    # shuffle config
    $toolnum++, ' ',
    radio_group(-name=>'tool', -values=>['shuffle'],
		-default=>($tool || $tool_default)),
    ': ',
    popup_menu(-name=>'shuffle', -values=>['lines', 'words', 'both'],
	       -default=>$shuffle),
    br,

    # syn config
    $toolnum++, ' ',
    radio_group(-name=>'tool', -values=>['syn'],
		-default=>($tool || $tool_default)),
    br, br,

    # buttons
    submit(-value=>'Go'),
#    ' ', reset,
#    defaults(-value=>'Reset'),

    # test, debug
    br,br,br,br,br,br,
    hr, hr, 'ignore this stuff...', br, br, reset, br, '(',
    radio_group(-name=>'tool', -values=>['test'],
		-default=>($tool || $tool_default)),
    '; ',
    checkbox(-name=>'debug', -checked=>$debug),
    ')',br,
    '(',
    radio_group(-name=>'tool', -values=>['randomnum'],
		-default=>($tool || $tool_default)),
    ': from 1 to ',
    popup_menu(-name=>'randomnum', values=>[2..300], -default=>100),
    ')',br,

    end_form;

print end_html();

#print <<ENDTEXT;
#Hello, this
#is a test of endoftext.
#ENDTEXT

