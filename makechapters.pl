#!/usr/bin/perl

# Copyright (c) 2013 by jxpk @ github 

use strict;

use Getopt::Long;
use FileHandle;
use DirHandle;

sub print_help {
	    print <<EOF;
Usage:
--help
--ext video file extensions to consider
--avsname single avs filename, if not specified, assumes separate avs file for each video
--fps=n fps to use
--chapters chapters file, if not specified, assumes separate output files so no chapters written

EOF

}

my $mediainfo = "C:/apps/video/MediaInfo/MediaInfocli.exe -f";

my ( $fps, $avsname, $help, $chaptername, $ext );

GetOptions(
    "help"   => \$help,
    "ext=s"  => \$ext,
    "avs=s"  => \$avsname,
    "fps=i"  => \$fps,
    "chap=s" => \$chaptername,
) || die;

if ( defined $help ) {
	print_help;
    exit;
}

print_help and die "need --fps\n" unless $fps;
print_help and die "need --ext\n" unless $ext;

print_help and die
    "either specify both --avs and --chap (single file output) or neither (seperate files)\n"
    if ( ( $avsname and !defined $chaptername )
    || ( !defined $avsname and $chaptername ) );

my @filelist = get_files();

if ( $avsname and $chaptername ) {
    single_file_output(@filelist);
}
else {
    multi_file_output(@filelist);
}


sub single_file_output {
    my @filelist = @_;

    my $avsfh = FileHandle->new(">$avsname");
    die "Problem opening outfile: $!\n" if !defined $avsfh;

    my $chapterfh = FileHandle->new(">$chaptername");
    die "Problem opening outfile: $!\n" if !defined $chapterfh;

    my $runningtotal = 0;
    my $chapnum      = 1;

    while ( my $filename = shift @filelist ) {
        my $time_ms = get_duration($filename);

        #print "$time_ms, $time_str\n";

        # append to avs file
        if ( $runningtotal > 0 and $avsfh ) {
            print $avsfh " ++ \\\n";
        }

        print $avsfh
            "DirectShowSource(\"$filename\", fps=$fps.000, audio=true, convertfps=true).AssumeFPS($fps,1)";

        printf( $chapterfh "CHAPTER%02d=%s\nCHAPTER%02dNAME=%s\n",
            $chapnum, ms_to_str($runningtotal),
            $chapnum, $filename
        );
        $runningtotal += $time_ms;

        # round up to nearest second
        $runningtotal = round_second($runningtotal);
        $chapnum++;
    }

    print $avsfh "\n" if $avsfh;
    $avsfh->close;
    $chapterfh->close;
}

sub multi_file_output {
    my @filelist = @_;

    foreach (@filelist) {
    	my $filename = $_;
        print $filename . "\n";
        my $avsname = $_ . ".avs";

        my $avsfh = FileHandle->new(">$avsname");
        die "Problem opening outfile: $!\n" if !defined $avsfh;

        print $avsfh
            "DirectShowSource(\"$filename\", fps=$fps.000, audio=true, convertfps=true).AssumeFPS($fps,1)\n";
        $avsfh->close;
    }
}

sub ms_to_str {
    my $ms = shift;
    my ( $h, $m, $s, $fs );
    $h  = $ms / 3600 / 1000;
    $m  = ( $ms / 60 / 1000 ) % 60;
    $s  = ( $ms / 1000 ) % 60;
    $fs = $ms % 1000;
    return sprintf( "%02d:%02d:%02d.%03d", $h, $m, $s, $fs );
}

# round up to nearest second
sub round_second {
    my $t  = shift;
    my $ms = $t % 1000;
    $t += ( 1000 - $ms ) unless ( $ms == 0 );
    return $t;
}

sub get_files {
    my $dh = new DirHandle('.');
    die "couldn't open dir\n" unless defined $dh;

    my @files = ();
    while ( defined( $_ = $dh->read ) ) {
        push( @files, $_ ) if (/$ext$/i);
    }

    # sort numerically, e.g. 9 < 10, otherwise sort by alphanumeric
    @files = sort {
        ( $a =~ /^(\d+)/ )[0] <=> ( $b =~ /^(\d+)/ )[0]
            || uc($a) cmp uc($b)
    } @files;
    print join( "\n", @files );
    $dh->close;
    return @files;
}

sub get_duration {

    my $filename = shift;

    open( MI, $mediainfo . " \"$filename\"|" ) || die $!;
    my $time_ms;
    my $time_str;
    my $time_ms_video;
    my $in_video = 0;
    while ( my $outmi = <MI> ) {
        $in_video = 1 if $outmi =~ /^Video$/i;
        $in_video = 0 if $outmi =~ /^Audio$/i;

        #print $outmi;
        if ( $outmi =~ /^Duration\s+:\s(\d+)\s*$/ ) {
            $time_ms = $1 unless $in_video;
            $time_ms_video = $1 if $in_video;
        }

        #if ($outmi =~/^Duration\s+:\s(\d{2,2}:\d{2,2}:\d{2,2}.\d+)/) {
        #	$time_str = $1;
        #}
    }
    close MI;

# sometimes mediainfo reports twice the duration in the audio/container than the video
    $time_ms = $time_ms_video if ( $time_ms_video < $time_ms );
    return $time_ms;
}
