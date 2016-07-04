####################################################################################################################################
# SCRIPT TEST MODULE
####################################################################################################################################
package ExpressPg::Script::ScriptTest;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Exporter qw(import);
    our @EXPORT = qw();

use ExpressPg::Common::Log;
use ExpressPg::Common::String;

####################################################################################################################################
# scriptTestRender
#
# Render test schema script.
####################################################################################################################################
sub scriptTestRender
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oBuild
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::scriptTestRender', \@_,
            {name => 'oBuild', trace => true}
        );

    my $strScript = trim("
/***********************************************************************************************************************************
************************************************************************************************************************************
_test schema

Functions to implement a unit test suite for builds.
************************************************************************************************************************************
**********************************************************************************************************************************/;
" . $oBuild->roleResetText($oBuild->{strDbOwner}) . "
create schema _test;

grant usage
   on schema _build
   to public;

/***********************************************************************************************************************************
UNIT_TEST Table

Track the current test being run.
**********************************************************************************************************************************/;
create table _test.unit_test
(
    unit text,
    unit_begin timestamp,
    test text,
    test_begin timestamp
);

insert into _test.unit_test values (null, null, null, null);

/***********************************************************************************************************************************
UNIT_TEST_RESULT Table

Track all test results.
**********************************************************************************************************************************/;
create table _test.unit_test_result
(
    id serial not null,
    unit text not null,
    test text not null,
    test_interval interval not null,
    result text not null
        constraint unittestresult_result_ck check (result in ('fail', 'pass')),
    description text
        constraint unittestresult_description_ck check (description is null or result = 'fail' and description is not null),

    constraint unittestresult_pk primary key (id),
    constraint unittestresult_unit_test_unq unique (unit, test)
);

/***********************************************************************************************************************************
UNIT_BEGIN Function

Begin a test unit.
**********************************************************************************************************************************/;
create function _test.unit_begin(strUnit text) returns void as \$\$
declare
    strUnitCurrent text = (select unit from _test.unit_test);
begin
    if strUnitCurrent is not null then
        raise exception 'Cannot begin unit \"%\" when unit \"%\" is already running', strUnit, strUnitCurrent;
    end if;

    update _test.unit_test
       set unit = strUnit,
           unit_begin = clock_timestamp();
end;
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
UNIT_END Function

End a test unit.
**********************************************************************************************************************************/;
create function _test.unit_end() returns void as \$\$
declare
    strUnitCurrent text = (select unit from _test.unit_test);
    rResult record;
    bError boolean = false;
    strError text = E'\nErrors in ' || strUnitCurrent || ' Unit:';
begin
    if strUnitCurrent is null then
        raise exception 'Cannot end unit before it has begun';
    end if;

    update _test.unit_test
       set unit = null,
           unit_begin = null;

    for rResult in
        select rank() over (order by id) as rank,
               *
          from _test.unit_test_result
         where result = 'fail'
           and unit = strUnitCurrent
    loop
        strError = strError || E'\n' || rResult.rank || '. ' || rResult.test || ' - ' || coalesce(rResult.Description, '');
        bError = true;
    end loop;

    if bError then
        raise exception '%', strError;
    end if;
end;
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
TEST_BEGIN Function

Begin a test.
**********************************************************************************************************************************/;
create function _test.test_begin(strTest text) returns void as \$\$
declare
    strUnitCurrent text = (select unit from _test.unit_test);
    strTestCurrent text = (select test from _test.unit_test);
begin
    if strUnitCurrent is null then
        raise exception 'Cannot begin test \"%\" before a unit has begun', strTest;
    end if;

    if strTestCurrent is not null then
        raise exception 'Cannot begin unit test \"%/%\" when unit test \"%/%\" is already running',
                        strUnitCurrent, strTest, strUnitCurrent, strTestCurrent;
    end if;

    update _test.unit_test
       set test = strTest,
           test_begin = clock_timestamp();
end;
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
TEST_END Function

End a test.
**********************************************************************************************************************************/;
create function _test.test_end(strResult text, strDescription text) returns void as \$\$
declare
    strTestCurrent text = (select test from _test.unit_test);
begin
    if strTestCurrent is null then
        raise exception 'Must begin a test before calling %', strResult;
    end if;

    insert into _test.unit_test_result (unit, test, test_interval, result, description)
                                values ((select unit from _test.unit_test),
                                        strTestCurrent,
                                        clock_timestamp() - (select test_begin from _test.unit_test),
                                        strResult,
                                        strDescription);

    update _test.unit_test
       set test = null,
           test_begin = null;
end;
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
TEST_PASS Function

Mark a test as passed.
**********************************************************************************************************************************/;
create function _test.test_pass() returns void as \$\$
begin
    perform _test.test_end('pass', null);
end;
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
TEST_FAIL Function

Mark a test as failed.
**********************************************************************************************************************************/;
create function _test.test_fail(strDescription text) returns void as \$\$
begin
    perform _test.test_end('fail', strDescription);
end;
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
Grant permissions to public so all roles can run tests.
**********************************************************************************************************************************/;
grant usage on schema _test to public;
grant execute on all functions in schema _test to public;
");

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strScript', value => $strScript, trace => true}
    );
}

push @EXPORT, qw(scriptTestRender);

1;
