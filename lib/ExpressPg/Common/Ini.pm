####################################################################################################################################
# COMMON INI MODULE
####################################################################################################################################
package ExpressPg::Common::Ini;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Exporter qw(import);
    our @EXPORT = qw();
use Fcntl qw(:mode O_WRONLY O_CREAT O_TRUNC);
use File::Basename qw(dirname basename);
use IO::Handle;

use ExpressPg::Common::Exception;
use ExpressPg::Common::Log;
use ExpressPg::Common::String;

####################################################################################################################################
# Operation constants
####################################################################################################################################
use constant OP_INI                                                 => 'Ini';

use constant OP_INI_INI_SAVE                                        => OP_INI . "::iniSave";
use constant OP_INI_SET                                             => OP_INI . "->set";

####################################################################################################################################
# Command constants
####################################################################################################################################
use constant CMD_BUILD                                              => 'build';
    push @EXPORT, qw(CMD_BUILD);
use constant CMD_UPDATE                                             => 'update';
    push @EXPORT, qw(CMD_UPDATE);

####################################################################################################################################
# Config constants
####################################################################################################################################
use constant CONFIG_SECTION_FULL                                    => 'full';
    push @EXPORT, qw(CONFIG_SECTION_FULL);
use constant CONFIG_SECTION_CONFIG                                  => 'config';
    push @EXPORT, qw(CONFIG_SECTION_CONFIG);
use constant CONFIG_SECTION_DB                                      => 'database';
    push @EXPORT, qw(CONFIG_SECTION_DB);
use constant CONFIG_SECTION_HISTORY                                 => 'history';
    push @EXPORT, qw(CONFIG_SECTION_HISTORY);
use constant CONFIG_SECTION_FEATURE                                 => 'feature';
    push @EXPORT, qw(CONFIG_SECTION_FEATURE);
use constant CONFIG_SECTION_FULL_TEST                               => 'full-test';
    push @EXPORT, qw(CONFIG_SECTION_FULL_TEST);
use constant CONFIG_SECTION_UPDATE                                  => 'update';
    push @EXPORT, qw(CONFIG_SECTION_UPDATE);

use constant CONFIG_KEY_FILE                                        => 'file';
    push @EXPORT, qw(CONFIG_KEY_FILE);
use constant CONFIG_KEY_ID_MAX                                      => 'id-max';
    push @EXPORT, qw(CONFIG_KEY_ID_MAX);
use constant CONFIG_KEY_ID_MIN                                      => 'id-min';
    push @EXPORT, qw(CONFIG_KEY_ID_MIN);
use constant CONFIG_KEY_LIBRARY                                     => 'library';
    push @EXPORT, qw(CONFIG_KEY_LIBRARY);
use constant CONFIG_KEY_NAME                                        => 'name';
    push @EXPORT, qw(CONFIG_KEY_NAME);
use constant CONFIG_KEY_PREFIX                                      => 'prefix';
    push @EXPORT, qw(CONFIG_KEY_PREFIX);
use constant CONFIG_KEY_SCHEMA_EXCLUDE                              => 'schema-exclude';
    push @EXPORT, qw(CONFIG_KEY_SCHEMA_EXCLUDE);
use constant CONFIG_KEY_OWNER                                       => 'owner';
    push @EXPORT, qw(CONFIG_KEY_OWNER);

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;                  # Class name
    my $strFileName = shift;            # Manifest filename
    my $bLoad = shift;                  # Load the ini?

    # Create the class hash
    my $self = {};
    bless $self, $class;

    # Filename must be specified
    if (!defined($strFileName))
    {
        confess &log(ASSERT, 'filename must be provided');
    }

    # Set variables
    my $oContent = {};
    $self->{oContent} = $oContent;
    $self->{strFileName} = $strFileName;

    # Load the ini if specified
    if (!defined($bLoad) || $bLoad)
    {
        $self->load();
    }

    return $self;
}

####################################################################################################################################
# load
#
# Load the ini.
####################################################################################################################################
sub load
{
    my $self = shift;

    iniLoad($self->{strFileName}, $self->{oContent});
}

####################################################################################################################################
# iniLoad
#
# Load file from standard INI format to a hash.
####################################################################################################################################
push @EXPORT, qw(iniLoad);

sub iniLoad
{
    my $strFileName = shift;
    my $oContent = shift;

    # Open the ini file for reading
    my $hFile;
    my $strSection;

    open($hFile, '<', $strFileName)
        or confess &log(ERROR, "unable to open ${strFileName}");

    # Read the INI file
    while (my $strLine = readline($hFile))
    {
        $strLine = trim($strLine);

        # Skip lines that are blank or comments
        if ($strLine ne '' && $strLine !~ '^[ ]*#.*')
        {
            # Get the section
            if (index($strLine, '[') == 0)
            {
                $strSection = substr($strLine, 1, length($strLine) - 2);
            }
            else
            {
                # Get key and value
                my $iIndex = index($strLine, '=');

                if ($iIndex == -1)
                {
                    confess &log(ERROR, "unable to read from ${strFileName}: ${strLine}");
                }

                my $strKey = substr($strLine, 0, $iIndex);
                my $strValue = substr($strLine, $iIndex + 1);

                if (defined($$oContent{$strSection}{$strKey}))
                {
                    if (ref($$oContent{$strSection}{$strKey}) ne 'ARRAY')
                    {
                        $$oContent{$strSection}{$strKey} = [$$oContent{$strSection}{$strKey}];
                    }

                    push(@{$oContent->{$strSection}{$strKey}}, $strValue);
                }
                else
                {
                    $$oContent{$strSection}{$strKey} = $strValue;
                }
            }
        }
    }

    close($hFile);
    return($oContent);
}

####################################################################################################################################
# get
#
# Get a value.
####################################################################################################################################
sub get
{
    my $self = shift;
    my $strSection = shift;
    my $strValue = shift;
    my $strSubValue = shift;
    my $bRequired = shift;
    my $oDefault = shift;

    my $oContent = $self->{oContent};

    # Section must always be defined
    if (!defined($strSection))
    {
        confess &log(ASSERT, 'section is not defined');
    }

    # Set default for required
    $bRequired = defined($bRequired) ? $bRequired : true;

    # Store the result
    my $oResult = undef;

    if (defined($strSubValue))
    {
        if (!defined($strValue))
        {
            confess &log(ASSERT, "subvalue '${strSubValue}' requested but value is not defined");
        }

        if (defined(${$oContent}{$strSection}{$strValue}))
        {
            $oResult = ${$oContent}{$strSection}{$strValue}{$strSubValue};
        }
    }
    elsif (defined($strValue))
    {
        if (defined(${$oContent}{$strSection}))
        {
            $oResult = ${$oContent}{$strSection}{$strValue};
        }
    }
    else
    {
        $oResult = ${$oContent}{$strSection};
    }

    if (!defined($oResult) && $bRequired)
    {
        confess &log(ASSERT, "manifest section '$strSection'" . (defined($strValue) ? ", value '$strValue'" : '') .
                              (defined($strSubValue) ? ", subvalue '$strSubValue'" : '') . ' is required but not defined');
    }

    if (!defined($oResult) && defined($oDefault))
    {
        $oResult = $oDefault;
    }

    return $oResult
}

####################################################################################################################################
# boolGet
#
# Get a numeric value.
####################################################################################################################################
sub boolGet
{
    my $self = shift;
    my $strSection = shift;
    my $strValue = shift;
    my $strSubValue = shift;
    my $bRequired = shift;
    my $bDefault = shift;

    return $self->get($strSection, $strValue, $strSubValue, $bRequired,
                      defined($bDefault) ? ($bDefault ? true : false) : undef) ? true : false;
}

####################################################################################################################################
# numericGet
#
# Get a numeric value.
####################################################################################################################################
sub numericGet
{
    my $self = shift;
    my $strSection = shift;
    my $strValue = shift;
    my $strSubValue = shift;
    my $bRequired = shift;
    my $nDefault = shift;

    return $self->get($strSection, $strValue, $strSubValue, $bRequired,
                      defined($nDefault) ? $nDefault + 0 : undef) + 0;
}

####################################################################################################################################
# arrayGet
#
# Get a value as an array even if it is a scalar.
####################################################################################################################################
sub arrayGet
{
    my $self = shift;
    my $strSection = shift;
    my $strValue = shift;
    my $strSubValue = shift;
    my $bRequired = shift;
    my $nDefault = shift;

    my $stryValue = $self->get($strSection, $strValue, $strSubValue, $bRequired);

    # If not defined return an empty array
    if (!defined($stryValue))
    {
        $stryValue = [];
    }
    # Else if the value is not an array make it one with a single entry
    elsif (ref($stryValue) ne "ARRAY")
    {
        $stryValue = [$stryValue];
    }

    return $stryValue;
}

####################################################################################################################################
# keys
#
# Get a list of keys.
####################################################################################################################################
sub keys
{
    my $self = shift;
    my $strSection = shift;
    my $strKey = shift;

    if (defined($strSection))
    {
        if ($self->test($strSection, $strKey))
        {
            return sort(keys(%{$self->get($strSection, $strKey)}));
        }

        my @stryEmptyArray;
        return @stryEmptyArray;
    }

    return sort(keys(%{$self->{oContent}}));
}

####################################################################################################################################
# test
#
# Test a value to see if it equals the supplied test value.  If no test value is given, tests that it is defined.
####################################################################################################################################
sub test
{
    my $self = shift;
    my $strSection = shift;
    my $strValue = shift;
    my $strSubValue = shift;
    my $strTest = shift;

    my $strResult = $self->get($strSection, $strValue, $strSubValue, false);

    if (defined($strResult))
    {
        if (defined($strTest))
        {
            return $strResult eq $strTest ? true : false;
        }

        return true;
    }

    return false;
}

1;
