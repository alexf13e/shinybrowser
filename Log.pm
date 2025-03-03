
package Log;

use warnings;
use strict;
use Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(log_write log_print);

our $enabled = 1; # set to 1 to enable logging if having issues

sub log_write
{
    if (not $enabled)
    {
        return;
    }

    if (scalar(@_) > 0)
    {
        open(FH, ">>", "log.txt") or die $!;
        print(FH $_[0]);
        close(FH);
    }
}

1;
