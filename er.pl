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
			move($file, $newname);
			utime @timestamp, $newname;
		}
	} else {
		out("copying $file to $newname",1);
		unless ($Opt{dryrun}) {
			copy($file, $newname);
			utime @timestamp, $newname;
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

	my $md = $ep->opf->metadata;


	#print join(' ', ($md->title, $md->creator, $md->language, $md->identifier, $cover_img_path, $at->{cover}{href}, $at->{cover-image}{href}, "\n"));

	my $author = $md->creator;
	out("  Book info: author $author, title " . $md->title,2);
	#make some minor improvements
	$author =~ s/  +/ /g;
	$author =~ s/ (and|und|et|i|och|og) /, /g;
	$author =~ s/ & /, /g;

	my $name = sprintf("%s; %s.epub", mksafe($author), mksafe($md->title));

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
	##white space
	#$str =~ s/\s+/_/g;
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
        $Opt{execute}=1;
        $Opt{dryrun}=0;
        $Opt{recurse}=0;
        $Opt{maxupdates}=0;
        $Opt{rename}='move';
        $Opt{targetdir}='';
        $Opt{minage}=0;
	$Opt{fileschanged}=0;
	$Opt{filesseen}=0;

        getopts( "dvrcm:n:t:h", \%Opt ) or Usage();


        if ($Opt{d}) {
                $Opt{dryrun}=1;
                $Opt{debug}=1;
        }

        if ($Opt{r}) {
                $Opt{recursive}=1;
        }

        if ($Opt{v}) {
                $Opt{debug}=2;
        }

        if ($Opt{c}) {
                $Opt{rename}='copy';
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

usage $Opt{prog} [-n num] [-m days] [-t dir] [-drc] file1 file2 directory

      -d dry run: show what will be done
      -v verbode: be very chatty
      -n # maximum number of epubs to process
      -m # minimum age of file in days

      -r recursive: recurse into subdirectories
      -c copy: instead of renameing the file, copy it and leave the original behind

      -t directory target directory where files are placed instad og keeping them where they are


      -h help

EOF
        if ($msg) {
                print STDERR "Error: $msg\n";
                exit 1;
        }
}

