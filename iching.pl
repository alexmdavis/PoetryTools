#!/usr/local/bin/perl

# I Ching 1.0
# copyright me so gityerstinkinhandsoff

#########################
# INIT

use CGI qw(:standard);
$sp = ' ';
$brk = "\n";

sub debug {$debug?print @_:0;@_;}

#########################
# I CHING

# build hexagram ground up
#  using yarrow probabilities: solid (2) 5/16, broken (1) 7/16,
#   changing solid (0) 3/16, changing broken (3) 1/16

sub HexThrowBasic {
    my @throw;
    for (0..5) {
	my $r = int rand 16;
	if ($r == 0) { $throw[$_] = 3; }
	elsif ($r < 6 ) { $throw[$_] = 2; }
	elsif ($r < 13 ) { $throw[$_] = 1; }
	else { $throw[$_] = 0; }
    }
    return @throw;
}

sub HexRelating {
    my @throw = @_;
    return map { ((($_==3)||($_==0))?(3-$_):$_) } @throw;
}

sub StalkPrintStringBasic {
    my $str;
    if (@_[0] == 0) {$str = '-----';}
    if (@_[0] == 2) {$str = '-----';}
    if (@_[0] == 1) {$str = '-- --';}
    if (@_[0] == 3) {$str = '-- --';}
    return $str;
}

sub HexGenNum {
    my ($throw, $num) = @_;
    return int ((($throw[0] + $throw[1] + $throw[2] + $throw[3]
		  + $throw[4]  + $throw[5]) / 18) * $num);
}

# reused from chaos.pl to lay out page
#  TODO make a layout library...
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

sub HexPrintString {
    my @throw = @_;
    my @rthrow = &HexRelating(@throw);
    my $dimx = 32;
    my @page;

    for (0..5) {
	unshift @page, $dimx * (5-$_) + 6, StalkPrintStringBasic($throw[$_]);
	unshift @page, $dimx * (5-$_) + 21, StalkPrintStringBasic($rthrow[$_]);
    }

    return ' original throw  relating throw ' . $brk . $brk .
	ScatterPageGenPrintString(\@page, $dimx, 6);
}

sub HexLinksString {
    my @throw = @_;
    my @rthrow = &HexRelating(@throw);
    my $tlink = $urlpre;
    my $rtlink = $urlpre;

    for ( $p = 5 ; $p >= 0 ; --$p ) {
	my $tnum = $throw[$p];
	my $rtnum = $rthrow[$p];

	if (($tnum == 0) || ($tnum == 2)) { $tlink .= '1'; }
	else { $tlink .= '0'; }
	if (($rtnum == 0) || ($rtnum == 2)) { $rtlink .= '1'; }
	else { $rtlink .= '0'; }
    }

    $tlink = a({href=>($tlink.'.html')}, 'interpret original throw');
    $rtlink = a({href=>($rtlink.'.html')}, 'interpret relating throw');

    return $tlink . br . $rtlink;
}

#########################
# INTERFACE

$debug = 1;
$nummin = 1;
$nummax = 100;
$urlpre = 'http://www.onlineclarity.co.uk/free_I_Ching_reading/hexagrams/';

$text = param('text');
$num = param('num') || 10;
$usenum = param('usenum');

srand $text if $text;

print header(),
    start_html(-title=>'I Ching'), h2('I Ching');

@throw = &HexThrowBasic;
$result = &HexPrintString(@throw);
$resultlinks = &HexLinksString(@throw);

print table({border=>3}, Tr(td(pre($result)))), br,
    $resultlinks, br, br;
if ($usenum) { print 'numeric result: ', &HexGenNum(\@throw, $num), br; }
print hr, br;

#if (param('Throw')) {
#}

print start_form, 
    submit(-name=>'Throw'), br, br,
    'If desired, enter question or consideration:', br,
    textfield(-name=>'text', -size=>30, -maxlength=>99),
    br, br, 
    checkbox(-name=>'usenum', -checked=>$usenum,
             -label=>'interpret as number up to: '), ' ',
    popup_menu(-name=>'num', values=>[$nummin..$nummax],
	       -default=>"$num"),
    end_form;

print end_html();



