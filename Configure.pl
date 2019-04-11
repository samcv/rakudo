#!/usr/bin/env perl
# Copyright (C) 2009 The Perl Foundation

use 5.10.1;
use strict;
use warnings;
use Text::ParseWords;
use Getopt::Long;
use File::Spec;
use Cwd;
use FindBin;

BEGIN {
    unless ( -e '3rdparty/nqp-configure/LICENSE' ) {
        print "Updating nqp-configure submodule...\n";
        my $msg =
qx{git submodule sync --quiet 3rdparty/nqp-configure && git submodule --quiet update --init 3rdparty/nqp-configure 2>&1};
        if ( $? >> 8 == 0 ) { print "OK\n" }
        else {
            if ( $msg =~ /[']([^']+)[']\s+already exists and is not an empty/ )
            {
                print "\n===SORRY=== ERROR: "
                  . "Cannot update submodule because directory exists and is not empty.\n"
                  . ">>> Please delete the following folder and try again:\n$1\n\n";
                exit 1;
            }
        }
    }
}

use lib ( "$FindBin::Bin/tools/lib",
    "$FindBin::Bin/3rdparty/nqp-configure/lib" );
use NQP::Config;
use NQP::Config::Rakudo;

$| = 1;

my $cfg    = NQP::Config::Rakudo->new;
my $config = $cfg->config( no_ctx => 1 );
my $lang   = $cfg->cfg('lang');

# We don't use ExtUtils::Command in Configure.pl, but it is used in the Makefile
# Try `use`ing it here so users know if they need to install this module
# (not included with *every* Perl installation)
use ExtUtils::Command;
MAIN: {
    if ( -r 'config.default' ) {
        unshift @ARGV, shellwords( slurp('config.default') );
    }

    my $config_status = "$config->{lclang}_config_status";
    $config->{$config_status} = join ' ', map { qq("$_") } @ARGV;

    GetOptions(
        $cfg->options,      'help!',
        'prefix=s',         'libdir=s',
        'sysroot=s',        'sdkroot=s',
        'no-relocatable',   'backends=s',
        'no-clean!',        'with-nqp=s',
        'gen-nqp:s',        'gen-moar:s',
        'moar-option=s@',   'git-protocol=s',
        'ignore-errors',    'make-install!',
        'makefile-timing!', 'git-depth=s',
        'git-reference=s',  'github-user=s',
        'rakudo-repo=s',    'nqp-repo=s',
        'moar-repo=s',      'roast-repo=s',
      )
      or do {
        print_help();
        exit(1);
      };

    # Print help if it's requested
    if ( $cfg->opt('help') ) {
        print_help();
        exit(0);
    }
    if ( $cfg->option('ignore-errors') ) {
        print
"===WARNING!===\nErrors are being ignored.\nIn the case of any errors the script may behave unexpectedly.\n";
    }

    $cfg->configure_from_options;
    $cfg->configure_refine_vars;
    $cfg->configure_relocatability;
    $cfg->configure_repo_urls;
    $cfg->configure_commands;
    $cfg->configure_misc;
    $cfg->configure_backends;

    # Save options in config.status
    $cfg->save_config_status;

    $cfg->options->{'gen-nqp'} ||= '' if $cfg->has_option('gen-moar');
    $cfg->gen_nqp;
    $cfg->configure_active_backends;

    open my $MAKEFILE, '>', 'Makefile'
      or die "Cannot open 'Makefile' for writing: $!";
    print $MAKEFILE "\n# Makefile code generated by Configure.pl:\n";
    $cfg->fill_template_file( 'Makefile', $MAKEFILE );

    close $MAKEFILE or die "Cannot write 'Makefile': $!";

    my $make = $cfg->cfg('make');

    unless ( $cfg->opt('no-clean') ) {
        no warnings;
        print "Cleaning up ...\n";
        if ( open my $CLEAN, '-|', "$make clean" ) {
            my @slurp = <$CLEAN>;
            close($CLEAN);
        }
    }

    if ( $cfg->opt('make-install') ) {
        system_or_die($make);
        system_or_die( $make, 'install' );
        print "\n$lang has been built and installed.\n";
    }
    else {
        print "\nYou can now use '$make' to build $lang.\n";
        print "After that, '$make test' will run some tests and\n";
        print "'$make install' will install $lang.\n";
    }

    exit 0;
}

#  Print some help text.
sub print_help {
    print <<"END";
Configure.pl - $lang Configure

General Options:
    --help             Show this text
    --prefix=<path>    Install files in dir; also look for executables there
    --libdir=<path>    Install architecture-specific files in dir; Perl6 modules
                       included
    --no-relocatable
                       Create a perl6 with a fixed NQP and Perl6 home dir
                       instead of dynamically identifying it (On AIX MoarVM is
                       always built non-relocatable, since AIX misses
                       a necessary mechanism.)
    --sdkroot=<path>   When given, use for searching build tools here, e.g.
                       nqp, java, node etc.
    --sysroot=<path>   When given, use for searching runtime components here
    --backends=jvm,moar,js
                       Which backend(s) to use (or ALL for all of them)
    --gen-nqp[=branch]
                       Download, build, and install a copy of NQP before writing
                       the Makefile
    --gen-moar[=branch]
                       Download, build, and install a copy of MoarVM to use
                       before writing the Makefile
    --with-nqp=<path>
                       Provide path to already installed nqp
    --make-install     Install Rakudo after configuration is done
    --moar-option='--option=value'
                       Options to pass to MoarVM's Configure.pl
                       For example: --moar-option='--compiler=clang'
    --github-user=<user>
                       Fetch all repositories (rakudo, nqp, roast, MoarVM) from
                       this github user. Note that the user must have all
                       required repos forked from the originals.
    --rakudo-repo=<url>
    --nqp-repo=<url>
    --moar-repo=<url>
    --roast-repo=<url>
                       User specified URL to fetch corresponding components
                       from. The URL will also be used to setup git push.
    --git-protocol={ssh,https,git}
                       Protocol used for cloning git repos
    --git-depth=<number>
                       Use the --git-depth option for git clone with parameter number
    --git-reference=<path>
                       Use --git-reference option to identify local path where git repositories are stored
                       For example: --git-reference=/home/user/repo/for_perl6
                       Folders 'nqp' and 'MoarVM' with corresponding git repos should be in for_perl6 folder
    --makefile-timing  Enable timing of individual makefile commands
    --no-clean         Skip cleanup before installation
    --ignore-errors    Ignore errors (such as the version of NQP)

Please note that the --gen-moar and --gen-nqp options are there for convenience
only and will actually immediately - at Configure time - compile and install
moar and nqp respectively. They will live under the path given to --prefix,
unless other targeting options are used. To configure how MoarVM should be
compiled, use the --moar-option flag and view MoarVM's Configure.pl for more
information on its configuration options.

Configure.pl also reads options from 'config.default' in the current directory.
END

    return;
}

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
