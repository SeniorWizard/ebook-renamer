ebook renamer
===
[![Build Status](https://travis-ci.org/SeniorWizard/ebook-renamer.svg?branch=master)](https://travis-ci.org/SeniorWizard/ebook-renamer)

ebook renamer is a script written in perl, which looks into an ebook in epub format and change the filename according to author and title from the metadata. Specificly the new name of the file will be `"<author>; <title>.epub"` thus making it possible to order your electronic books the same way the paper books is organized on the shelf.

The default behaviour is to strip non-printables and replace unsafe characters /, \ and : with a dash, and rename the file but leave it the same place.

Requirements
==

* Perl 5.6 or newer
* EPUB::Parser module http://search.cpan.org/~tokubass/EPUB-Parser-0.05/
* Unix/Linux based operating system (tested on FreeBSD, Ubuntu and OSX)
* Windows is not tested but should work
* some poorly named ebooks in epub format.

Install
==

    git clone https://github.com/SeniorWizard/ebook-renamer.git
    chmod +x er.pl
    cpanm --quiet EPUB::Parser

Usage
==

    usage er.pl [-n num] [-m days] [-t dir] [-drc] file1 file2 directory
    
      -d dry run: show what will be done
      -v verbose: be very chatty
      -n # maximum number of epubs to process
      -m # minimum age of file in days
    
      -r recursive: recurse into subdirectories
      -c copy: instead of renameing the file, copy it and leave the original behind
    
      -t directory target directory where files are placed instad og keeping them where they are
    
      -h help

Running
==
Just rename the book.epub

    ./er.pl book.epub

Show what will be done, but dont do anything

    ./er.pl -d book.epub

Be very verbosive about what will be done

    ./er.pl -dv book.epub

Rename all books in a book collection directory tree

    ./er.pl -r /path/to/collection/

Keep originals but make copies of books found to book directory

    ./er.pl -rc -t /path/to/collection/ /dev/usb1 /tmp



