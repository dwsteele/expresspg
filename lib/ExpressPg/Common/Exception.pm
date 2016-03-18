####################################################################################################################################
# COMMON EXCEPTION MODULE
####################################################################################################################################
package ExpressPg::Common::Exception;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess longmess);

use Exporter qw(import);
    our @EXPORT = qw();

####################################################################################################################################
# Exception codes
####################################################################################################################################
use constant ERROR_MINIMUM                                          => 100;
    push @EXPORT, qw(ERROR_MINIMUM);
use constant ERROR_MAXIMUM                                          => 199;
    push @EXPORT, qw(ERROR_MAXIMUM);

use constant ERROR_FILE_OPEN                                        => ERROR_MINIMUM;
    push @EXPORT, qw(ERROR_FILE_OPEN);
use constant ERROR_COMMAND_MISSING                                  => ERROR_MINIMUM + 1;
    push @EXPORT, qw(ERROR_COMMAND_MISSING);
use constant ERROR_COMMAND_INVALID                                  => ERROR_MINIMUM + 2;
    push @EXPORT, qw(ERROR_COMMAND_INVALID);
use constant ERROR_OPTION_INVALID                                   => ERROR_MINIMUM + 3;
    push @EXPORT, qw(ERROR_OPTION_INVALID);
use constant ERROR_CONFIG_INVALID                                   => ERROR_MINIMUM + 4;
    push @EXPORT, qw(ERROR_CONFIG_INVALID);
use constant ERROR_FILE_READ                                        => ERROR_MINIMUM + 5;
    push @EXPORT, qw(ERROR_FILE_READ);
use constant ERROR_FILE_WRITE                                       => ERROR_MINIMUM + 6;
    push @EXPORT, qw(ERROR_FILE_WRITE);

use constant ERROR_INVALID_VALUE                                    => ERROR_MAXIMUM - 1;
    push @EXPORT, qw(ERROR_INVALID_VALUE);
use constant ERROR_UNKNOWN                                          => ERROR_MAXIMUM;
    push @EXPORT, qw(ERROR_UNKNOWN);

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;       # Class name
    my $iCode = shift;       # Error code
    my $strMessage = shift;  # ErrorMessage
    my $strTrace = shift;    # Stack trace

    if ($iCode < ERROR_MINIMUM || $iCode > ERROR_MAXIMUM)
    {
        $iCode = ERROR_INVALID_VALUE;
    }

    # Create the class hash
    my $self = {};
    bless $self, $class;

    # Initialize exception
    $self->{iCode} = $iCode;
    $self->{strMessage} = $strMessage;
    $self->{strTrace} = $strTrace;

    return $self;
}

####################################################################################################################################
# CODE
####################################################################################################################################
sub code
{
    my $self = shift;

    return $self->{iCode};
}

####################################################################################################################################
# MESSAGE
####################################################################################################################################
sub message
{
    my $self = shift;

    return $self->{strMessage};
}

####################################################################################################################################
# TRACE
####################################################################################################################################
sub trace
{
    my $self = shift;

    return $self->{strTrace};
}

1;
