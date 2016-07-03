####################################################################################################################################
# BUILD MODULE
####################################################################################################################################
package ExpressPg::Build;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Exporter qw(import);
    our @EXPORT = qw();

use ExpressPg::Common::Exception;
use ExpressPg::Common::File;
use ExpressPg::Common::Ini;
use ExpressPg::Common::Log;
use ExpressPg::Common::String;

use ExpressPg::Script::ScriptBuild;
use ExpressPg::Script::ScriptHistory;
use ExpressPg::Script::ScriptTest;

####################################################################################################################################
# Operation constants
####################################################################################################################################
use constant OP_BUILD                                               => 'Ini';

use constant OP_BUILD_NEW                                           => OP_BUILD . "->new";
use constant OP_BUILD_PROCESS                                       => OP_BUILD . "->process";
use constant OP_BUILD_PROCESS_SUB                                   => OP_BUILD . "->processSub";

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;                  # Class name

    # Create the class hash
    my $self = {};
    bless $self, $class;

    # Assign function parameters, defaults, and log debug info
    (
        my $strOperation,
        $self->{strCommand},
        $self->{strConfigFile},
        $self->{strLibraryPath},
        $self->{strDbInstance},
        $self->{strDbOwner},
        $self->{strySchemaExclude},
        $self->{bDebug},
        $self->{bDebugAll},
        my $oParam
    ) =
        logDebugParam
        (
            OP_BUILD_NEW, \@_,
            {name => 'strCommand'},
            {name => 'oConfig'},
            {name => 'strLibraryPath'},
            {name => 'strDbInstance'},
            {name => 'strDbOwner'},
            {name => 'strySchemaExclude'},
            {name => 'bDebug'},
            {name => 'bDebugAll'},
            {name => 'oParam'},
        );

    # Load the config file
    $self->{oConfig} = new ExpressPg::Common::Ini($self->{strConfigFile}, true);

    # Get optional params
    $self->{bDrop} = defined($$oParam{bDrop}) && $$oParam{bDrop} ? true : false;
    $self->{strCopyFrom} = $$oParam{strCopyFrom};

    # Last block was not a long comment
    $self->{bCommentLong} = false;

    # Process the build
    $self->process();

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

####################################################################################################################################
# commentLong
####################################################################################################################################
sub commentLong
{
    my $self = shift;
    my $strComment = shift;

    $self->{bCommentLong} = true;

    $self->{strScript} .=
        (defined($self->{strScript}) ? "\n\n" : '') .
        '/' . ('*' x 131) . "\n" .
        trim($strComment) . "\n" .
        ('*' x 130) . '/;';
}

####################################################################################################################################
# commentShort
####################################################################################################################################
sub commentShort
{
    my $self = shift;
    my $strComment = shift;

    if (!defined($self->{strScript}))
    {
        confess &log(ASSERT, "script cannot begin with short comment");
    }

    if (length($strComment) > 129)
    {
        confess &log(ASSERT, "short comment cannot be longer than 129 characters: ${strComment}");
    }

    $self->{strScript} .= (!$self->{bCommentLong} ? "\n" : '') . "\n-- ${strComment}";
    $self->{bCommentLong} = false;
}

####################################################################################################################################
# block
####################################################################################################################################
sub block
{
    my $self = shift;
    my $strBlock = shift;
    my $bLF = shift;

    if (!defined($self->{strScript}))
    {
        confess &log(ASSERT, "script cannot begin with block");
    }

    $self->{strScript} .= (defined($bLF) && $bLF ? "\n" : '') . "\n" . trim($strBlock);
    $self->{bCommentLong} = false;
}

####################################################################################################################################
# roleReset
####################################################################################################################################
sub roleReset
{
    my $self = shift;
    my $strRole = shift;
    my $bLF = shift;

    if (!defined($self->{strScript}))
    {
        confess &log(ASSERT, "script cannot begin with roleReset");
    }

    $self->{strScript} .= (defined($bLF) && $bLF ? "\n" : '') . "\n" . $self->roleResetText($strRole);
    $self->{bCommentLong} = false;
}

####################################################################################################################################
# roleResetText
####################################################################################################################################
sub roleResetText
{
    my $self = shift;
    my $strRole = shift;

    return 'reset session authorization; reset role;' . (defined($strRole) ? " set role ${strRole};" : '') .
           ' set client_min_messages = \'warning\';';
}

####################################################################################################################################
# process
####################################################################################################################################
sub processSub
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my (
        $strOperation,
        $strConfigFile,
        $strWorkingPath,
        $bDebug,
        $bLibrary
    ) =
        logDebugParam
        (
            OP_BUILD_PROCESS_SUB, \@_,
            {name => 'strConfigFile'},
            {name => 'strWorkingPath'},
            {name => 'bDebug', default => false},
            {name => 'bLibrary', default => false}
        );

    # Local variable
    my $strCommand = $self->{strCommand};
    my $strDbOwner = $self->{strDbOwner};
    my $oConfig = new ExpressPg::Common::Ini($strConfigFile, true);

    # Add user build files
    if ($strCommand eq CMD_BUILD)
    {
        my $stryBuildFile = $oConfig->arrayGet(CONFIG_SECTION_FULL, CONFIG_KEY_FILE, undef, false);

        if (@{$stryBuildFile} == 0)
        {
            confess &log(ERROR, 'at least one file must be listed in \'' . CONFIG_SECTION_FULL . '\' section', ERROR_CONFIG_INVALID);
        }

        $self->commentLong('User build scripts.');
        $self->roleReset($strDbOwner);

        $self->commentShort('Include user scripts from original location for debugging');

        foreach my $strBuildFile (@{$stryBuildFile})
        {
            if ($bLibrary)
            {
                $strBuildFile = "${strWorkingPath}/${strBuildFile}";
            }

            $self->block("\\i ${strBuildFile}");
        }
    }

    # Add user update files
    elsif ($strCommand eq CMD_UPDATE)
    {
        my $stryUpdateFile = $oConfig->arrayGet(CONFIG_SECTION_UPDATE, CONFIG_KEY_FILE, undef, false);

        if (@{$stryUpdateFile} > 0)
        {
            $self->commentLong('User update scripts.');
            $self->roleReset($strDbOwner);

            $self->commentShort('Include user scripts from original location for debugging');

            foreach my $strUpdateFile (@{$stryUpdateFile})
            {
                if ($bLibrary)
                {
                    $strUpdateFile = "${strWorkingPath}/${strUpdateFile}";
                }

                $self->block("\\i ${strUpdateFile}");
            }
        }
    }
}

####################################################################################################################################
# process
####################################################################################################################################
sub process
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my ($strOperation) = logDebugParam(OP_BUILD_PROCESS);

    # Local variable
    my $strCommand = $self->{strCommand};
    my $oConfig = $self->{oConfig};
    my $strLibraryPath = $self->{strLibraryPath};
    my $strDbInstance = $self->{strDbInstance};
    my $strDbOwner = $self->{strDbOwner};
    my $strCopyFrom = $self->{strCopyFrom};
    my $bDebug = $self->{bDebug};
    my $bDebugAll = $self->{bDebugAll};
    my $bDrop = $self->{bDrop};
    my $strSchema = '_express';

    # Initialize build/update settings
    $self->commentLong("Initialize settings for ${strCommand}.");

    $self->commentShort('Do not output information messages');
    $self->block('\set QUIET on');

    $self->commentShort('Set autocommit on for the preamble');
    $self->block('\set AUTOCOMMIT on');

    $self->commentShort('Reset the user/role to the original logon role');
    $self->roleReset();

    $self->commentShort('Stop on error');
    $self->block('\set ON_ERROR_STOP on');

    $self->commentShort('Make sure that errors are detected and not automatically rolled back');
    $self->block('\set ON_ERROR_ROLLBACK off');

    $self->commentShort('Set verbosity according to build settings');
    $self->block('\set VERBOSITY terse');

    # Make sure the database owner role exists
    $self->commentLong("Create the database owner and reader roles if they doesn't exist.");

    $self->block("
do \$\$
begin
    -- Create the owner role
    if
    (
        select count(*) = 0
          from pg_roles
         where rolname = '${strDbOwner}'
    ) then
        create role ${strDbOwner} noinherit createrole;
    end if;

    -- Create the reader role
    if
    (
        select count(*) = 0
          from pg_roles
         where rolname = '${strDbOwner}_reader'
    ) then
        create role ${strDbOwner}_reader noinherit;
    end if;

    -- Create the user role
    if
    (
        select count(*) = 0
          from pg_roles
         where rolname = '${strDbOwner}_user'
    ) then
        create role ${strDbOwner}_user;
    end if;

    -- Create the admin role
    if
    (
        select count(*) = 0
          from pg_roles
         where rolname = '${strDbOwner}_admin'
    ) then
        create role ${strDbOwner}_admin;
        grant ${strDbOwner}_reader to ${strDbOwner}_admin;
    end if;
end \$\$;
");

    # Drop the old database on build
    if ($bDrop)
    {
        $self->commentLong('Drop old database after disconnecting all users.');

        $self->block("
do \$\$
declare
    xProcess record;
begin
    create temp table temp_build_process
    (
        pid integer
    );

    -- This exception is for 9.1-9.2 compatability.
    begin
        insert into temp_build_process
        select procpid as pid
          from pg_stat_activity
         where datname = '${strDbInstance}';
    exception
        when undefined_column then
            insert into temp_build_process
            select pid
              from pg_stat_activity
             where datname = '${strDbInstance}';
    end;

    for xProcess in
        select pid
          from temp_build_process
    loop
        perform pg_terminate_backend(xProcess.pid);
    end loop;

    drop table temp_build_process;
end \$\$;
");

        $self->block("drop database if exists ${strDbInstance};", true);
    }

    # Drop the old database on build
    if (defined($strCopyFrom))
    {
        if ($strCommand ne CMD_UPDATE)
        {
            confess &log(ERROR, '--copy-from option is only valid with ' . CMD_UPDATE . ' command', ERROR_OPTION_INVALID);
        }

        $self->commentLong('Copy the database to update from ${strCopyFrom}.');

        $self->block("
create database ${strDbInstance} with template = ${strCopyFrom};
alter database ${strDbInstance} owner to ${strDbOwner};
");
    }

    # Create the new database on build
    if ($strCommand eq CMD_BUILD)
    {
        $self->commentLong('Create the new database.');

        $self->block("create database ${strDbInstance} with owner ${strDbOwner} encoding = 'UTF8';");

        $self->commentShort('Revoke all public permissions for security');
        $self->block("revoke all on database ${strDbInstance} from public;");
    }

    # Connect to the database
    $self->commentLong('Connect to the database.');
    $self->block("\\connect ${strDbInstance}");

    $self->commentShort('Disallow connections from other clients');
    $self->block("update pg_database set datallowconn = false where datname = '${strDbInstance}';");

    # Analyze the database if it was copied
    if (defined($strCopyFrom))
    {
        $self->commentShort('Analyze the copied database');
        $self->block("analyze;");
    }

    $self->commentShort("Set autocommit off for the ${strCommand}");
    $self->block('\set AUTOCOMMIT off');

    if ($strCommand eq CMD_BUILD)
    {
        $self->commentShort('Drop default public schema -- this can be recreated later if required');
        $self->block('drop schema if exists public;');
    }

    # !!! Capture the transaction ID here and store in a temp table.  This will be used to ensure that no commits are done in any
    # of the user scripts or accidentally in the build scripts.

    # Include the _build schema
    $self->block(scriptBuildRender($self), true);

    # Include the _test schema
    $self->block(scriptTestRender($self), true);

    # Only include library code when requested
    if ($oConfig->get(CONFIG_SECTION_FEATURE, CONFIG_KEY_LIBRARY, undef, false, false))
    {
        # Include the history tables & functions
        $self->block(scriptHistoryRender($self, $strSchema, $strCommand, $strDbOwner,
            $oConfig->get(CONFIG_SECTION_HISTORY, CONFIG_KEY_ID_MIN),
            $oConfig->get(CONFIG_SECTION_HISTORY, CONFIG_KEY_ID_MAX)), true);
    }

    # $self->processSub("${strLibraryPath}/Script/build/build.conf", "${strLibraryPath}/Script", $bDebug, true);
    $self->processSub($self->{strConfigFile}, '.', $bDebug, false);

    # Build schema exclusion array
    my $strSchemaExclude;

    if (defined($self->{strySchemaExclude}))
    {
        foreach my $strSchema (@{$self->{strySchemaExclude}})
        {
            $strSchemaExclude .= (defined($strSchemaExclude) ? ', ' : '') .
                                 '"' . trim($strSchema) . '"';
        }
    }

    # Validation steps
    $self->commentLong('Validation procedures.');
    $self->roleReset($strDbOwner);
    $self->block("
do \$\$
declare
    strDbOwner text = '${strDbOwner}';
    strySchemaExclude text[] = '{" . (defined($strSchemaExclude) ? $strSchemaExclude : '') . "}'::text[];
begin
    -- Make sure that all objects are owned by the database owner
    perform _build.object_owner_validate(strDbOwner);

    -- Make sure all object names follow the standard
    perform _build.object_name_validate(strySchemaExclude);

    -- Make sure all foreign keys have supporting indexes
    perform _build.foreign_key_validate(strySchemaExclude);

    -- Make sure there are no public execute permissions on functions
    perform _build.public_execute_revoke();

    -- Assign read permissions on all tables to the reader role
    perform _build.reader_role_create(strDbOwner);
end \$\$;
", true);

    # Unit tests
    if ($strCommand eq CMD_BUILD)
    {
        my $stryTestFile = $oConfig->arrayGet(CONFIG_SECTION_FULL_TEST, CONFIG_KEY_FILE, undef, false);

        # Only include the unit tests if there are some
        if (@{$stryTestFile} > 0)
        {
            $self->commentLong('Begin unit tests.');
            $self->roleReset($strDbOwner);

            $self->commentShort('Create a savepoint for unit test reset');
            $self->block("savepoint unit_test;");

            $self->commentLong('User unit tests.');
            $self->commentShort('Include test scripts from original location for debugging');

            foreach my $strTestFile (@{$stryTestFile})
            {
                $self->block("\\i ${strTestFile}");
            }

            $self->commentLong('Make sure that all units were completed');
            $self->roleReset($strDbOwner);

            $self->block("
do \$\$
declare
    strUnitCurrent text = (select unit from _test.unit_test);
begin
    if strUnitCurrent is not null then
        raise exception 'Unit \"%\" was not ended by calling _test.unit_end()', strUnitCurrent;
    end if;
end \$\$;
", true);

            $self->commentShort('Rollback to before unit test started');
            $self->block('rollback to unit_test;');
        }
    }

    # Complete script
    $self->commentLong("Complete the ${strCommand}.");
    $self->roleReset();

    $self->commentShort('Drop build schemas');
    $self->block("drop schema _build cascade;");
    $self->block("drop schema _test cascade;");

    $self->commentShort('Allow connections to the database');
    $self->block("update pg_database set datallowconn = true where datname = '${strDbInstance}';");

    $self->commentShort("Commit the ${strCommand}");
    $self->block('commit;');

    $self->commentShort('Analyze the database');
    $self->block("analyze;");

    $self->commentShort("Commit the analyze");
    $self->block('commit;');

    # Add a final LF
    $self->block('');

    # Return from function and log return values if any
    logDebugReturn($strOperation)
}

1;
