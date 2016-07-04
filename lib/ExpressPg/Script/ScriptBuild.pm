####################################################################################################################################
# SCRIPT BUILD MODULE
####################################################################################################################################
package ExpressPg::Script::ScriptBuild;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Exporter qw(import);
    our @EXPORT = qw();

use ExpressPg::Common::Log;
use ExpressPg::Common::String;

####################################################################################################################################
# scriptBuildRender
#
# Render build schema script.
####################################################################################################################################
sub scriptBuildRender
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oBuild
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::scriptBuildRender', \@_,
            {name => 'oBuild', trace => true}
        );

    my $strScript = trim("
/***********************************************************************************************************************************
************************************************************************************************************************************
_build schema

Common functions to be used in other parts of the build.
************************************************************************************************************************************
**********************************************************************************************************************************/;
" . $oBuild->roleResetText($oBuild->{strDbOwner}) . "
create schema _build;

grant usage
   on schema _build
   to public;

/***********************************************************************************************************************************
OBJECT_NAME_EXCEPTION Function & Table

Track object naming exceptions.
**********************************************************************************************************************************/;
create table _build.object_name_exception
(
    schema_name text not null,
    object_name text not null,

    constraint objectnameexception_pk primary key (schema_name, object_name)
);

create function _build.object_name_exception
(
    strSchemaName text,
    strObjectName text
)
    returns void as \$\$
begin
    insert into _build.object_name_exception (schema_name, object_name) values (strSchemaName, strObjectName);
end;
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
TRIGGER_EXCEPTION Function & Table

Track trigger naming exceptions.
**********************************************************************************************************************************/;
create table _build.trigger_exception
(
    schema_name text not null,
    trigger_name text not null,

    constraint triggerexception_pk primary key (schema_name, trigger_name)
);

create function _build.trigger_exception
(
    strSchemaName text,
    strTriggerName text
)
    returns void as \$\$
begin
    insert into _build.trigger_exception values (strSchemaName, strTriggerName);
end;
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
OBJECT_NAME_EXPECTED Function

Determine the expected name for an object that has columns.

oRelationId - Oid of the table object
strObjectName - Name of the object
strType - Type appended to the object name, if applicable, e.g. fk, ck, idx, etc.
iyColumn - Array of constrained column numbers
bRegExp - Is a regular expression built for matching?
bException - Is there a naming exception?
**********************************************************************************************************************************/;
create function _build.object_name_expected
(
    oRelationId oid,
    strObjectName text,
    strType text,
    iyColumn int[],
    bRegExp boolean default true,
    bException boolean default true
)
    returns text as \$\$
declare
     strName text;
     strSeparator text = '_';
begin
    if bException then
        select object_name
          into strName
          from pg_constraint
               inner join pg_namespace
                    on pg_namespace.oid = pg_constraint.connamespace
               inner join _build.object_name_exception
                    on object_name_exception.schema_name = pg_namespace.nspname
                   and object_name_exception.object_name = pg_constraint.conname
                   and object_name_exception.object_name = strObjectName
         where pg_constraint.conrelid = oRelationId;

        if strName is not null then
            return strName;
        end if;

        select object_name
          into strName
          from pg_index
               inner join pg_class
                    on pg_class.oid = pg_index.indexrelid
               inner join pg_namespace
                    on pg_namespace.oid = pg_class.relnamespace
               inner join _build.object_name_exception
                    on object_name_exception.schema_name = pg_namespace.nspname
                   and object_name_exception.object_name = pg_class.relname
                   and object_name_exception.object_name = strObjectName
         where pg_index.indrelid = oRelationId;

        if strName is not null then
            return strName;
        end if;
    end if;

    select replace(relname, '_', '')
      into strName
      from pg_class
     where oid = oRelationId;

    if bRegExp then
        strName = '^' || strName || '_'; -- || E'\\_(scd\\_|workflow\\_|)';
        strSeparator = E'\\_';
    else
        strName = strName || strSeparator;
    end if;

    if strType not in ('pk', 'ck') then
        for iIndex in array_lower(iyColumn, 1) .. array_upper(iyColumn, 1) loop
            if iyColumn[iIndex] <> 0 then
                select strName || replace(attname, '_', '') || strSeparator
                  into strName
                  from pg_attribute
                 where attrelid = oRelationId
                   and attnum = iyColumn[iIndex];
            else
                strName = strName || 'function' || strSeparator;
            end if;
        end loop ;
    end if;

    if strType = 'ck' then
        strName = strName || E'.*' || strSeparator;
    end if;

    strName = strName || strType;

    if bRegExp then
        strName = strName || '\$';
    end if;

    return strName;
end;
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
OBJECT_NAME_VALIDATE Function

Make sure all object names follow the standard (unless excepted).
**********************************************************************************************************************************/;
create function _build.object_name_validate
(
    strySchemaExclude text[]
)
    returns void as \$\$
declare
    rSchema record;
    rObject record;
    iCount int = 0;
begin
    for rSchema in
        select pg_namespace.oid,
               nspname as name
          from pg_namespace, pg_roles
         where pg_namespace.nspowner = pg_roles.oid
           and pg_roles.rolname <> 'postgres'
           and pg_namespace.nspname not like '%_partition'
           and not (pg_namespace.nspname = any(strySchemaExclude))
         order by name
    loop
        for rObject in
            select 'Index' as label,
                   pg_class.relname as name,
                   indrelid as table_oid,
                   pg_table.relname as table_name,
                   case indisunique
                       when true then 'unq'
                       else 'idx'
                   end as type,
                   indkey::int[] as columns
              from pg_class, pg_index, pg_class pg_table
             where pg_class.relnamespace = rSchema.oid
               and pg_class.oid = pg_index.indexrelid
               and pg_index.indrelid = pg_table.oid
               and not exists
             (
                 select conrelid
                   from pg_constraint
                  where pg_constraint.connamespace = rSchema.oid
                    and pg_constraint.conname = pg_class.relname
             )
                union
            select 'Constraint' as label,
                   pg_constraint.conname as name,
                   pg_constraint.conrelid as table_oid,
                   pg_class.relname as table_name,
                   case contype
                       when 'p' then 'pk'
                       when 'u' then 'unq'
                       when 'f' then 'fk'
                       when 'c' then 'ck'
                       else 'err'
                   end as type,
                   pg_constraint.conkey::int[] as columns
              from pg_constraint, pg_class
             where pg_constraint.connamespace = rSchema.oid
               and pg_constraint.conrelid = pg_class.oid
               and pg_constraint.contype <> 't'
            order by table_name, label, name
        loop
           if (rObject.name !~ _build.object_name_expected(rObject.table_oid, rObject.name, rObject.type, rObject.columns)) or
              (_build.object_name_expected(rObject.table_oid, rObject.name, rObject.type, rObject.columns) is null) then
               raise warning '% \"%\" on table \"%.%\" should be named \"%\"', rObject.label, rObject.name, rSchema.name,
                    rObject.table_name, _build.object_name_expected(rObject.table_oid, rObject.name, rObject.type, rObject.columns);
               iCount = iCount + 1;
           end if;
        end loop;

        -- for each trigger in the current schema (that does not begin with _) that is not a postgres internal trigger and is not
        -- an _scd,_workflow or _partition trigger check if there is an exception on the name else error if the name is not in the
        -- correct format.
        for rObject in
            select tgname as name,
                   pg_class.oid as table_oid,
                   pg_class.relname as table_name,
                   lower(replace(pg_class.relname, '_', '')) as table_abbr
              from pg_trigger
                   inner join pg_class
                        on pg_class.oid = pg_trigger.tgrelid
                       and pg_class.relnamespace = rSchema.oid
             where pg_trigger.tgisinternal = false
               and tgname !~ ('^' || lower(replace(pg_class.relname, '_', '')) || '_(scd|workflow|partition)_trigger_.*')
               and rSchema.name !~ E'^_'
               and not exists
                (
                    select trigger_name
                      from _build.trigger_exception
                     where schema_name = rSchema.name
                       and trigger_name = pg_trigger.tgname
                )
            order by table_name, name
        loop
            if rObject.name !~ (rObject.table_abbr || '_([0-9]{2}|express)_.*_trg') then
                raise warning 'Trigger \"%\" on table \"%.%\" (oid %) should begin with \"%\" and end with _trg',
                    rObject.name, rSchema.name, rObject.table_name, rObject.table_oid, rObject.table_abbr || '_([0-9]{2}|express)_';
                iCount = iCount + 1;
            end if;
        end loop;
    end loop;

    if iCount > 0 then
        raise exception 'Object naming errors were detected';
    end if;
end
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
FOREIGN_KEY_EXCEPTION Function & Table

Track exceptions to foreign keys requiring supporting indexes.
**********************************************************************************************************************************/;
create table _build.foreign_key_exception
(
    schema_name text not null,
    foreign_key_name text not null,

    constraint foreignkeyexception_pk primary key (schema_name, foreign_key_name)
);

create function _build.foreign_key_exception(strSchemaName text, strForeignKeyName text) returns void as \$\$
begin
    insert into _build.foreign_key_exception values (strSchemaName, strForeignKeyName);
end;
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
FOREIGN_KEY_VALIDATE Function

Make sure all foreign keys have supporting indexes.
**********************************************************************************************************************************/;
create function _build.foreign_key_validate
(
    strySchemaExclude text[]
)
    returns void as \$\$
declare
    rSchema record;
    rTable record;
    rForeignKey record;
    rIndex record;
    iCount int = 0;
    bFound boolean;
begin
    for rSchema in
        select pg_namespace.oid,
               nspname as name
          from pg_namespace, pg_roles
         where pg_namespace.nspowner = pg_roles.oid
           and pg_roles.rolname <> 'postgres'
           and pg_namespace.nspname not like '%_partition'
           and not (pg_namespace.nspname = any(strySchemaExclude))
         order by name
    loop
        for rTable in
            select oid,
                   relname as name
              from pg_class
             where relnamespace = rSchema.oid
             order by relname
        loop
            for rForeignKey in
                select _build.object_name_expected(rTable.oid, pg_constraint.conname,
                                                   '', pg_constraint.conkey::int[], false, false) as name
                  from pg_constraint
                 where pg_constraint.conrelid = rTable.oid
                   and pg_constraint.contype = 'f'
                   and not exists
                (
                    select foreign_key_name
                      from _build.foreign_key_exception
                     where schema_name = rSchema.name
                       and foreign_key_name = _build.object_name_expected(rTable.oid, pg_constraint.conname,
                                                                 'fk', pg_constraint.conkey::int[], false, true)
                )
                order by name
            loop
                bFound = false;

                for rIndex in
                    select _build.object_name_expected(rTable.oid, pg_class.relname, 'idx',
                                                       pg_index.indkey::int[], false, false) as name
                  from pg_index, pg_class
                 where pg_index.indrelid = rTable.oid
                   and pg_index.indexrelid = pg_class.oid
                   and pg_index.indpred is null
                loop
                    if strpos(rIndex.name, rForeignKey.name) = 1 then
                        bFound = true;
                    end if;
                end loop;

                if not bFound then
                    raise warning 'Foreign key %.%fk has no supporting index', rSchema.name, rForeignKey.name;
                    iCount = iCount + 1;
                end if;
            end loop;
        end loop;
    end loop;

    if iCount > 0 then
        raise exception 'Unsupported foreign keys were found';
    end if;
end
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
OBJECT_OWNER_EXCEPTION Function & Table

Track object owner exceptions
**********************************************************************************************************************************/;
create table _build.object_owner_exception
(
    schema_name text not null,
    object_name text not null,
    owner text not null,

    constraint objectownerexception_pk primary key (schema_name, object_name)
);

create function _build.object_owner_exception
(
    strSchemaName text,
    strObjectName text,
    strOwner text
)
    returns void as \$\$
begin
    insert into _build.object_owner_exception (schema_name, object_name, owner) values (strSchemaName, strObjectName, strOwner);
end;
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
OBJECT_OWNER_VALIDATE Function

Make sure that all objects are owner by the database owner (unless excepted).
**********************************************************************************************************************************/;
create function _build.object_owner_validate
(
    strOwnerName text
)
    returns void as \$\$
declare
    rSchema record;
    rObject record;
    iCount int = 0;
begin
    -- Temp table to hold the objects with invalid ownership
    create temp table temp_post_owner
    (
        ordering serial,
        type text,
        schema_name text,
        object_name text,
        owner text
    );

    for rSchema in
        select pg_namespace.oid, nspname as name
          from pg_namespace, pg_roles
         where pg_namespace.nspname not in ('_build')
           and pg_namespace.nspowner = pg_roles.oid
           and pg_roles.rolname <> 'postgres'
         order by nspname
    loop
        insert into temp_post_owner (type, schema_name, object_name, owner)
        select type,
               schema_name,
               object_name,
               owner
          from
            (
                select 'class' as type,
                       rSchema.name as schema_name,
                       relname as object_name,
                       pg_roles.rolname as owner
                  from pg_class
                       inner join pg_roles
                            on pg_roles.oid = pg_class.relowner
                           and pg_roles.rolname <> strOwnerName
                 where relnamespace = rSchema.oid
                    union
                select 'function' as types,
                       rSchema.name as schema_name,
                       proname as object_name,
                       pg_roles.rolname as owner
                  from pg_proc
                       inner join pg_roles
                            on pg_roles.oid = pg_proc.proowner
                           and pg_roles.rolname <> strOwnerName
                 where pronamespace = rSchema.oid
                    union
                select 'type' as type,
                       rSchema.name as schema_name,
                       typname as object_name,
                       pg_roles.rolname as owner
                  from pg_type
                       inner join pg_roles
                            on pg_roles.oid = pg_type.typowner
                           and pg_roles.rolname <> strOwnerName
                 where typnamespace = rSchema.oid
                   and typname not like E'\\_%'
                   and not exists
                (
                    select 'class' as type,
                           rSchema.name as schema_name,
                           relname as object_name,
                           pg_roles.rolname as owner
                      from pg_class
                     where relnamespace = rSchema.oid
                       and relname = pg_type.typname
                )
            ) object
         where not exists
        (
            select 1
              from _build.object_owner_exception
             where object_owner_exception.schema_name = object.schema_name
               and object_owner_exception.object_name = object.object_name
               and object_owner_exception.owner = object.owner
        )
         order by schema_name,
                  object_name,
                  type;
    end loop;

    for rObject in
        select *
          from temp_post_owner
         order by ordering
    loop
        raise warning '% %.% is owned by % instead of %', Initcap(rObject.type), rObject.schema_name, rObject.object_name,
                                                          rObject.owner, strOwnerName;
        iCount = iCount + 1;
    end loop;

    if iCount <> 0 then
        raise exception 'Some objects do not have correct ownership';
    end if;
end
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
BUILD_ROLE_CREATE Function

Make sure all tables and views can be read by the schema reader role and grant schema usage.
**********************************************************************************************************************************/;
create function _build.build_role_create
(
    strRoleName text,
    bInherit boolean default false
)
    returns void as \$\$
declare
    rSchema record;
begin
    if
    (
        select count(*) = 0
          from pg_roles
         where rolname = strRoleName
    ) then
        -- raise exception 'got here %', strRoleName;
        execute 'create role ' || strRoleName || case when bInherit then ' inherit' else ' noinherit' end;
    end if;
end
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
READER_ROLE_CREATE Function

Make sure all tables and views can be read by the schema reader role and grant schema usage.
**********************************************************************************************************************************/;
set role postgres;

create function _build.reader_role_create
(
    strOwnerName text
)
    returns void as \$\$
declare
    rSchema record;
    strReaderRole text = strOwnerName || '_reader';
begin
    perform _build.build_role_create(strReaderRole);

    for rSchema in
        select pg_namespace.oid, nspname as name
          from pg_namespace, pg_roles
         where pg_namespace.nspowner = pg_roles.oid
           and pg_roles.rolname <> 'postgres'
         order by nspname
    loop
        execute 'grant usage on schema ' || rSchema.name || ' to ' || strReaderRole;
        execute 'grant select on all tables in schema ' || rSchema.name || ' to ' || strReaderRole;
    end loop;
end
\$\$ language plpgsql security definer;

/***********************************************************************************************************************************
PUBLIC_EXECUTE_REVOKE Function

Make sure there are no public execute permissions on functions.
**********************************************************************************************************************************/;
create function _build.public_execute_revoke()
    returns void as \$\$
declare
    rSchema record;
begin
    for rSchema in
        select pg_namespace.oid, nspname as name
          from pg_namespace
               inner join pg_roles
                    on pg_roles.oid = pg_namespace.nspowner
                   and pg_roles.rolname <> 'postgres'
         where pg_namespace.nspname not in ('_build', '_test')
         order by nspname
    loop
        execute 'revoke all on all functions in schema ' || rSchema.name || ' from public';
    end loop;
end
\$\$ language plpgsql security definer;");

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strScript', value => $strScript, trace => true}
    );
}

push @EXPORT, qw(scriptBuildRender);

1;
