#!/usr/bin/env perl
# er.pl - Version 1.0.0
# ebook renamer
#
# Git repository available at http://github.com/SeniorWizard/ebook-renamer
#
# Copyright (c) 2015, Ole Dam Møller
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
# 
# * Neither the name of ebook-renamer nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# 

use strict;
use vars qw/ %Opt /;
use Getopt::Std;
use File::Basename;
use File::Spec::Functions;
use File::Copy qw(copy move);
use Encode;

eval("use EPUB::Parser");

if ($@) {
	Usage("This program requires the module EPUB::Parser to be installed");
}

Init();

Usage() if ($#ARGV == -1);

my $files = 0;
foreach my $arg (@ARGV) {
	next unless ( -r $arg );
	if ( -f $arg  ) {
		processfile($arg);
	} elsif ( -d $arg ) {
		processdir($arg);
	}
}
out("Considered $Opt{filesseen} files - handled $Opt{fileschanged}",1);

sub processdir {
	my $dir = shift;
	return undef unless (-r $dir);
	opendir(DIR, $dir);
	out("  looking in directory $dir",2);
	foreach my $file (grep !/^\.+$/, readdir(DIR)) {
		my $fullfile = catfile($dir,$file);
		if (-f "$fullfile") {
			processfile("$fullfile");
		} elsif ( -d "$fullfile" ) {
			if ( $Opt{recursive} ) {
				out(" decenting into $fullfile",2);
				processdir("$fullfile");
			} else {
				out(" not decenting into $fullfile",2);
			}
		} else {
			print(STDERR "$fullfile niether a file nor a directory - skipping\n");
		}
	}
}

sub processfile {
	my $file = shift;
	$Opt{filesseen}++;
	out("Considering file: $file",2);
	unless ($file =~ m/\.epub$/i){
		out("  not named .epub",2);
		return undef;
	}
	unless (-r $file) {
		out("  not readable",2);
		return undef;
	}

	if ( $Opt{minage} && -M $file < $Opt{minage} ) {
		out("  not $Opt{minage} days old",2);
		return undef;
	}

	my $newname = bookname("$file");
	unless ($newname) { 
		out("Error handling $file - skipping",0);
		return undef;
	}

	#make inplace rename
	my ($vol,$dir,$fil) = File::Spec->splitpath( $file );

	if ( $fil eq $newname ) {
		#correct named
		out("  already correct named",2);
	} else {
		out("  correct name set to $newname",2);
	}


	my @timestamp = (stat($file)) [8,9];

	if ($Opt{targetdir}) {
		$newname = catfile($Opt{targetdir}, $newname);
	} else {
		$newname = File::Spec->catpath($vol,$dir,$newname);
	}

	if ( $file eq $newname ) {
		#correct named and placed
		out("  no operation necesserey",2);
		return undef;
	}


	if (-e $newname) {
		print(STDERR "$newname already exists - not overwritten\n");
		return undef;
	}

	if ($Opt{rename} eq 'move' ) {
		out("moving $file to $newname",1);
		unless ($Opt{dryrun}) {
			move($file, $newname) || die "error moving $file to $newname: $!\n";
			utime @timestamp, $newname;
		}
	} else {
		out("copying $file to $newname",1);
		unless ($Opt{dryrun}) {
			copy(qq/$file/, qq/$newname/) || die "error copying $file to $newname: $!\n";
			utime @timestamp, "$newname";
		}
	}
	$Opt{fileschanged}++;
	if ($Opt{maxupdates} && $Opt{fileschanged} >= $Opt{maxupdates}) {
		out("  handled $Opt{maxupdates} files - bailing out",1);
		exit;
	}
	return 1;
}

sub bookname {
	my $book = shift;

	my $ep = EPUB::Parser->new;

	# load epub
	eval { $ep->load_file({ file_path  => "$book" }); };
	if ($@) {
		return undef;
	}


    # get opf version
    my $version = 0;
    eval { $version = $ep->opf->guess_version; };
    if ($@) {
       return undef;
    }

	# get opf variables, shadow EPUB::Parser as it does not exit gracefylly
    my %md;
    foreach my $var (qw(title creator language identifier)) {
        eval {
            $md{$var} = $ep->opf->metadata->${var};
        };
        if ($@) {
            out(" Error getting $var for $book", 0);
            $md{$var} = 'unknown';
            if ($Opt{debug} < 2) {
                # this is an error unless running in pure debugmode
                return undef;
            }
        }
    }


	$md{author} = $md{creator};
	out("  Book info: author $md{author}, title $md{title}",2);
	#make some minor improvements
	$md{author} =~ s/  +/ /g;
	$md{author} =~ s/ (and|und|et|i|och|og) /, /g;
	$md{author} =~ s/ & /, /g;

	my $name = sprintf("%s; %s.epub", mksafe($md{author}), mksafe($md{title}));

	if ($Opt{asciify}) {
		$name = asciify($name);
	}

	##white space
	if ($Opt{whitespace}) {
		$name =~ s/\s+/_/g;
	}

	##lower case
	if ($Opt{lowercase}) {
		$name = lc($name);
	}

    #return encode('ISO-8859-1',$name);
	return encode('utf-8',$name);
}

sub mksafe {
	my $str = shift || 'Unknown';
	#trim first
	$str =~ s/^\s+//g;
	$str =~ s/[\s\.]+$//g;
	#\ / and : used as directoryseperators
	$str =~ s/[\\\/\:]+/-/g;
	#non printables
	$str =~ s/[\x00-\x1F]+//g;
	##. , [ ] { } ( ) ! ; " ' * ? < > | reserved for scripting may cause problems
	#$str =~ s/[\.\,\[\]\{\}\(\)\!\;\"\'\*\?\<\>\|]+/./g;
	return $str;
}

sub asciify {
	my %asciiize = (
  		"\x{00C0}" => "A",    "\x{00C1}" => "A",    "\x{00C2}" => "A",
  		"\x{00C3}" => "A",    "\x{00C4}" => "Ae",   "\x{00C5}" => "A",
  		"\x{00C6}" => "A",    "\x{0100}" => "A",    "\x{0104}" => "A",
  		"\x{0102}" => "A",    "\x{00C7}" => "C",    "\x{0106}" => "C",
  		"\x{010C}" => "C",    "\x{0108}" => "C",    "\x{010A}" => "C",
  		"\x{010E}" => "D",    "\x{0110}" => "D",    "\x{00C8}" => "E",
  		"\x{00C9}" => "E",    "\x{00CA}" => "E",    "\x{00CB}" => "E",
  		"\x{0112}" => "E",    "\x{0118}" => "E",    "\x{011A}" => "E",
  		"\x{0114}" => "E",    "\x{0116}" => "E",    "\x{011C}" => "G",
  		"\x{011E}" => "G",    "\x{0120}" => "G",    "\x{0122}" => "G",
  		"\x{0124}" => "H",    "\x{0126}" => "H",    "\x{00CC}" => "I",
  		"\x{00CD}" => "I",    "\x{00CE}" => "I",    "\x{00CF}" => "I",
  		"\x{012A}" => "I",    "\x{0128}" => "I",    "\x{012C}" => "I",
  		"\x{012E}" => "I",    "\x{0130}" => "I",    "\x{0132}" => "IJ",
  		"\x{0134}" => "J",    "\x{0136}" => "K",    "\x{013D}" => "K",
  		"\x{0139}" => "K",    "\x{013B}" => "K",    "\x{013F}" => "K",
  		"\x{0141}" => "L",    "\x{00D1}" => "N",    "\x{0143}" => "N",
  		"\x{0147}" => "N",    "\x{0145}" => "N",    "\x{014A}" => "N",
  		"\x{00D2}" => "O",    "\x{00D3}" => "O",    "\x{00D4}" => "O",
  		"\x{00D5}" => "O",    "\x{00D6}" => "Oe",   "\x{00D8}" => "O",
  		"\x{014C}" => "O",    "\x{0150}" => "O",    "\x{014E}" => "O",
  		"\x{0152}" => "OE",   "\x{0154}" => "R",    "\x{0158}" => "R",
  		"\x{0156}" => "R",    "\x{015A}" => "S",    "\x{015E}" => "S",
  		"\x{015C}" => "S",    "\x{0218}" => "S",    "\x{0160}" => "S",
  		"\x{0164}" => "T",    "\x{0162}" => "T",    "\x{0166}" => "T",
  		"\x{021A}" => "T",    "\x{00D9}" => "U",    "\x{00DA}" => "U",
  		"\x{00DB}" => "U",    "\x{00DC}" => "Ue",   "\x{016A}" => "U",
  		"\x{016E}" => "U",    "\x{0170}" => "U",    "\x{016C}" => "U",
  		"\x{0168}" => "U",    "\x{0172}" => "U",    "\x{0174}" => "W",
  		"\x{0176}" => "Y",    "\x{0178}" => "Y",    "\x{00DD}" => "Y",
  		"\x{0179}" => "Z",    "\x{017B}" => "Z",    "\x{017D}" => "Z",
  		"\x{00E0}" => "a",    "\x{00E1}" => "a",    "\x{00E2}" => "a",
  		"\x{00E3}" => "a",    "\x{00E4}" => "ae",   "\x{0101}" => "a",
  		"\x{0105}" => "a",    "\x{0103}" => "a",    "\x{00E5}" => "a",
  		"\x{00E6}" => "ae",   "\x{00E7}" => "c",    "\x{0107}" => "c",
  		"\x{010D}" => "c",    "\x{0109}" => "c",    "\x{010B}" => "c",
  		"\x{010F}" => "d",    "\x{0111}" => "d",    "\x{00E8}" => "e",
  		"\x{00E9}" => "e",    "\x{00EA}" => "e",    "\x{00EB}" => "e",
  		"\x{0113}" => "e",    "\x{0119}" => "e",    "\x{011B}" => "e",
  		"\x{0115}" => "e",    "\x{0117}" => "e",    "\x{0192}" => "f",
  		"\x{011D}" => "g",    "\x{011F}" => "g",    "\x{0121}" => "g",
  		"\x{0123}" => "g",    "\x{0125}" => "h",    "\x{0127}" => "h",
  		"\x{00EC}" => "i",    "\x{00ED}" => "i",    "\x{00EE}" => "i",
  		"\x{00EF}" => "i",    "\x{012B}" => "i",    "\x{0129}" => "i",
  		"\x{012D}" => "i",    "\x{012F}" => "i",    "\x{0131}" => "i",
  		"\x{0133}" => "ij",   "\x{0135}" => "j",    "\x{0137}" => "k",
  		"\x{0138}" => "k",    "\x{0142}" => "l",    "\x{013E}" => "l",
  		"\x{013A}" => "l",    "\x{013C}" => "l",    "\x{0140}" => "l",
  		"\x{00F1}" => "n",    "\x{0144}" => "n",    "\x{0148}" => "n",
  		"\x{0146}" => "n",    "\x{0149}" => "n",    "\x{014B}" => "n",
  		"\x{00F2}" => "o",    "\x{00F3}" => "o",    "\x{00F4}" => "o",
  		"\x{00F5}" => "o",    "\x{00F6}" => "oe",   "\x{00F8}" => "o",
  		"\x{014D}" => "o",    "\x{0151}" => "o",    "\x{014F}" => "o",
  		"\x{0153}" => "oe",   "\x{0155}" => "r",    "\x{0159}" => "r",
  		"\x{0157}" => "r",    "\x{015B}" => "s",    "\x{0161}" => "s",
  		"\x{0165}" => "t",    "\x{00F9}" => "u",    "\x{00FA}" => "u",
  		"\x{00FB}" => "u",    "\x{00FC}" => "ue",   "\x{016B}" => "u",
  		"\x{016F}" => "u",    "\x{0171}" => "u",    "\x{016D}" => "u",
  		"\x{0169}" => "u",    "\x{0173}" => "u",    "\x{0175}" => "w",
  		"\x{00FF}" => "y",    "\x{00FD}" => "y",    "\x{0177}" => "y",
  		"\x{017C}" => "z",    "\x{017A}" => "z",    "\x{017E}" => "z",
  		"\x{00DF}" => "ss",   "\x{017F}" => "ss",   "\x{0391}" => "A",
  		"\x{0386}" => "A",    "\x{1F08}" => "A",    "\x{1F09}" => "A",
  		"\x{1F0A}" => "A",    "\x{1F0B}" => "A",    "\x{1F0C}" => "A",
  		"\x{1F0D}" => "A",    "\x{1F0E}" => "A",    "\x{1F0F}" => "A",
  		"\x{1F88}" => "A",    "\x{1F89}" => "A",    "\x{1F8A}" => "A",
  		"\x{1F8B}" => "A",    "\x{1F8C}" => "A",    "\x{1F8D}" => "A",
  		"\x{1F8E}" => "A",    "\x{1F8F}" => "A",    "\x{1FB8}" => "A",
  		"\x{1FB9}" => "A",    "\x{1FBA}" => "A",    "\x{1FBB}" => "A",
  		"\x{1FBC}" => "A",    "\x{0392}" => "B",    "\x{0393}" => "G",
  		"\x{0394}" => "D",    "\x{0395}" => "E",    "\x{0388}" => "E",
  		"\x{1F18}" => "E",    "\x{1F19}" => "E",    "\x{1F1A}" => "E",
  		"\x{1F1B}" => "E",    "\x{1F1C}" => "E",    "\x{1F1D}" => "E",
  		"\x{1FC9}" => "E",    "\x{1FC8}" => "E",    "\x{0396}" => "Z",
  		"\x{0397}" => "I",    "\x{0389}" => "I",    "\x{1F28}" => "I",
  		"\x{1F29}" => "I",    "\x{1F2A}" => "I",    "\x{1F2B}" => "I",
  		"\x{1F2C}" => "I",    "\x{1F2D}" => "I",    "\x{1F2E}" => "I",
  		"\x{1F2F}" => "I",    "\x{1F98}" => "I",    "\x{1F99}" => "I",
  		"\x{1F9A}" => "I",    "\x{1F9B}" => "I",    "\x{1F9C}" => "I",
  		"\x{1F9D}" => "I",    "\x{1F9E}" => "I",    "\x{1F9F}" => "I",
  		"\x{1FCA}" => "I",    "\x{1FCB}" => "I",    "\x{1FCC}" => "I",
  		"\x{0398}" => "TH",   "\x{0399}" => "I",    "\x{038A}" => "I",
  		"\x{03AA}" => "I",    "\x{1F38}" => "I",    "\x{1F39}" => "I",
  		"\x{1F3A}" => "I",    "\x{1F3B}" => "I",    "\x{1F3C}" => "I",
  		"\x{1F3D}" => "I",    "\x{1F3E}" => "I",    "\x{1F3F}" => "I",
  		"\x{1FD8}" => "I",    "\x{1FD9}" => "I",    "\x{1FDA}" => "I",
  		"\x{1FDB}" => "I",    "\x{039A}" => "K",    "\x{039B}" => "L",
  		"\x{039C}" => "M",    "\x{039D}" => "N",    "\x{039E}" => "KS",
  		"\x{039F}" => "O",    "\x{038C}" => "O",    "\x{1F48}" => "O",
  		"\x{1F49}" => "O",    "\x{1F4A}" => "O",    "\x{1F4B}" => "O",
  		"\x{1F4C}" => "O",    "\x{1F4D}" => "O",    "\x{1FF8}" => "O",
  		"\x{1FF9}" => "O",    "\x{03A0}" => "P",    "\x{03A1}" => "R",
  		"\x{1FEC}" => "R",    "\x{03A3}" => "S",    "\x{03A4}" => "T",
  		"\x{03A5}" => "Y",    "\x{038E}" => "Y",    "\x{03AB}" => "Y",
  		"\x{1F59}" => "Y",    "\x{1F5B}" => "Y",    "\x{1F5D}" => "Y",
  		"\x{1F5F}" => "Y",    "\x{1FE8}" => "Y",    "\x{1FE9}" => "Y",
  		"\x{1FEA}" => "Y",    "\x{1FEB}" => "Y",    "\x{03A6}" => "F",
  		"\x{03A7}" => "X",    "\x{03A8}" => "PS",   "\x{03A9}" => "O",
  		"\x{038F}" => "O",    "\x{1F68}" => "O",    "\x{1F69}" => "O",
  		"\x{1F6A}" => "O",    "\x{1F6B}" => "O",    "\x{1F6C}" => "O",
  		"\x{1F6D}" => "O",    "\x{1F6E}" => "O",    "\x{1F6F}" => "O",
  		"\x{1FA8}" => "O",    "\x{1FA9}" => "O",    "\x{1FAA}" => "O",
  		"\x{1FAB}" => "O",    "\x{1FAC}" => "O",    "\x{1FAD}" => "O",
  		"\x{1FAE}" => "O",    "\x{1FAF}" => "O",    "\x{1FFA}" => "O",
  		"\x{1FFB}" => "O",    "\x{1FFC}" => "O",    "\x{03B1}" => "a",
  		"\x{03AC}" => "a",    "\x{1F00}" => "a",    "\x{1F01}" => "a",
  		"\x{1F02}" => "a",    "\x{1F03}" => "a",    "\x{1F04}" => "a",
  		"\x{1F05}" => "a",    "\x{1F06}" => "a",    "\x{1F07}" => "a",
  		"\x{1F80}" => "a",    "\x{1F81}" => "a",    "\x{1F82}" => "a",
  		"\x{1F83}" => "a",    "\x{1F84}" => "a",    "\x{1F85}" => "a",
  		"\x{1F86}" => "a",    "\x{1F87}" => "a",    "\x{1F70}" => "a",
  		"\x{1F71}" => "a",    "\x{1FB0}" => "a",    "\x{1FB1}" => "a",
  		"\x{1FB2}" => "a",    "\x{1FB3}" => "a",    "\x{1FB4}" => "a",
  		"\x{1FB6}" => "a",    "\x{1FB7}" => "a",    "\x{03B2}" => "b",
  		"\x{03B3}" => "g",    "\x{03B4}" => "d",    "\x{03B5}" => "e",
  		"\x{03AD}" => "e",    "\x{1F10}" => "e",    "\x{1F11}" => "e",
  		"\x{1F12}" => "e",    "\x{1F13}" => "e",    "\x{1F14}" => "e",
  		"\x{1F15}" => "e",    "\x{1F72}" => "e",    "\x{1F73}" => "e",
  		"\x{03B6}" => "z",    "\x{03B7}" => "i",    "\x{03AE}" => "i",
  		"\x{1F20}" => "i",    "\x{1F21}" => "i",    "\x{1F22}" => "i",
  		"\x{1F23}" => "i",    "\x{1F24}" => "i",    "\x{1F25}" => "i",
  		"\x{1F26}" => "i",    "\x{1F27}" => "i",    "\x{1F90}" => "i",
  		"\x{1F91}" => "i",    "\x{1F92}" => "i",    "\x{1F93}" => "i",
  		"\x{1F94}" => "i",    "\x{1F95}" => "i",    "\x{1F96}" => "i",
  		"\x{1F97}" => "i",    "\x{1F74}" => "i",    "\x{1F75}" => "i",
  		"\x{1FC2}" => "i",    "\x{1FC3}" => "i",    "\x{1FC4}" => "i",
  		"\x{1FC6}" => "i",    "\x{1FC7}" => "i",    "\x{03B8}" => "th",
  		"\x{03B9}" => "i",    "\x{03AF}" => "i",    "\x{03CA}" => "i",
  		"\x{0390}" => "i",    "\x{1F30}" => "i",    "\x{1F31}" => "i",
  		"\x{1F32}" => "i",    "\x{1F33}" => "i",    "\x{1F34}" => "i",
  		"\x{1F35}" => "i",    "\x{1F36}" => "i",    "\x{1F37}" => "i",
  		"\x{1F76}" => "i",    "\x{1F77}" => "i",    "\x{1FD0}" => "i",
  		"\x{1FD1}" => "i",    "\x{1FD2}" => "i",    "\x{1FD3}" => "i",
  		"\x{1FD6}" => "i",    "\x{1FD7}" => "i",    "\x{03BA}" => "k",
  		"\x{03BB}" => "l",    "\x{03BC}" => "m",    "\x{03BD}" => "n",
  		"\x{03BE}" => "ks",   "\x{03BF}" => "o",    "\x{03CC}" => "o",
  		"\x{1F40}" => "o",    "\x{1F41}" => "o",    "\x{1F42}" => "o",
  		"\x{1F43}" => "o",    "\x{1F44}" => "o",    "\x{1F45}" => "o",
  		"\x{1F78}" => "o",    "\x{1F79}" => "o",    "\x{03C0}" => "p",
  		"\x{03C1}" => "r",    "\x{1FE4}" => "r",    "\x{1FE5}" => "r",
  		"\x{03C3}" => "s",    "\x{03C2}" => "s",    "\x{03C4}" => "t",
  		"\x{03C5}" => "y",    "\x{03CD}" => "y",    "\x{03CB}" => "y",
  		"\x{03B0}" => "y",    "\x{1F50}" => "y",    "\x{1F51}" => "y",
  		"\x{1F52}" => "y",    "\x{1F53}" => "y",    "\x{1F54}" => "y",
  		"\x{1F55}" => "y",    "\x{1F56}" => "y",    "\x{1F57}" => "y",
  		"\x{1F7A}" => "y",    "\x{1F7B}" => "y",    "\x{1FE0}" => "y",
  		"\x{1FE1}" => "y",    "\x{1FE2}" => "y",    "\x{1FE3}" => "y",
  		"\x{1FE6}" => "y",    "\x{1FE7}" => "y",    "\x{03C6}" => "f",
  		"\x{03C7}" => "x",    "\x{03C8}" => "ps",   "\x{03C9}" => "o",
  		"\x{03CE}" => "o",    "\x{1F60}" => "o",    "\x{1F61}" => "o",
  		"\x{1F62}" => "o",    "\x{1F63}" => "o",    "\x{1F64}" => "o",
  		"\x{1F65}" => "o",    "\x{1F66}" => "o",    "\x{1F67}" => "o",
  		"\x{1FA0}" => "o",    "\x{1FA1}" => "o",    "\x{1FA2}" => "o",
  		"\x{1FA3}" => "o",    "\x{1FA4}" => "o",    "\x{1FA5}" => "o",
  		"\x{1FA6}" => "o",    "\x{1FA7}" => "o",    "\x{1F7C}" => "o",
  		"\x{1F7D}" => "o",    "\x{1FF2}" => "o",    "\x{1FF3}" => "o",
  		"\x{1FF4}" => "o",    "\x{1FF6}" => "o",    "\x{1FF7}" => "o",
  		"\x{00A8}" => "",     "\x{0385}" => "",     "\x{1FBF}" => "",
  		"\x{1FFE}" => "",     "\x{1FCD}" => "",     "\x{1FDD}" => "",
  		"\x{1FCE}" => "",     "\x{1FDE}" => "",     "\x{1FCF}" => "",
  		"\x{1FDF}" => "",     "\x{1FC0}" => "",     "\x{1FC1}" => "",
  		"\x{0384}" => "",     "\x{1FEE}" => "",     "\x{1FEF}" => "",
  		"\x{1FED}" => "",     "\x{037A}" => "",     "\x{1FBD}" => "",
  		"\x{0410}" => "A",    "\x{0411}" => "B",    "\x{0412}" => "V",
  		"\x{0413}" => "G",    "\x{0414}" => "D",    "\x{0415}" => "E",
  		"\x{0401}" => "E",    "\x{0416}" => "ZH",   "\x{0417}" => "Z",
  		"\x{0418}" => "I",    "\x{0419}" => "I",    "\x{041A}" => "K",
  		"\x{041B}" => "L",    "\x{041C}" => "M",    "\x{041D}" => "N",
  		"\x{041E}" => "O",    "\x{041F}" => "P",    "\x{0420}" => "R",
  		"\x{0421}" => "S",    "\x{0422}" => "T",    "\x{0423}" => "U",
  		"\x{0424}" => "F",    "\x{0425}" => "KH",   "\x{0426}" => "TS",
  		"\x{0427}" => "CH",   "\x{0428}" => "SH",   "\x{0429}" => "SHCH",
  		"\x{042B}" => "Y",    "\x{042D}" => "E",    "\x{042E}" => "YU",
  		"\x{042F}" => "YA",   "\x{0430}" => "A",    "\x{0431}" => "B",
  		"\x{0432}" => "V",    "\x{0433}" => "G",    "\x{0434}" => "D",
  		"\x{0435}" => "E",    "\x{0451}" => "E",    "\x{0436}" => "ZH",
  		"\x{0437}" => "Z",    "\x{0438}" => "I",    "\x{0439}" => "I",
  		"\x{043A}" => "K",    "\x{043B}" => "L",    "\x{043C}" => "M",
  		"\x{043D}" => "N",    "\x{043E}" => "O",    "\x{043F}" => "P",
  		"\x{0440}" => "R",    "\x{0441}" => "S",    "\x{0442}" => "T",
  		"\x{0443}" => "U",    "\x{0444}" => "F",    "\x{0445}" => "KH",
  		"\x{0446}" => "TS",   "\x{0447}" => "CH",   "\x{0448}" => "SH",
  		"\x{0449}" => "SHCH", "\x{044B}" => "Y",    "\x{044D}" => "E",
  		"\x{044E}" => "YU",   "\x{044F}" => "YA",   "\x{042A}" => "",
  		"\x{044A}" => "",     "\x{042C}" => "",     "\x{044C}" => "",
  		"\x{00F0}" => "d",    "\x{00D0}" => "D",    "\x{00FE}" => "th",
  		"\x{00DE}" => "TH",
	);
	my $str = shift;
  	$str =~ s/([^\0-\x7f])/exists($asciiize{$1})?$asciiize{$1}:"?"/eg;
  	return $str;
}
        

sub out {
	my $msg = shift;
	my $lvl = shift || 2;
	if ( $lvl <= $Opt{debug} ) {
		print "$msg\n";
	}
}


sub Init {
    $Opt{prog} = basename($0);

    $Opt{debug}=0;
    $Opt{asciify}=0;
    $Opt{whitespace}=0;
    $Opt{lowercase}=0;
    $Opt{execute}=1;
    $Opt{dryrun}=0;
    $Opt{recurse}=0;
    $Opt{progress}=0;
    $Opt{maxupdates}=0;
    $Opt{rename}='move';
    $Opt{targetdir}='';
    $Opt{minage}=0;
	$Opt{fileschanged}=0;
	$Opt{filesseen}=0;

    getopts( "awlpdvrcm:n:t:h", \%Opt ) or Usage();


    if ($Opt{d}) {
        $Opt{dryrun}=1;
        $Opt{debug}=1;
    }

    if ($Opt{r}) {
        $Opt{recursive}=1;
    }

    if ($Opt{p}) {
        $Opt{debug}=1;
        $Opt{progress}=1;
    }

    if ($Opt{v}) {
        $Opt{debug}=2;
    }

    if ($Opt{c}) {
        $Opt{rename}='copy';
    }

    if ($Opt{a}) {
        $Opt{asciify}=1;
    }

    if ($Opt{w}) {
        $Opt{whitespace}=1;
    }

    if ($Opt{l}) {
        $Opt{lowercase}=1;
    }

    if ($Opt{t}) {
        if ( -d $Opt{t} && -w _ ) {
            $Opt{targetdir}=$Opt{t};
        } else {
            Usage("-t must be followed by a writable directory where epubs can be stored");
        }
    }

    if (defined($Opt{n}) && $Opt{n} =~ m#(\d+)#) {
        $Opt{maxupdates}=$1;
    }

    if (defined($Opt{m}) && $Opt{m} =~ m#(\d+)#) {
        $Opt{minage}=$1;
    }

    if ($Opt{h}) {
        Usage();
    }

	if ($#ARGV == -1) {
		Usage();
	}

}

sub Usage {
        my ($msg) = shift;

        print STDERR <<EOF;

usage $Opt{prog} [-n num] [-m days] [-t dir] [-dpcrawl] file1 file2 directory

      -d dry run: show what will be done
      -v verbose: be very chatty
      -p progress: show some progress while renaming files
      -n # maximum number of epubs to process
      -m # minimum age of file in days

      -a asciify: make filename 7-bit ascii, try to find a substitution or use a questionmark
      -w whitespace: replace whitesapce with underscore
      -l lowercase: only use lowercase letters

      -r recursive: recurse into subdirectories
      -c copy: instead of renaming the file, copy it and leave the original behind

      -t dir target directory: where files are placed insted of keeping them where they are


      -h help

EOF
        if ($msg) {
                print STDERR "Error: $msg\n";
                exit 1;
        }
        exit 0;
}

