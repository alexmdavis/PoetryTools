# -*- perl -*-
#
# Package to interface with WordNet (wn) command line program

# Run 'perldoc' on this file to produce documentation

# Copyright 1999 Jason Rennie <jrennie@csail.mit.edu>

# This module is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.

# $Id: QueryData.pm,v 1.37 2004/12/01 19:55:03 jrennie Exp $

####### manual page & loadIndex ##########

# STANDARDS
# =========
# - upper case to distinguish words in function & variable names
# - use 'warn' to report warning & progress messages
# - begin 'warn' messages with "(fn)" where "fn" is function name
# - all non-trivial function calls should receive $self
# - syntactic markers are ignored

package WordNet::QueryData;

use strict;
use Carp;
use FileHandle;
use Search::Dict;
use File::Spec;
use Exporter;

##############################
# Environment/Initialization #
##############################

BEGIN {
    use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
    # List of classes from which we are inheriting methods
    @ISA = qw(Exporter);
    # Automatically loads these function names to be used without qualification
    @EXPORT = qw();
    # Allows these functions to be used without qualification
    @EXPORT_OK = qw();
    $VERSION = do { my @r=(q$Revision: 1.37 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
}

#############################
# Private Package Variables #
#############################

# Mapping of possible part of speech to single letter used by wordnet
my %pos_map = ('noun'      => 'n',
	       'n'         => 'n',
	       '1'         => 'n',
	       ''          => 'n',
	       'verb'      => 'v',
	       'v'         => 'v',
	       '2'         => 'v',
	       'adjective' => 'a',
	       'adj'       => 'a',
	       'a'         => 'a',
	       # Adj satellite is essentially just an adjective
	       's'         => 'a',
	       '3'         => 'a',
	       '5'         => 'a', # adj satellite
	       'adverb'    => 'r',
	       'adv'       => 'r',
	       'r'         => 'r',
	       '4'         => 'r');
# Mapping of possible part of speech to corresponding number
my %pos_num = ('noun'      => '1',
	       'n'         => '1',
	       '1'         => '1',
	       ''          => '1',
	       'verb'      => '2',
	       'v'         => '2',
	       '2'         => '2',
	       'adjective' => '3',
	       'adj'       => '3',
	       'a'         => '3',
	       # Adj satellite is essentially just an adjective
	       's'         => '3',
	       '3'         => '3',
	       'adverb'    => '4',
	       'adv'       => '4',
	       'r'         => '4',
	       '4'         => '4');
# Mapping from WordNet symbols to short relation names
my %relNameSym = ('ants' => {'!'=>1},
		  'hype' => {'@'=>1},
		  'hypo' => {'~'=>1},
		  'mmem' => {'%m'=>1},
		  'msub' => {'%s'=>1},
		  'mprt' => {'%p'=>1},
		  'mero' => {'%m'=>1, '%s'=>1, '%p'=>1},
		  'hmem' => {'#m'=>1},
		  'hsub' => {'#s'=>1},
		  'hprt' => {'#p'=>1},
		  'holo' => {'#m'=>1, '#s'=>1, '#p'=>1},
		  'attr' => {'='=>1},
		  'enta' => {'*'=>1},
		  'caus' => {'>'=>1},
		  'also' => {'^'=>1},
		  'vgrp' => {'$'=>1},
		  'sim' => {'&'=>1},
		  'part' => {'<'=>1},
		  'pert' => {'\\'=>1},
		  'deri' => {'+'=>1},
		  'domn' => {';c'=>1, ';r'=>1, ';u'=>1},
		  'dmnc' => {';c'=>1},
		  'dmnr' => {';r'=>1},
		  'dmnu' => {';u'=>1},
		  'domt' => {'-c'=>1, '-r'=>1, '-u'=>1},
		  'dmtc' => {'-c'=>1},
		  'dmtr' => {'-r'=>1},
		  'dmtu' => {'-u'=>1});

# Mapping from WordNet symbols to short relation names
my %relSymName = ('!'  => 'ants',
		  '@'  => 'hype',
		  '~'  => 'hypo',
		  '%m' => 'mmem',
		  '%s' => 'msub',
		  '%p' => 'mprt',
		  '#m' => 'hmem',
		  '#s' => 'hsub',
		  '#p' => 'hprt',
		  '='  => 'attr',
		  '*'  => 'enta',
		  '>'  => 'caus',
		  '^'  => 'also',
		  '$' => 'vgrp', # '$' Hack to make font-lock work in emacs
		  '&'  => 'sim',
		  '<'  => 'part',
		  '\\' => 'pert',
		  '-u' => 'dmtu',
		  '-r' => 'dmtr',
		  '-c' => 'dmtc',
		  ';u' => 'dmnu',
		  ';r' => 'dmnr',
		  ';c' => 'dmnc');

# DEPRECATED!  DO NOT USE!  Use relSymName instead.
my %relation_sym = ('!'  => 'ants',
		    '@'  => 'hype',
		    '~'  => 'hypo',
		    '%m' => 'mmem',
		    '%s' => 'msub',
		    '%p' => 'mprt',
		    '#m' => 'hmem',
		    '#s' => 'hsub',
		    '#p' => 'hprt',
		    '='  => 'attr',
		    '*'  => 'enta',
		    '>'  => 'caus',
		    '^'  => 'also',
		    '$' => 'vgrp', # '$' Hack to make font-lock work in emacs
		    '&'  => 'sim',
		    '<'  => 'part',
		    '\\' => 'pert');

# WordNet data file names
my $lexnamesFile = "lexnames";
my @excFile = ("", "noun.exc", "verb.exc", "adj.exc", "adv.exc");
my @indexFileUnix = ("", "index.noun", "index.verb", "index.adj", "index.adv");
my @dataFileUnix = ("", "data.noun", "data.verb", "data.adj", "data.adv");
my @indexFilePC = ("", "noun.idx", "verb.idx", "adj.idx", "adv.idx");
my @dataFilePC = ("", "noun.dat", "verb.dat", "adj.dat", "adv.dat");

my $wnHomeUnix = defined($ENV{"WNHOME"}) ? $ENV{"WNHOME"} : "/usr/local/WordNet-2.0";
my $wnHomePC = defined($ENV{"WNHOME"}) ? $ENV{"WNHOME"} : "C:\\Programs\\WordNet\\2.0";
my $wnPrefixUnix = defined($ENV{"WNSEARCHDIR"}) ? $ENV{"WNSEARCHDIR"} : "$wnHomeUnix/dict";
my $wnPrefixPC = defined($ENV{"WNSEARCHDIR"}) ? $ENV{"WNSEARCHDIR"} : "$wnHomePC\\dict";

END { } # module clean-up code here (global destructor)

###############
# Subroutines #
###############

# report WordNet version
sub version { my $self = shift; return $self->{version}; }

# report WordNet data dir -- Sid (05/01/2003)
sub dataPath { my $self = shift; return $self->{wnpath}; }

# convert to lower case, translate ' ' to '_' and eliminate any
# syntactic marker
sub lower#
{ 
    my $word = shift;
    $word =~ tr/A-Z /a-z_/;
    $word =~ s/\(.*\)$//;
    return $word;
}

# translate ' ' to '_'
sub underscore#
{ 
    $_[0] =~ tr/ /_/;
    return $_[0];
}

# Eliminate any syntactic marker
sub delMarker#
{ 
    $_[0] =~ s/\(.*\)$//;
    return $_[0];
}

# Perform all initialization for new WordNet class instance
sub _initialize#
{
    my $self = shift;
    warn "Loading WordNet data...\n" if ($self->{verbose});
    # Ensure that input record separator is "\n"
    my $old_separator = $/;
    $/ = "\n";
    
    # Load morphology exclusion mapping
    $self->loadExclusions ();
    $self->loadLexnames();
    $self->loadIndex ();
    $self->openData ();
    warn "Done.\n" if ($self->{verbose});
    
    # Return setting of input record separator
    $/ = $old_separator;
}

sub new#
{
    # First argument is class
    my $class = shift;
    # Second is location of WordNet dictionary; Third is verbosity
    
    my $self = {};
    bless $self, $class;
    $self->{dir} = shift if (defined(@_ > 0));
    $self->{verbose} = @_ ? shift : 0;
    warn "Dir = ", $self->{dir}, "\n" if ($self->{verbose});
    warn "Verbose = ", $self->{verbose}, "\n" if ($self->{verbose});
    $self->_initialize ();
    return $self;
}

# Object destructor
sub DESTROY#
{
    my $self = shift;
    
    for (my $i=1; $i <= 4; $i++) {
	undef $self->{data_fh}->[$i];
    }
}

# Load mapping to non-standard canonical form of words (morphological
# exceptions)
sub loadExclusions#
{
    my $self = shift;
    warn "(loadExclusions)" if ($self->{verbose});

    for (my $i=1; $i <= 4; $i++)
    {
	my $fileUnix = defined($self->{dir}) ? $self->{dir}."/".$excFile[$i] : "$wnPrefixUnix/$excFile[$i]";
	my $filePC = defined($self->{dir}) ? $self->{dir}."\\".$excFile[$i] : "$wnPrefixPC\\$excFile[$i]";
	
	my $fh = new FileHandle($fileUnix);
	$fh = new FileHandle($filePC) if (!defined($fh));
	die "Not able to open $fileUnix or $filePC: $!" if (!defined($fh));
	
	while (my $line = <$fh>)
	{
	    my ($exc, @word) = split(/\s+/, $line);
	    next if (!@word);
	    if (!defined($self->{morph_exc}->[$i]->{$exc})) {
		@{$self->{morph_exc}->[$i]->{$exc}} = @word;
	    } else {
		push @{$self->{morph_exc}->[$i]->{$exc}}, @word;
	    }
	}
    }
}

# Load mapping to non-standard canonical form of words (morphological
# exceptions)
sub loadLexnames#
{
    my $self = shift;
    warn "(loadLexnames)" if ($self->{verbose});

    my $fileUnix = defined($self->{dir}) ? $self->{dir}."/".$lexnamesFile : "$wnPrefixUnix/$lexnamesFile";
    my $filePC = defined($self->{dir}) ? $self->{dir}."\\".$lexnamesFile : "$wnPrefixPC\\$lexnamesFile";
	
    my $fh = new FileHandle($fileUnix);
    $fh = new FileHandle($filePC) if (!defined($fh));
    die "Not able to open $fileUnix or $filePC: $!" if (!defined($fh));
    
    while (my $line = <$fh>)
    {
	my ($num, $name, $pos) = split(/\s+/, $line);
	next if (!$num);
	$self->{lexMap}->{$num} = $name;
    }
    undef $fh
}

sub loadIndex#
{
    my $self = shift;
    warn "(loadIndex)" if ($self->{verbose});

    for (my $i=1; $i <= 4; $i++)
    {
	my $fileUnix = defined($self->{dir}) ? $self->{dir}."/".$indexFileUnix[$i] : "$wnPrefixUnix/$indexFileUnix[$i]";
	my $filePC = defined($self->{dir}) ? $self->{dir}."\\".$indexFilePC[$i] : "$wnPrefixPC\\$indexFilePC[$i]";
	
	my $fh = new FileHandle($fileUnix);
	
	# Added Code -- WordNet data path being used -- Sid (05/01/2003)
	if (defined $fh) { $self->{wnpath} = defined($self->{dir}) ? $self->{dir} : $wnPrefixUnix; }
	else { $self->{wnpath} = defined($self->{dir}) ? $self->{dir} : $wnPrefixPC; }
	
	$fh = new FileHandle($filePC) if (!defined($fh));
	die "Not able to open $fileUnix or $filePC: $!" if (!defined($fh));
	
	my $line;
	while ($line = <$fh>) {
	    $self->{version} = $1 if ($line =~ m/WordNet (\S+)/);
	    last if ($line =~ m/^\S/);
	}
	while (1) {
	    my ($lemma, $pos, $sense_cnt, $p_cnt);
	    ($lemma, $pos, $sense_cnt, $p_cnt, $line) = split(/\s+/, $line, 5);
	    for (my $i=0; $i < $p_cnt; ++$i) {
		(undef, $line) = split(/\s+/, $line, 2);
	    }
	    my (undef, $tagsense_cnt, @offset) = split(/\s+/, $line);
	    $self->{"index"}->[$pos_num{$pos}]->{$lemma} = pack "i*", @offset;
	    $self->{"tagsense_cnt"}->[$pos_num{$pos}]->{$lemma} = $tagsense_cnt;
	    $line = <$fh>;
	    last if (!$line);
	}
    }
    warn "\n*** Version 1.6 of the WordNet database is no longer being supported as\n*** of QueryData 1.27.  It may still work, but consider yourself warned.\n" if ($self->{version} eq "1.6");
    warn "\n*** Version 1.7 of the WordNet database is no longer being supported as\n*** of QueryData 1.27.  It may still work, but consider yourself warned.\n" if ($self->{version} eq "1.7");
}

# Open data files and return file handles
sub openData#
{
    my $self = shift;
    warn "(openData)" if ($self->{verbose});

    for (my $i=1; $i <= 4; $i++)
    {
	my $fileUnix = defined($self->{dir}) ? $self->{dir}."/".$dataFileUnix[$i] : "$wnPrefixUnix/$dataFileUnix[$i]";
	my $filePC = defined($self->{dir}) ? $self->{dir}."\\".$dataFilePC[$i] : "$wnPrefixPC\\$dataFilePC[$i]";
	
	my $fh = new FileHandle($fileUnix);
	$fh = new FileHandle($filePC) if (!defined($fh));
	die "Not able to open $fileUnix or $filePC: $!" if (!defined($fh));
	$self->{data_fh}->[$i] = $fh;
    }
}

# DEPRECATED!  DO NOT USE!  Use removeDuplicates instead.
sub remove_duplicates
{
    my ($self, $aref) = @_;
    $self->removeDuplicates($aref);
}

# Remove duplicate values from an array, which must be passed as a
# reference to an array.
sub removeDuplicates
{
    my ($self, $aref) = @_;
    warn "(removeDupliates) array=", join(" ", @{$aref}), "\n"
	if ($self->{verbose});
    
    my $i = 0;
    while ( $i < $#$aref ) {
        if ( grep {$_ eq ${$aref}[$i]} @{$aref}[$i+1 .. $#$aref] ) {
	    # element at $i is duplicate--remove it
	    splice @$aref, $i, 1;
	} else {
            $i++;
        }
    }
}

# - transforms ending according to rules of detachment
#   (http://www.cogsci.princeton.edu/~wn/doc/man1.7.1/morphy.htm).
# - assumes a single token (no collocations).
# - "#pos#sense" qualification NOT appended to returned words
# - always returns original word
sub tokenDetach#
{
    my ($self, $string) = @_;
    # The query string (word, pos and sense #)
    my ($word, $pos, $sense) = $string =~ /^([^\#]+)(?:\#([^\#]+)(?:\#(\d+))?)?$/; 
    warn "(forms) Sense number ignored\n" if (defined($sense));
    die "(tokenDetach) bad part-of-speech: pos=$pos word=$word sense=$sense" if (!defined($pos) or !defined($pos_num{$pos}));
    my @detach = ($word); # list of possible forms
    if ($pos_num{$pos} == 1)
    {
	push @detach, $1 if ($word =~ m/^(\w+)s$/);
	push @detach, $1 if ($word =~ m/^(\w+s)es$/);
	push @detach, $1 if ($word =~ m/^(\w+x)es$/);
	push @detach, $1 if ($word =~ m/^(\w+z)es$/);
	push @detach, $1 if ($word =~ m/^(\w+ch)es$/);
	push @detach, $1 if ($word =~ m/^(\w+sh)es$/);
	push @detach, $1."man" if ($word =~ m/^(\w+)men$/);
	push @detach, $1."y" if ($word =~ m/^(\w+)ies$/);
    }
    elsif ($pos_num{$pos} == 2)
    {
	push @detach, $1 if ($word =~ m/^(\w+)s$/);
	push @detach, $1."y" if ($word =~ m/^(\w+)ies$/);
	push @detach, $1 if ($word =~ m/^(\w+e)s$/);
	push @detach, $1 if ($word =~ m/^(\w+)es$/);
	push @detach, $1 if ($word =~ m/^(\w+e)d$/);
	push @detach, $1 if ($word =~ m/^(\w+)ed$/);
	push @detach, $1."e" if ($word =~ m/^(\w+)ing$/);
	push @detach, $1 if ($word =~ m/^(\w+)ing$/);
    }
    elsif ($pos_num{$pos} == 3)
    {
	push @detach, $1 if ($word =~ m/^(\w+)er$/);
	push @detach, $1 if ($word =~ m/^(\w+)est$/);
	push @detach, $1 if ($word =~ m/^(\w+e)r$/);
	push @detach, $1 if ($word =~ m/^(\w+e)st$/);
    }
    $self->removeDuplicates(\@detach);
    return @detach;
}

# sub-function of forms; do not use unless you know what you're doing
sub _forms#
{
    # Assume that word is canonicalized, pos is number
    my ($self, $word, $pos) = @_;

    my $lword = lower($word);
    warn "(_forms) WORD=$word POS=$pos\n" if ($self->{verbose});
    # if word is in morph exclusion table, return that entry
    return ($word, @{$self->{morph_exc}->[$pos]->{$lword}}) if (defined ($self->{morph_exc}->[$pos]->{$lword}));	

    my @token = split (/[ _]/, $word);
    # If there is only one token, process via rules of detachment
    return tokenDetach ($self, $token[0]."#".$pos) if (@token == 1);
    # Otherwise, process each token individually, then string together colloc's
    my @forms;
    for (my $i=0; $i < @token; $i++) {
	push @{$forms[$i]}, _forms ($self, $token[$i], $pos);
    }
    # Generate all possible token sequences (collocations)
    my @rtn;
    my @index;
    for (my $i=0; $i < @token; $i++) { $index[$i] = 0; }
    while (1) {
	# String together one sequence of possibilities
	my $colloc = $forms[0]->[$index[0]];
	for (my $i=1; $i < @token; $i++) {
	    $colloc .= "_".$forms[$i]->[$index[$i]];
	}
	push @rtn, $colloc;
	# think "adder" (computer architechture)
	my $i;
	for ($i=0; $i < @token; $i++) {
	    last if (++$index[$i] < @{$forms[$i]});
	    $index[$i] = 0;
	}
	# If we had to reset every index, we're done
	last if ($i >= @token);
    }
    return @rtn;
}

# Generate list of all possible forms of how word may be found in WordNet
sub forms#
{
    my ($self, $string) = @_;
    # The query string (word, pos and sense #)
    my ($word, $pos, $sense) = $string =~ /^([^\#]+)(?:\#([^\#]+)(?:\#(\d+))?)?$/; 
    warn "(forms) Sense number ignored\n" if (defined($sense));
    warn "(forms) WORD=$word POS=$pos\n" if ($self->{verbose});
    die "(forms) Bad part-of-speech: pos=$pos" if (!defined($pos) or !defined($pos_num{$pos}));
    my @rtn = _forms ($self, $word, $pos_num{$pos});
    for (my $i=0; $i < @rtn; ++$i) {
	$rtn[$i] .= "\#$pos";
    }
    return @rtn;
}


# DEPRECATED!  DO NOT USE!  Use "getSensePointers" instead.
sub get_pointers
{
    my ($line, $pointer, $index_offset) = @_;
    my $i;
    
    # $w_cnt is hexadecimal
    my ($offset, $lex_file, $ss_type, $w_cnt, @stuff) = split (/\s+/, $line);
    $w_cnt = hex ($w_cnt);
    print STDERR "Offsets differ INDEX=$index_offset DATA=$offset\n"
	if ($index_offset != $offset);
    # Strip words
    my (@word_info) = splice @stuff, 0, $w_cnt*2;
    # Get pointers
    my ($p_cnt) = splice (@stuff, 0, 1);
    my (@pointer_info) = splice (@stuff, 0, $p_cnt*4);
    for ($i=0; $i < $p_cnt; $i++)
    {
	# $st "source/target" is 2-part hexadecimal
	my ($type, $offset, $pos, $st) = splice (@pointer_info, 0, 4);
	push @{$pointer->{$relation_sym{$type}}}, "$offset\#$pos";
    }
    my $key;
}

# $line is line from data file; $ptr is a reference to a hash of
# symbols; returns list of word#pos#sense strings
sub getSensePointers#
{
    my ($self, $line, $ptr) = @_;
    warn "(getSensePointers) ptr=", keys(%{$ptr}), " line=\"$line\"\n"
	if ($self->{verbose});
    
    my (@rtn, $w_cnt);
    # $w_cnt is hexadecimal
    (undef, undef, undef, $w_cnt, $line) = split (/\s+/, $line, 5);
    $w_cnt = hex ($w_cnt);
    for (my $i=0; $i < $w_cnt; ++$i) {
	(undef, undef, $line) = split(/\s+/, $line, 3);
    }
    my $p_cnt;
    ($p_cnt, $line) = split(/\s+/, $line, 2);
    for (my $i=0; $i < $p_cnt; ++$i) {
	my ($sym, $offset, $pos, $st);
	# $st "source/target" is 2-part hexadecimal
	($sym, $offset, $pos, $st, $line) = split(/\s+/, $line, 5);
	push @rtn, $self->getSense($offset, $pos)
	    if (hex($st)==0 and defined($ptr->{$sym}));
    }
    return @rtn;
}

# $line is line from data file; $ptr is a reference to a hash of
# symbols; $word is query word/lemma; returns list of word#pos#sense strings
sub getWordPointers#
{
    my ($self, $line, $ptr, $word) = @_;
    warn "(getWordPointers) ptr=", keys(%{$ptr}), " word=$word line=\"$line\"\n"
	if ($self->{verbose});
    
    my $lword = lower($word);
    my (@rtn, $w_cnt);
    (undef, undef, undef, $w_cnt, $line) = split (/\s+/, $line, 5);
    $w_cnt = hex ($w_cnt);
    my @word;
    for (my $i=0; $i < $w_cnt; ++$i) {
	($word[$i], undef, $line) = split(/\s+/, $line, 3);
    }
    my $p_cnt;
    ($p_cnt, $line) = split(/\s+/, $line, 2);
    for (my $i=0; $i < $p_cnt; ++$i) {
	my ($sym, $offset, $pos, $st);
	# $st "source/target" is 2-part hexadecimal
	($sym, $offset, $pos, $st, $line) = split(/\s+/, $line, 5);
	next if (!$st);
	my ($src, $tgt) = ($st =~ m/([0-9a-f]{2})([0-9a-f]{2})/);
	push @rtn, $self->getWord($offset, $pos, hex($tgt))
	    if (defined($ptr->{$sym}) and ($word[$src-1] =~ m/$lword/i));
    }
    return @rtn;
}

# DEPRECATED!  DO NOT USE!  Use "getAllSenses" instead.
sub get_all_words
{
    my ($self, $index_offset, $pos) = @_;
    my ($i, @rtn);
    
    my $fh = $self->{data_fh}->[$pos_num{$pos}];
    seek $fh, $index_offset, 0;
    $_ = <$fh>;
    my ($offset, $w_cnt, @stuff);
    ($offset, undef, undef, $w_cnt, @stuff) = split (/\s+/);
    # $w_cnt is in hex, not decimal
    $w_cnt = hex ($w_cnt);
    print STDERR "Offsets differ INDEX=$index_offset DATA=$offset\n"
	if ($index_offset != $offset);
    # Grab words
    my (@words) = splice @stuff, 0, $w_cnt*2;
    # Get rid of lex file number junk
    for ($i=1; $i <= $w_cnt; $i++) { splice @words, $i, 1; }
    foreach my $word (@words)
    {
	$word = lower ($word);
	# Eliminate syntactic marker (if any)
        $word =~ s/\(.*\)$//; 
	my @offset_array = (unpack "i*", $self->{"index"}->[$pos_num{$pos}]->{$word});
	for ($i=0; $i < @offset_array; $i++)
	{
	    push @rtn, "$word\#$pos\#".($i+1) if ($offset_array[$i] == $index_offset);
	    last if ($offset_array[$i] == $index_offset);
	}
    }
    return @rtn;
}

# DEPRECATED!  DO NOT USE!  Use "getSense" instead.
sub get_word
{
    my ($self, $index_offset, $pos) = @_;
    
    warn "(get_word) offset=$index_offset pos=$pos\n" if ($self->{verbose});
    my $fh = $self->{data_fh}->[$pos_num{$pos}];
    seek $fh, $index_offset, 0;
    $_ = <$fh>;
    my ($offset, $word);
    ($offset, undef, undef, undef, $word) = split (/\s+/);
    $word = lower ($word);
    print STDERR "Offsets differ INDEX=$index_offset DATA=$offset\n"
	if ($index_offset != $offset);
    my @offset_array = (unpack "i*", $self->{"index"}->[$pos_num{$pos}]->{$word});
    for (my $i=0; $i < @offset_array; $i++)
    {
	return "$word\#$pos\#".($i+1) if ($offset_array[$i] == $index_offset);
    }
}

# return list of word#pos#sense for $offset and $pos (synset)
sub getAllSenses#
{
    my ($self, $offset, $pos) = @_;
    warn "(getAllSenses) offset=$offset pos=$pos\n" if ($self->{verbose});

    my @rtn;
    my $fh = $self->{data_fh}->[$pos_num{$pos}];
    seek $fh, $offset, 0;
    my $line = <$fh>;
    my $w_cnt;
    (undef, undef, undef, $w_cnt, $line) = split(/\s+/, $line, 5);
    $w_cnt = hex ($w_cnt);
    my @words;
    for (my $i=0; $i < $w_cnt; ++$i) {
	($words[$i], undef, $line) = split(/\s+/, $line, 3);
    }
    foreach my $word (@words) {
	$word = delMarker($word);
	my $lword = lower ($word);
	my @offArr = (unpack "i*", $self->{"index"}->[$pos_num{$pos}]->{$lword});
	for (my $i=0; $i < @offArr; $i++) {
	    if ($offArr[$i] == $offset) {
		push @rtn, "$word\#$pos\#".($i+1);
		last;
	    }
	}
    }
    return @rtn;
}

# returns word#pos#sense for given offset and pos
sub getSense#
{
    my ($self, $offset, $pos) = @_;
    warn "(getSense) offset=$offset pos=$pos\n" if ($self->{verbose});
    
    my $fh = $self->{data_fh}->[$pos_num{$pos}];
    seek $fh, $offset, 0;
    my $line = <$fh>;
    my ($lexfn,$word);
    (undef, $lexfn, undef, undef, $word, $line) = split (/\s+/, $line, 6);
    $word = delMarker($word);
    my $lword = lower($word);
    my @offArr = (unpack "i*", $self->{"index"}->[$pos_num{$pos}]->{$lword});
    for (my $i=0; $i < @offArr; $i++) {
	return "$word\#$pos\#".($i+1) if ($offArr[$i] == $offset);
    }
    die "(getSense) Internal error: offset=$offset pos=$pos";
}

# returns word#pos#sense for given offset, pos and number
sub getWord#
{
    my ($self, $offset, $pos, $num) = @_;
    warn "(getWord) offset=$offset pos=$pos num=$num" if ($self->{verbose});
    
    my $fh = $self->{data_fh}->[$pos_num{$pos}];
    seek $fh, $offset, 0;
    my $line = <$fh>;
    my $w_cnt;
    (undef, undef, undef, $w_cnt, $line) = split (/\s+/, $line, 5);
    $w_cnt = hex ($w_cnt);
    my $word;
    for (my $i=0; $i < $w_cnt; ++$i) {
	($word, undef, $line) = split(/\s+/, $line, 3);
	$word = delMarker($word);
	# (mich0212) return "$word\#$pos" if ($i+1 == $num);
	last if ($i+1 == $num);
    }
    my $lword = lower($word);
    my @offArr = (unpack "i*", $self->{"index"}->[$pos_num{$pos}]->{$lword});
    for (my $i=0; $i < @offArr; $i++) {
	return "$word\#$pos\#".($i+1) if ($offArr[$i] == $offset);
    }
    die "(getWord) Bad number: offset=$offset pos=$pos num=$num";
}


# Return the WordNet data file offset for a fully qualified word sense
sub offset#
{
    my ($self, $string) = @_;

    my ($word, $pos, $sense) = $string =~ /^([^\#]+)(?:\#([^\#]+)(?:\#(\d+))?)?$/; 
    warn "(offset) WORD=$word POS=$pos SENSE=$sense\n" if ($self->{verbose});
    die "(offset) Bad query string: $string"
	if (!defined($sense) or !defined($pos)
	    or !defined($word) or !defined($pos_num{$pos}));
    my $lword = lower ($word);
    return (unpack "i*", $self->{"index"}->[$pos_num{$pos}]->{$lword})[$sense-1];
}

# Return the lexname for the type (3) query string
sub lexname#
{
    my ($self, $string) = @_;

    my $offset = $self->offset($string);
    my ($word, $pos, $sense) = $string =~ /^([^\#]+)(?:\#([^\#]+)(?:\#(\d+))?)?$/; 
    warn "(lexname) word=$word pos=$pos sense=$sense offset=$offset\n" if ($self->{verbose});
    my $fh = $self->{data_fh}->[$pos_num{$pos}];
    seek $fh, $offset, 0;
    my $line = <$fh>;
    my (undef, $lexfn, undef) = split (/\s+/, $line, 3);
    return $self->{lexMap}->{$lexfn};
}

# Return the frequency count for the type (3) query string
# Added by mich0212 (12/1/04)
sub frequency
{
    my ($self, $string) = @_;
    my ($word, $pos, $sense) = $string =~ /^([^\#]+)\#([^\#]+)\#([^\#]+)$/;

    unless (defined $word and defined $pos and defined $sense) {
	croak "(frequency) Query string is not a valid type (3) string";
    }

    warn "(frequency) word=$word pos=$pos sense=$sense\n" if $self->{verbose};

    my $dp = $self->dataPath;
    my $cntfile = File::Spec->catfile ($dp, 'cntlist.rev');
    open CFH, "<$cntfile" or die "Cannot open $cntfile: $!";
    
    # look() seek()s to the right position in the file
    my $position = Search::Dict::look (*CFH, "$word\%", 0, 0);
    while (<CFH>) {
	if (/^$word\%(\d+):[^ ]+ (\d+) (\d+)/) {
	    next unless $pos_map{$1} eq $pos;
	    next unless $2 eq $sense;
	    close CFH;
	    return $3;
	}
	else {
	    last;
	}
    }
    close CFH;
    return 0;
}

# DEPRECATED!  DO NOT USE!  Use "querySense" instead.
sub query
{
    my $self = shift;
    # The query string (word, pos and sense #)
    my $string = shift;
    # The relation about which to return information
    # Only required for fully-qualified query (word, pos and sense #)
    my $relation = shift;
    my $i;
    
    # Ensure that input record separator is "\n"
    my $old_separator = $/;
    $/ = "\n";
    
    # get word, pos, and sense from second argument:
    my ($word, $pos, $sense) = $string =~ /^([^\#]+)(?:\#([^\#]+)(?:\#(\d+))?)?$/; 
    
    $word = lower ($word) if ($word);
    warn "(query) Illegal Part-of-speech: POS=$pos WORD=$word\n" 
	if ($pos && !$pos_num{$pos});
    
    if ($sense)
    {
	print STDERR "(query) WORD=$word POS=$pos SENSE=$sense RELATION=$relation\n" if ($self->{verbose});
	
	if (!$relation)
	{
	    warn "Second argument is not a valid relation: $relation\n";
	    return ();
	}
	# Map to abbreviation if relation name is in long or symbol form
	$relation = $relSymName{$relation} if ($relSymName{$relation});
	
	my $fh = $self->{data_fh}->[$pos_num{$pos}];
	# Each entry should be an array reference.  Each element in the
	# array should be a pos-qualified offset (OFFSET#POS)
	my %pointer;
	# Sense number can be obtained from offset pointer ordering in index.*
	
	# Data file pointer
	my $index_offset =
	    (unpack "i*", $self->{"index"}->[$pos_num{$pos}]->{$word})[$sense-1];
	seek $fh, $index_offset, 0;
	# Get line corresponding to sense
	$_ = <$fh>;
	
	if ($relation eq "glos")
	{
	    m/.*\|\s*(.*)$/;
	    return $1;
	}
	
	# Add synset relation
	push @{$pointer{syns}}, "$index_offset\#$pos";
	get_pointers ($_, \%pointer, $index_offset);
	
	# Create list of meronyms
	push @{$pointer{mero}}, @{$pointer{mmem}} if ($pointer{mmem});
	push @{$pointer{mero}}, @{$pointer{msub}} if ($pointer{msub});
	push @{$pointer{mero}}, @{$pointer{mprt}} if ($pointer{mprt});
	# Create list of holonyms
	push @{$pointer{holo}}, @{$pointer{hmem}} if ($pointer{hmem});
	push @{$pointer{holo}}, @{$pointer{hsub}} if ($pointer{hsub});
	push @{$pointer{holo}}, @{$pointer{hprt}} if ($pointer{hprt});
	
	# If the relation is invalid, exit prematurely
	if (!$pointer{$relation})
	{
	    warn "No such relation ($relation) for word \'$word\'\n"
		if ($self->{verbose});
	    return ();    
	}
	
	# For syns, we must return all word/pos/sense tuples for this
	# synset (not just the representative one)
	return $self->get_all_words ($index_offset, $pos)
	    if ($relation eq "syns");
	
	my @rtn;
	foreach my $syn (@{$pointer{$relation}})
	{
	    my ($offset, $pos) = $syn =~ /^(\d+)\#([^\#]+)$/;
	    push @rtn, $self->get_word ($offset, $pos);
	}
	return @rtn;
    }
    elsif ($pos)
    {
	print STDERR "(query) WORD=$word POS=$pos\n" if ($self->{verbose});
	
	my (@rtn, $i);
	my @pointers = unpack "i*", $self->{"index"}->[$pos_num{$pos}]->{$word}
	if defined $self->{"index"}->[$pos_num{$pos}]->{$word};
	my $sense_cnt = scalar @pointers;
	for ($i=0; $i < @pointers; $i++) {
	    push @rtn, "$string\#".($i+1);
	}
	return @rtn;
    }
    elsif ($word)
    {
	print STDERR "(query) WORD=$word\n" if ($self->{verbose});
	my ($i, @rtn);
	for ($i=1; $i <= 4; $i++)
	{
	    push @rtn, "$word\#".$pos_map{$i}
	    if ($self->{"index"}->[$i]->{$word});
	}
	return @rtn;
    }
    else
    {
	warn "Illegal query string: $string\n";
    }
    # Return setting of input record separator
    $/ = $old_separator;
}

sub querySense#
{
    my $self = shift;
    my $string = shift;
    
    # Ensure that input record separator is "\n"
    my $old_separator = $/;
    $/ = "\n";
    my @rtn;
    
    # get word, pos, and sense from second argument:
    my ($word, $pos, $sense) = $string =~ /^([^\#]+)(?:\#([^\#]+)(?:\#(\d+))?)?$/; 
    die "(querySense) Bad query string: $string" if (!defined($word));
    my $lword = lower ($word);
    die "(querySense) Bad part-of-speech: $string"
	if (defined($pos) && !$pos_num{$pos});
    
    if (defined($sense)) {
	my $rel = shift;
	warn "(querySense) WORD=$word POS=$pos SENSE=$sense RELATION=$rel\n" if ($self->{verbose});
	die "(querySense) Relation required: $string" if (!defined($rel));
	die "(querySense) Bad relation: $rel" 
	    if (!defined($relNameSym{$rel}) and !defined($relSymName{$rel})
		 and ($rel ne "glos") and ($rel ne "syns"));
	$rel = $relSymName{$rel} if (defined($relSymName{$rel}));
	
	my $fh = $self->{data_fh}->[$pos_num{$pos}];
	my $offset = (unpack "i*", $self->{"index"}->[$pos_num{$pos}]->{$lword})[$sense-1];
	seek $fh, $offset, 0;
	my $line = <$fh>;
	
	if ($rel eq "glos") {
	    $line =~ m/.*\|\s*(.*)$/;
	    $rtn[0] = $1;
	} elsif ($rel eq "syns") {
	    @rtn = $self->getAllSenses ($offset, $pos);
	} else {
	    @rtn = $self->getSensePointers($line, $relNameSym{$rel});
	}
    } elsif (defined($pos)) {
	warn "(querySense) WORD=$word POS=$pos\n" if ($self->{verbose});
	if (defined($self->{"index"}->[$pos_num{$pos}]->{$lword})) {
	    my @offset = unpack "i*", $self->{"index"}->[$pos_num{$pos}]->{$lword};
	    $word = underscore(delMarker($word));
	    for (my $i=0; $i < @offset; $i++) {
		push @rtn, "$word\#$pos\#".($i+1);
	    }
	}
    } elsif (defined($word)) {
	print STDERR "(querySense) WORD=$word\n" if ($self->{verbose});
	$word = underscore(delMarker($word));
	for (my $i=1; $i <= 4; $i++) {
	    push @rtn, "$word\#".$pos_map{$i}
	    if ($self->{"index"}->[$i]->{$lword});
	}
    }
    # Return setting of input record separator
    $/ = $old_separator;
    return @rtn;
}

sub queryWord#
{
    my $self = shift;
    my $string = shift;

    # (mich0212) warn "queryWord: WARNING: certain aspects of this function are broken.  It needs\n a rewrite.  Use at your own risk.\n";
    
    # Ensure that input record separator is "\n"
    my $old_separator = $/;
    $/ = "\n";
    my @rtn;
    
    # get word, pos, and sense from second argument:
    my ($word, $pos, $sense) = $string =~ /^([^\#]+)(?:\#([^\#]+)(?:\#(\d+))?)?$/; 
    die "(queryWord) Bad query string: $string" if (!defined($word));
    my $lword = lower ($word);
    die "(queryWord) Bad part-of-speech: $string"
	if (defined($pos) && !$pos_num{$pos});
    
    if (defined($sense)) {
	my $rel = shift;
	warn "(queryWord) WORD=$word POS=$pos SENSE=$sense RELATION=$rel\n" 
	    if ($self->{verbose});
	die "(queryWord) Relation required: $string" if (!defined($rel));
	die "(queryWord) Bad relation: $rel"
	    if ((!defined($relNameSym{$rel}) and !defined($relSymName{$rel})));
	$rel = $relSymName{$rel} if (defined($relSymName{$rel}));
	
	my $fh = $self->{data_fh}->[$pos_num{$pos}];
	my $offset = (unpack "i*", 
		      $self->{"index"}->[$pos_num{$pos}]->{$lword})[$sense-1];
	seek $fh, $offset, 0;
	my $line = <$fh>;
	push @rtn, $self->getWordPointers($line, $relNameSym{$rel}, $word);
    } elsif (defined($pos)) {
	warn "(queryWord) WORD=$word POS=$pos\n" if ($self->{verbose});
	if (defined($self->{"index"}->[$pos_num{$pos}]->{$lword})) {
	    my @offset = unpack "i*", 
	    $self->{"index"}->[$pos_num{$pos}]->{$lword};
	    $word = underscore(delMarker($word));
	    for (my $i=0; $i < @offset; $i++) {
		push @rtn, "$word\#$pos\#".($i+1);
	    }
	}
    } else {
	print STDERR "(queryWord) WORD=$word\n" if ($self->{verbose});
	
	$word = underscore(delMarker($word));
	for (my $i=1; $i <= 4; $i++) {
	    push @rtn, "$word\#".$pos_map{$i}
	    if ($self->{"index"}->[$i]->{$lword});
	}
    }
    # Return setting of input record separator
    $/ = $old_separator;
    return @rtn;
}

# DEPRECATED!  DO NOT USE!  Use validForms instead.
sub valid_forms
{
    my ($self, $string) = @_;
    return $self->validForms($string);
}

# return list of entries in wordnet database (in word#pos form)
sub validForms#
{
    my ($self, $string) = @_;
    my (@possible_forms, @valid_forms);
    
    # get word, pos, and sense from second argument:
    my ($word, $pos, $sense) = $string =~ /^([^\#]+)(?:\#([^\#]+)(?:\#(\d+))?)?$/; 
    warn "(valid_forms) Sense number ignored: $string\n" if (defined $sense);
    if (!defined($pos)) {
	my @rtn;
	push @rtn, $self->validForms($string."#n");
	push @rtn, $self->validForms($string."#v");
	push @rtn, $self->validForms($string."#a");
	push @rtn, $self->validForms($string."#r");
	return @rtn;
    }
    
    die "(valid_forms) Invalid part-of-speech: $pos" if (!defined($pos_map{$pos}));
    @possible_forms = $self->forms ("$word#$pos");
    @valid_forms = grep $self->querySense ($_), @possible_forms;
    
    return @valid_forms;
}

# DEPRECATED!  DO NOT USE!  Use listAllWords instead.
sub list_all_words
{
    my ($self, $pos) = @_;
    return $self->listAllWords($pos);
}

# List all words in WordNet database of a particular part of speech
sub listAllWords#
{
    my ($self, $pos) = @_;
    return keys(%{$self->{"index"}->[$pos_num{$pos}]});
}

# Return length of (some) path to root, plus one (root is considered
# to be level 1); $word must be word#pos#sense form
sub level#
{
    my ($self, $word) = @_;
    my $level;
    
    for ($level=0; $word; ++$level)
    {
	($word) = $self->querySense ($word, "hype");
    }
    return $level;
}

sub tagSenseCnt
{
    my ($self, $string) = @_;
    # get word, pos, and sense from second argument:
    my ($word, $pos, $sense) = $string =~ /^([^\#]+)(?:\#([^\#]+)(?:\#(\d+))?)?$/; 
    warn "(tagSenseCnt) Ignorning sense: $string" if (defined($sense));
    die "Word and part-of-speech required word=$word pos=$pos"
	if (!defined($word) or !defined($pos) or !defined($pos_num{$pos}));
    my $lword = lower($word);
    return $self->{"tagsense_cnt"}->[$pos_num{$pos}]->{$lword};
}

# module must return true
1;
__END__

#################
# Documentation #
#################

=head1 NAME

WordNet::QueryData - direct perl interface to WordNet database

=head1 SYNOPSIS

  use WordNet::QueryData;

  my $wn = WordNet::QueryData->new;

  print "Synset: ", join(", ", $wn->querySense("cat#n#7", "syns")), "\n";
  print "Hyponyms: ", join(", ", $wn->querySense("cat#n#1", "hypo")), "\n";
  print "Parts of Speech: ", join(", ", $wn->querySense("run")), "\n";
  print "Senses: ", join(", ", $wn->querySense("run#v")), "\n";
  print "Forms: ", join(", ", $wn->validForms("lay down#v")), "\n";
  print "Noun count: ", scalar($wn->listAllWords("noun")), "\n";
  print "Antonyms: ", join(", ", $wn->queryWord("dark#n#1", "ants")), "\n";

=head1 DESCRIPTION

WordNet::QueryData provides a direct interface to the WordNet database
files.  It requires the WordNet package
(http://www.cogsci.princeton.edu/~wn/).  It allows the user direct
access to the full WordNet semantic lexicon.  All parts of speech are
supported and access is generally very efficient because the index and
morphical exclusion tables are loaded at initialization.  This
initialization step is slow (appx. 10-15 seconds), but queries are
very fast thereafter---thousands of queries can be completed every
second.

=head1 USAGE

=head2 LOCATING THE WORDNET DATABASE

To use QueryData, you must tell it where your WordNet database is.
There are two ways you can do this: 1) by setting the appropriate
environment variables, or 2) by passing the location to QueryData when
you invoke the "new" function.

QueryData knows about two environment variables, WNHOME and
WNSEARCHDIR.  If WNSEARCHDIR is set, QueryData looks for WordNet data
files there.  Otherwise, QueryData looks for WordNet data files in
WNHOME/dict (WNHOME\dict on a PC).  If WNHOME is not set, it defaults
to "/usr/local/WordNet-2.0" on Unix and "C:\Program Files\WordNet\2.0"
on a PC.  Normally, all you have to do is to set the WNHOME variable
to the location where you unpacked your WordNet distribution.  The
database files are normally unpacked to the "dict" subdirectory.

You can also pass the location of the database files directly to
QueryData.  To do this, pass the location to "new":

  my $wn = new WordNet::QueryData->new("/usr/local/wordnet/dict")

When calling "new" in this fashion, you can give it a second verbosity
argument; a true value will have QueryData print debugging
information.

=head2 QUERYING THE DATABASE

There are two primary query functions, 'querySense' and 'queryWord'.
querySense accesses semantic (sense to sense) relations; queryWord
accesses lexical (word to word) relations.  The majority of relations
are semantic.  Some relations, including "also see", antonym,
pertainym, "participle of verb", and derived forms are lexical.
See the following WordNet documentation for additional information:

  http://wordnet.princeton.edu/man/wninput.5WN#sect3

Both functions take as their first argument a query string that takes
one of three types:

  (1) word (e.g. "dog")
  (2) word#pos (e.g. "house#n")
  (3) word#pos#sense (e.g. "ghostly#a#1")

Types (1) or (2) passed to querySense or queryWord will return a list
of possible query strings at the next level of specificity.  When type
(3) is passed to querySense or queryWord, it requires a second
argument, a relation.  Relations generally only work with one function
or the other, though some relations can be either semantic or lexical;
hence they may work for both functions.  Below is a list of known
relations, grouped according to the function they're most likely to
work with:

  queryWord
  ---------
  also - also see
  ants - antonyms
  deri - derived forms (nouns and verbs only)
  part - participle of verb (adjectives only)
  pert - pertainym (pertains to noun) (adjectives only)
  vgrp - verb group (verbs only)

  querySense
  ----------
  also - also see
  glos - word definition
  syns - synset words
  hype - hypernyms
  hypo - hyponyms
  mmem - member meronyms
  msub - substance meronyms
  mprt - part meronyms
  mero - all meronyms
  hmem - member holonyms
  hsub - substance holonyms
  hprt - part holonyms
  holo - all holonyms
  attr - attributes (?)
  sim  - similar to (adjectives only)
  enta - entailment (verbs only)
  caus - cause (verbs only)
  domn - domain - all
  dmnc - domain - category
  dmnu - domain - usage
  dmnr - domain - region
  domt - member of domain - all (nouns only)
  dmtc - member of domain - category (nouns only)
  dmtu - member of domain - usage (nouns only)
  dmtr - member of domain - region (nouns only)

When called in this manner, querySense and queryWord will return a
list of related words/senses.

Note that querySense and queryWord use type (3) query strings in
different ways.  A type (3) string passed to querySense specifies a
synset.  A type (3) string passed to queryWord specifies a specific
sense of a specific word.

=head2 OTHER FUNCTIONS

"validForms" accepts a type (1) or (2) query string.  It returns a list of
all alternate forms (alternate spellings, conjugations,
plural/singular forms, etc.) that WordNet recognizes.  The type (1) query
returns alternates for all parts of speech (noun, verb, adjective,
adverb).

"listAllWords" accepts a part of speech and returns the full list of
words in the WordNet database for that part of speech.

"level" accepts a type (3) query string and returns a distance (not
necessarily the shortest or longest) to the root in the hypernym
directed acyclic graph.

"offset" accepts a type (3) query string and returns the binary offset of
that sense's location in the corresponding data file.

"tagSenseCnt" accepts a type (2) query string and returns the tagsense_cnt
value for that lemma: "number of senses of lemma that are ranked
according to their frequency of occurrence in semantic concordance
texts."

"lexname" accepts a type (3) query string and returns the lexname of
the sense; see WordNet lexnames man page for more information.

"frequency" accepts a type (3) query string and returns the frequency
count of the sense from tagged text; see WordNet cntlist man page
for more information.

See test.pl for additional example usage.

=head1 NOTES

Requires access to WordNet database files (data.noun/noun.dat,
index.noun/noun.idx, etc.)

=head1 COPYRIGHT

Copyright 2000, 2001, 2002 Jason Rennie.  All rights reserved.

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

perl(1)

http://www.cogsci.princeton.edu/~wn/

http://people.csail.mit.edu/~jrennie/WordNet/

=cut
