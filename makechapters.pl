#!/usr/bin/perl

# Copyright (c) 2013 by jxpk @ github

use strict;

use Getopt::Long;
use FileHandle;
use DirHandle;
use File::Copy qw(move);

sub print_help {
    print <<EOF;
Usage:
--help
--ext video file extensions to consider
--avsname single avs filename, if not specified, assumes separate avs file for each video
--fps=n fps to use
--chapters chapters file, if not specified, assumes separate output files so no chapters written
--subdir
    write avs files to an "avs" subdir, will adjust relative path in DirectShowSource
--traverse
    go down one directory level to search for video files instead of the current directory
--stereo
    convert mono to stereo
--cleanup
    remove .avs files, move any .mp4 files up if they are in "avs" subdirectories
    only goes down up to two levels
EOF

}

my $mediainfo = "C:/apps/video/MediaInfo/MediaInfocli.exe -f";

my ($fps,    $avsname,  $help,   $chaptername, $ext,
    $subdir, $traverse, $stereo, $cleanup
);

GetOptions(
    "help"     => \$help,
    "ext=s"    => \$ext,
    "avs=s"    => \$avsname,
    "fps=f"    => \$fps,
    "chap=s"   => \$chaptername,
    "subdir"   => \$subdir,
    "traverse" => \$traverse,
    "stereo"   => \$stereo,
    "cleanup"  => \$cleanup,
) || die;

if ( defined $help ) {
    print_help;
    exit;
}

if ((      defined $ext
        || defined $avsname
        || defined $fps
        || defined $chaptername
        || defined $subdir
        || defined $traverse
        || defined $stereo
    )
    && defined $cleanup
    )
{
    print_help and die "--cleanup cannot be used with any other option\n";
}

if ($cleanup) {
    cleanup('.');
    exit;
}

print_help and die "need --fps\n" unless $fps;
print_help and die "need --ext\n" unless $ext;

print_help
    and die
    "either specify both --avs and --chap (single file output) or neither (seperate files)\n"
    if ( ( $avsname and !defined $chaptername )
    || ( !defined $avsname and $chaptername ) );

if ($traverse) {
    my @dirs = get_dirs();

    process_dir($_) foreach @dirs;
}
else {
    process_dir('.');
}

sub cleanup {
    my $dir = shift;

    my $dh = new DirHandle($dir);
    print "cleanup $dir\n";
    chdir $dir;

    my @dirs = ();
    my $f;
    while ( defined( $f = $dh->read ) ) {

        #print ">$f\n";
        if ( -f $f and $f =~ /\.avs$/ ) {
            print "removing $f\n";
            unlink "$f";
        }
        push( @dirs, $f ) if ( -d $f and $f !~ /^\./ );
        if ( -d $f and $f !~ /^\./ ) { print "+$f\n"; }

        if ( $dir eq "avs" and $f =~ /\.mp4$/ ) {
            print "moving $f up\n";
            move( "$f", ".." );
        }
    }

    $dh->close;

    foreach my $sdir (@dirs) {
        cleanup($sdir);
    }

    chdir "..";

    # remove avs directory
    if ($dir eq "avs") {
        print "Removing avs dir\n";
        rmdir "avs" || print "ERROR: Could not remove avs dir: $!\n";
    }

}

sub process_dir {
    my $dir = shift;

    print "processing directory: $dir\n";

    chdir $dir if $dir ne ".";

    my @filelist = get_files();
    if ( @filelist == 0 ) {
        print "no files\n";
        chdir ".." if $dir ne ".";
        return;
    }

    if ($subdir) {
        mkdir "avs";
    }

    if ( $avsname and $chaptername ) {
        if ($subdir) {
            $avsname     = "avs/$avsname";
            $chaptername = "avs/$chaptername";
        }

        single_file_output(@filelist);

    }
    else {
        multi_file_output(@filelist);
    }

    chdir ".." if $dir ne ".";
}

sub single_file_output {
    my @filelist = @_;

    my $avsfh = FileHandle->new(">$avsname");
    die "Problem opening outfile: $!\n" if !defined $avsfh;

    my $chapterfh = FileHandle->new(">$chaptername");
    die "Problem opening outfile: $!\n" if !defined $chapterfh;

    my $runningtotal = 0;
    my $chapnum      = 1;

    if ($stereo) {
        print $avsfh "v = \\\n";
    }
    while ( my $filename = shift @filelist ) {
        my $time_ms = get_duration($filename);

        #print "$time_ms, $time_str\n";

        # append to avs file
        if ( $runningtotal > 0 and $avsfh ) {
            print $avsfh " ++ \\\n";
        }

        printf( $avsfh
                "DirectShowSource(\"%s\", fps=%.3f, audio=true, convertfps=true).AssumeFPS(%.3f)",
            ( $subdir ? "../" : "" ) . $filename,
            $fps, $fps

        );

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

    if ($stereo) {
        print $avsfh <<EOL
a=v.getchannel(1,1)
Audiodub(v,a)
EOL
    }
    $avsfh->close;
    $chapterfh->close;
}

sub multi_file_output {
    my @filelist = @_;

    foreach (@filelist) {
        my $filename = $_;
        my $avsname  = $_ . ".avs";
        $avsname =~ s/\.$ext//i;
        $avsname = "avs/$avsname" if $subdir;

        my $avsfh = FileHandle->new(">$avsname");
        die "Problem opening outfile: $!\n" if !defined $avsfh;

        print $avsfh "v=" if $stereo;

        printf( $avsfh
                "DirectShowSource(\"%s\", fps=%.3f, audio=true, convertfps=true).AssumeFPS(%.3f)",
            ( $subdir ? "../" : "" ) . $filename,
            $fps, $fps
        );

        if ($stereo) {
            print $avsfh <<EOL

a=v.getchannel(1,1)
Audiodub(v,a)
EOL
        }

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
    print "  " . join( "\n  ", @files ) . "\n" if (@files > 0);;
    $dh->close;
    return @files;
}

sub get_dirs {
    my $dh = new DirHandle('.');
    die "get_dirs: couldn't open dir\n" unless defined $dh;

    my @dirs = ();
    while ( defined( $_ = $dh->read ) ) {
        push( @dirs, $_ ) if ( -d $_ and !/^\./ );
    }

    # sort numerically, e.g. 9 < 10, otherwise sort by alphanumeric
    @dirs = sort {
        ( $a =~ /^(\d+)/ )[0] <=> ( $b =~ /^(\d+)/ )[0]
            || uc($a) cmp uc($b)
    } @dirs;
    #print "going into subdirs to search for files:\n" . join( "\n", @dirs );
    $dh->close;
    return @dirs;

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
        #   $time_str = $1;
        #}
    }
    close MI;

# sometimes mediainfo reports twice the duration in the audio/container than the video
    $time_ms = $time_ms_video if ( $time_ms_video < $time_ms );
    return $time_ms;
}
