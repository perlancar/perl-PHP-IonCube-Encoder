#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use File::Slurper qw(read_binary write_binary);
use IPC::System::Options 'system', -log=>1;
use Perinci::CmdLine::Lite;

our %SPEC;

$SPEC{ioncube_encode_php_or_zip} = {
    v => 1.1,
    summary => 'Enkode file PHP tunggal atau ZIP berisi kumpulan file PHP',
    args => {
        input_file => {
            schema => 'str*',
            cmdline_aliases => {i=>{}},
            req => 1,
            pos => 0,
        },
        input_type => {
            schema => ['str*', in=>['php', 'zip']],
            default => 'php',
        },
        output_dir => {
            schema => 'str*',
            summary => 'If unspecified, will create a random temporary dir',
            cmdline_aliases => {o=>{}},
        },
        php_version => {
            schema => ['str*', in=>[qw/4 5 53 54 55 56/]],
            default => '53',
        },
        ioncube_encoder_path => {
            schema  => 'str*',
            #default => '/opt/ioncube/ioncube_encoder',
            default => '/opt/ioncube/ioncube_encoder.sh',
        },
        encoder_version => {
            schema  => ['str*', in=>[qw/7.0 8.3 9.0/]],
            default => '9.0',
        },
    },
};
sub ioncube_encode_php_or_zip {
    require Archive::Zip; # i wanted Archive::Any, but it doesn't provide interface to create
    require File::Copy;
    require File::Path;
    require File::Temp;
    require Proc::ChildError;
    require UUID::Random;

    my %args = @_;

    my $encoder_version = $args{encoder_version} // '9.0';

    my $input_file = $args{input_file};
    return [404, "No such input file: '$input_file'"] unless -f $input_file;

    my $output_dir = $args{output_dir};
    if (!$output_dir) {
        $output_dir = File::Temp::tempdir();
    }
    return [404, "No such output dir: '$output_dir'"] unless -d $output_dir;

    my $encoder_path = $args{ioncube_encoder_path};
    my $php_version  = $args{php_version};
    my $code_encode = sub {
        my $path = shift;
        my $output_basename = UUID::Random::generate() . ".php";
        my $output_path = "$output_dir/" . $output_basename;
        my @cmd = ("sudo", $encoder_path);
        push @cmd, "-$php_version";

        $log->tracef("encoder version: %s", $encoder_version);
        if ($encoder_version eq '8.3') {
            push @cmd, "-L";
        } elsif ($encoder_version eq '7.0') {
            push @cmd, "-O";
        }

        push @cmd, $path, "-o", $output_path;
        system @cmd;
        if ($?) {
            return [500, "Failed: " . Proc::ChildError::explain_child_error(),
                    undef, {"func.input_file"=>$path}];
        } elsif (!-f($output_path)) {
            return [500, "Encode command succeeds, but no output was created",
                    undef, {"func.input_file"=>$path, "func.output_path"=>$output_path}];
        } elsif ($args{input_type} eq 'php' && read_binary($output_path) !~ /ioncube/) {
            return [500, "Encode command succeeds, but output doesn't seem encoded, perhaps there's a syntax error in the PHP source code",
                    undef, {"func.input_file"=>$path, "func.output_path"=>$output_path}];
        } else {
            chmod 0644, $output_path;
            return [200, "OK", undef, {"func.input_file"=>$path, 'func.output_path'=>$output_path, 'func.output_basename'=>$output_basename}];
        }
    };

    my $res;
    if ($args{input_type} eq 'zip') {
        my $ar;
        eval { $ar = Archive::Zip->new($input_file) }; # XXX capture warning
        return [500, "Can't open input archive: $@"] if $@;
        return [500, "Can't create Archive::Zip object for input"] unless $ar;

        (my $output_basename = $input_file) =~ s!.+[/\\]!!;
        $output_basename .= ".zip";
        my $output_path = "$output_dir/$output_basename";

        my $resmeta = {};
        my $num_encoded = 0;
        my $num_failed = 0;

        for my $member ($ar->members) {
            next if $member->fileName =~ m![/\\]\z!;
            next unless $member->fileName =~ m!\.php\z!i;
            my $tmpname = UUID::Random::generate() . ".php";
            write_binary("$output_dir/$tmpname", $ar->contents($member));
            my $mres = $code_encode->("$output_dir/$tmpname");
            if ($mres->[0] == 200) {
                $num_encoded++;
                $log->debugf("Replacing ZIP member '%s' ...", $member->fileName);
                #$log->debugf("Content: %s", read_binary($mres->[3]{'func.output_path'}));
                $ar->contents($member->fileName, read_binary($mres->[3]{'func.output_path'}));
            } else {
                $num_failed++;
                $resmeta->{'func.item_results'}{$member->fileName} = $mres;
            }
        }
        $ar->writeToFileNamed($output_path);

        $resmeta->{'func.output_basename'} = $output_basename;
        $resmeta->{'func.output_path'} = $output_path;
        $res = [200, "Success ($num_encoded encoded, $num_failed failed)", undef, $resmeta];
    } else {
        $res = $code_encode->($input_file);
    }
    $res;
}

Perinci::CmdLine::Lite->new(
    url => '/main/ioncube_encode_php_or_zip',
)->run;

__DATA__

ionCube PHP Encoder Evaluation Version 10.0 Enhancement 1
Language Support: PHP 4, 5, 5.3, 5.4, 5.5, 5.6, 7.0, 7.1
Copyright (c) 2002-2017 ionCube Ltd.
0

ionCube PHP Encoder Version 9.0 Enhancement 5
Language Support: PHP 4, 5, 5.3, 5.4, 5.5, 5.6
Copyright (c) 2002-2016 ionCube Ltd.
