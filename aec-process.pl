#!/usr/bin/env perl
use v5.14;
use strict;
use warnings;
use utf8;

use HTTP::Tiny;
use Encode ();
use JSON::PP qw(encode_json);
use FindBin;

sub write_file {
    my ($file, $content) = @_;

    my $output_dir = $ENV{AEC_OUTPUT_DIR} || ".";

    open my $fh, ">", "${output_dir}/$file";
    print $fh $content;
    close $fh;
}

sub fetch {
    my $url = $_[0];
    my $ua = HTTP::Tiny->new;
    my $response = $ua->get($url);

    die "fetch failed" unless $response->{success};

    return [ $response->{content}, [split / *\n */, Encode::decode(big5 => $response->{content})] ];
}

sub fetch_and_save_spds {
    my $fetched = fetch("http://www.aec.gov.tw/open/spds.csv");

    my $csv = $fetched->[1];

    my @t = $csv->[0] =~ m!資料時間：民國([0-9]+)年([0-9]+)月([0-9]+)日 ([0-9]+)點([0-9]+)分([0-9]+)秒!;
    $t[0] += 1911;

    my $p = qr/\s*,\s*/;

    my (undef, @machine) = split($p => $csv->[1]);
    my (undef, @status)  = split($p => $csv->[2]);
    my (undef, @ratio)   = split($p => $csv->[3]);
    my (undef, @power)   = split($p => $csv->[4]);

    my $status_code_to_text = {};
    for(@{$csv}[7..$#$csv]) {
        my ($n,$text) = split /:/;
        $status_code_to_text->{$n} = $text;
    }

    my $localtime = sprintf("%04d-%02d-%02dT%02d:%02d:%02d+08", @t);
    my $spds = [
        map { +{
            localtime => $localtime,
            machine => $machine[$_],
            status  => 0+ $status[$_],
            ratio   => 0+ $ratio[$_],
            power   => 0+ $power[$_],
            status_text => $status_code_to_text->{ 0+ $status[$_] } // "通信維護"
        } } 0..$#machine
    ];

    write_file("spds.csv", $fetched->[0]);
    write_file("spds.json", encode_json($spds));
}

sub fetch_and_save_gammamonitor {
    my $fetched = fetch("http://www.aec.gov.tw/open/gammamonitor.csv");
    my $csv = $fetched->[1];

    my $monitors = [
        map {
            my @row = split ",", $csv->[$_];
            $row[3] .= ":00+08";
            $row[3] =~ s!/!-!g;
            $row[3] =~ s! !T!g;

            +{
                station    => $row[0],
                station_en => $row[1],
                value      => $row[2],
                localtime  => $row[3],
            }
        } 1..$#$csv
    ];

    write_file("gammamonitor.csv", $fetched->[0]);
    write_file("gammamonitor.json", encode_json($monitors));
}

# main

fetch_and_save_gammamonitor;
fetch_and_save_spds;

if ($ENV{AEC_GIT_AUTOCOMMIT} && $ENV{AEC_OUTPUT_DIR}) {
    chdir($FindBin::Bin);
    chomp( my $sha1 = `git log -1 --format='%H' aec-process.pl` );

    chdir($ENV{AEC_OUTPUT_DIR});
    system("git add --all");
    system("git commit -m 'autocommit with aec-process.pl sha1'");
    system("git pull");
    system("git push");
}
