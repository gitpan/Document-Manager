# Basic repo operations

use strict;
my @scripts;

BEGIN {
@scripts = qw(
scripts/get_docs
scripts/dmsd
scripts/repo_add
scripts/ls_docs
scripts/repo_export
scripts/repo_get
scripts/repo_init
scripts/repo_ls
scripts/repo_put
scripts/stat_docs
scripts/submit_doc
scripts/update_doc
);
}

use Test::More tests => 1+$#scripts;

foreach my $script (@scripts) {
    next unless $script;
    `perl -c $script`;
    ok ( $?==0, "Verifying compilation of '$script'") or
       diag("Script '$script' failed");
}

