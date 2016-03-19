####################################################################################################################################
# SCRIPT HISTORY MODULE
####################################################################################################################################
package ExpressPg::Script::ScriptHistory;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Exporter qw(import);
    our @EXPORT = qw();

use ExpressPg::Common::Ini;
use ExpressPg::Common::Log;
use ExpressPg::Common::String;

####################################################################################################################################
# scriptHistoryRender
#
# Render history script.
####################################################################################################################################
sub scriptHistoryRender
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oBuild,
        $strSchema,
        $strCommand,
        $strDbOwner,
        $lHistoryIdMin,
        $lHistoryIdMax,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::scriptHistoryRender', \@_,
            {name => 'oBuild', trace => true},
            {name => 'strSchema', trace => true},
            {name => 'strCommand', trace => true},
            {name => 'strDbOwner', trace => true},
            {name => 'lHistoryIdMin', trace => true},
            {name => 'lHistoryIdMax', trace => true}
        );

    # Working variables
    my $strScript;
    my $strDoNoModifyComment = 'GENERATED AUTOMATICALLY BY EXPRESSPG - DO NOT MODIFY!';

    if ($strCommand eq CMD_BUILD || $strCommand eq CMD_UPDATE)
    {
        $strScript = trim("
/***********************************************************************************************************************************
************************************************************************************************************************************
HISTORY Tables & Functions
************************************************************************************************************************************
**********************************************************************************************************************************/;
" . $oBuild->roleResetText($oBuild->{strDbOwner}) . "
create schema ${strSchema};

create sequence ${strSchema}.history_id_seq start with ${lHistoryIdMin};

/***********************************************************************************************************************************
HISTORY_TABLE Table

Stores configuration parameters for a tables tracking history.
**********************************************************************************************************************************/;
create table ${strSchema}.history_table
(
    id bigint not null default nextval('${strSchema}.history_id_seq'),
    schema_name text not null
        constraint historytable_schemaname_ck
            check (schema_name = lower(schema_name)),
    table_name text not null
        constraint historytable_tablename_ck
            check (table_name = lower(table_name)),

    constraint historytable_pk
        primary key (id),
    constraint historytable_schemaname_tablename_unq
        unique (schema_name, table_name)
);

/***********************************************************************************************************************************
HISTORY_OBJECT Table

Stores a reference to every object that will participate in a slowly changing dimension, even if it does not do so in the current
database.
**********************************************************************************************************************************/;
create table ${strSchema}.history_object
(
    id bigint not null,
    history_table_id bigint
        constraint historyobject_historytableid_fk
            references ${strSchema}.history_table (id),
    timestamp_insert timestamp with time zone not null,
    timestamp_update timestamp with time zone,
    timestamp_delete timestamp with time zone,

    constraint historyobject_pk
        primary key (id)
);

create index historyobject_historytableid_idx
    on ${strSchema}.history_object (history_table_id);

/***********************************************************************************************************************************
HISTORY_ROLE Table
**********************************************************************************************************************************/;
create table ${strSchema}.history_role
(
    id bigint not null default nextval('${strSchema}.history_id_seq'),
    key text not null,
    deny boolean not null default false,
    comment boolean not null default true,

    constraint historyrole_pk
        primary key (id),
    constraint historyrole_key_unq
        unique (key)
);

-- insert into _scd.account (key, deny) values ('postgres', true);
-- insert into _scd.account (key, deny) values ((select * from _utility.role_get()), true);
-- insert into _scd.account (key, deny) values ((select * from _utility.role_get('admin')), true);
-- insert into _scd.account (key, deny, comment) values ((select * from _utility.role_get('user')), true, false);
-- insert into _scd.account (key, deny) values ((select * from _utility.role_get('reader')), true);

/***********************************************************************************************************************************
HISTORY_APPLICATION Table
**********************************************************************************************************************************/;
create table ${strSchema}.history_application
(
    id bigint not null default nextval('${strSchema}.history_id_seq'),
    key text not null,
    deny boolean not null default false,
    comment boolean not null default true,

    constraint historyapplication_pk
        primary key (id),
    constraint historyapplication_key_unq
        unique (key)
);

/***********************************************************************************************************************************
HISTORY_TRANSACTION Table
**********************************************************************************************************************************/;
create table ${strSchema}.history_transaction
(
    id bigint not null,
    build boolean not null,
    history_role_id bigint not null
        constraint historytransaction_historyroleid_fk
            references ${strSchema}.history_role (id),
    history_application_id bigint not null
        constraint historytransaction_historyapplicationid_fk
            references ${strSchema}.history_application (id),
    comment text,
    constraint historytransaction_pk primary key (id)
);

create index historytransaction_historyroleid_idx
    on ${strSchema}.history_transaction (history_role_id);
create index historytransaction_historyapplicationid_idx
    on ${strSchema}.history_transaction (history_application_id);

/***********************************************************************************************************************************
HISTORY Table
**********************************************************************************************************************************/;
create table ${strSchema}.history
(
    id bigint not null default nextval('${strSchema}.history_id_seq'),
    history_object_id bigint
        constraint history_historyobjectid_fk
            references ${strSchema}.history_object (id),
    history_transaction_id bigint
        constraint history_historytransactionid_fk
            references ${strSchema}.history_transaction (id),
    timestamp timestamp with time zone default clock_timestamp(),
    type text not null
        constraint history_type_ck
            check (type in ('i', 'u', 'd')),
    data jsonb
        constraint history_data_ck
            check (data is not null or (type = 'd' and data is null)),

    constraint history_pk
        primary key (id)
);

create index history_historyobjectid_type_idx on ${strSchema}.history (history_object_id, type);
create index history_historytransactionid_idx on ${strSchema}.history (history_transaction_id);

/***********************************************************************************************************************************
HISTORY_TRANSACTION_CREATE Function
**********************************************************************************************************************************/;
create function ${strSchema}.history_transaction_create(strComment text default null) returns bigint as \$\$
declare
    lTransactionId bigint;
    lAccountId bigint;
    strAccountName text;
    bAccountDeny boolean;
    bAccountComment boolean;
    lApplicationId bigint;
    strApplicationName text;
    bApplicationDeny boolean;
    bApplicationComment boolean;
    bBuild boolean = false;
    strSql text;
begin
    begin
         execute 'create temporary table _temp_express_history_transaction (id bigint, comment text) on commit drop';

         insert into _temp_express_history_transaction (comment) values (strComment);
    exception
        when duplicate_table then
            select id
              into lTransactionId
              from _temp_express_history_transaction;

            if strComment is not null then
                update _temp_express_history_transaction
                   set comment = coalesce(comment || E'\\n', '') || trim(both E' \\t\\n' from strComment);

                if lTransactionId is not null then
                    update _scd.transaction
                       set comment = (select comment from _temp_express_history_transaction)
                     where id = lTransactionId;
                end if;
            end if;

            if lTransactionId is not null then
                return lTransactionId;
            end if;
    end;

    select count(*) = 1
      into bBuild
      from pg_namespace
     where pg_namespace.nspname = '_build';

    if (strComment is null or bBuild = true) and lTransactionId is null then
        select nextval('${strSchema}.history_id_seq')
         into lTransactionId;

         update _temp_express_history_transaction
            set id = lTransactionId;

         select id,
                key,
                deny,
                comment
           into lAccountId,
                strAccountName,
                bAccountDeny,
                bAccountComment
           from ${strSchema}.history_role
          where history_role.key = session_user;

        if bAccountDeny then
            raise exception 'role \"%\" cannot update tables with history', strAccountName;
        end if;

        -- This exception is for 9.0-9.2 compatability.
        strSql =
            'select coalesce(application_name, ''<unknown>'')
              from pg_stat_activity
             where pid = pg_backend_pid()';

        execute strSql into strApplicationName;

        select id,
               deny,
               comment
          into lApplicationId,
               bApplicationDeny,
               bApplicationComment
          from ${strSchema}.history_application
         where lower(history_application.key) = lower(strApplicationName);

        if bApplicationDeny then
            raise exception 'application \"%\" cannot update tables with history', strApplicationName;
        end if;

        if lAccountId is null then
            insert into ${strSchema}.history_role (key)
                  values (session_user)
               returning id, deny, comment
                    into lAccountId, bAccountDeny, bAccountComment;
        end if;

        if lApplicationId is null then
            insert into ${strSchema}.history_application (key)
                 values (strApplicationName)
              returning id, deny, comment
                   into lApplicationId, bApplicationDeny, bApplicationComment;
        end if;

        strComment = (select comment from _temp_express_history_transaction);

        if bAccountComment and bApplicationComment then
            if strComment is null then
                raise exception 'Transaction comment is required';
            end if;
        end if;

        insert into ${strSchema}.history_transaction (id, build, history_role_id, history_application_id, comment)
             values (lTransactionId, bBuild, lAccountId, lApplicationId, strComment);
    end if;

    return lTransactionId;
end
\$\$ language plpgsql security definer;

do \$\$ begin perform ${strSchema}.history_transaction_create('update in progress'); end \$\$;

/***********************************************************************************************************************************
EXPRESS_TRIGGER_MAINTAIN Function
**********************************************************************************************************************************/;
create function ${strSchema}.express_trigger_maintain
(
    strSchemaName text,
    strTableName text
)
    returns void as \$\$
declare
    strSchemaTableName text;
    strSchemaTableAbbr text;
    strTriggerPrefix text;
    strBody text = null;
    lHistoryTableId bigint;
begin
    -- Schema and table names should be lower case
    strSchemaName = lower(strSchemaName);
    strTableName = lower(strTableName);

    strSchemaTableName = strSchemaName || '.' || strTableName;
    strSchemaTableAbbr = replace(strTableName, '_', '');
    strTriggerPrefix = strSchemaName || '.' || strSchemaTableAbbr || '_express_';

    -- Determine whether history is tracked for this table
    select id
      into lHistoryTableId
      from ${strSchema}.history_table
     where schema_name = strSchemaName
       and table_name = strTableName;

    -- Generate the insert before trigger
    if lHistoryTableId is not null then
        strBody =
            E'    if new.id is null then\\n' ||
            E'        select nextval(''${strSchema}.history_id_seq'')\\n' ||
            E'          into new.id;\\n' ||
            E'    elsif new.id between ${lHistoryIdMin} and ${lHistoryIdMax} then\\n' ||
            E'        begin\\n' ||
            E'            if new.id > currval(''${strSchema}.history_id_seq'') and not pg_has_role(session_user, ''${strDbOwner}'', ''usage'') then\\n' ||
            E'                raise exception ''${strSchema}.history_id_seq has current value of % " .
                                              "so new.id = % is not valid (%)'',\\n' ||
            E'                                currval(''${strSchema}.history_id_seq''), new.id,\\n' ||
            E'                                ''use ${strSchema}.history_id_seq to generate valid history IDs'';\\n' ||
            E'            end if;\\n' ||
            E'        exception\\n' ||
            E'            when object_not_in_prerequisite_state then\\n' ||
            E'                if not pg_has_role(session_user, ''${strDbOwner}'', ''usage'') then\\n' ||
            E'                    raise exception ''${strSchema}.history_id_seq has no current value so " .
                                                  "new.id = % could not have come from it (%)'',\\n' ||
            E'                                    new.id, ''use ${strSchema}.history_id_seq to generate valid history IDs'';\\n' ||
            E'                end if;\\n' ||
            E'        end;\\n' ||
            E'    elsif new.id < 100000000000000000 then\\n' ||
            E'        raise exception ''IDs from foreign keyspaces must be >= 100000000000000000'';\\n' ||
            E'    end if;\\n' ||
            E'\\n' ||
            E'    begin\\n' ||
            E'        insert into ${strSchema}.history_object (id, history_table_id, timestamp_insert, timestamp_update)' || E'\\n' ||
            E'                    values (new.id, ' || lHistoryTableId || E', tsTimestamp, tsTimestamp);\\n' ||
            E'    exception\\n' ||
            E'        when unique_violation then\\n' ||
            E'            if\\n' ||
            E'            (\\n' ||
            E'                select history_table.id <> ' || lHistoryTableId || E'\\n' ||
            E'                  from ${strSchema}.history_table\\n' ||
            E'                 where object.id = new.id\\n' ||
            E'            ) then\\n' ||
            E'                raise exception ''Object % cannot be (re)inserted into another table'', new.id;\\n' ||
            E'            end if;\\n' ||
            E'\\n' ||
            E'            update _scd.object\\n' ||
            E'               set datetime_insert = tsTimestamp,\\n' ||
            E'                   datetime_update = tsTimestamp,\\n' ||
            E'                   datetime_delete = null\\n' ||
            E'             where id = new.id;\\n' ||
            E'    end;\\n' ||
            E'\\n' ||
            E'    insert into ${strSchema}.history (history_object_id, history_transaction_id, timestamp, type, data)\\n' ||
            E'         values (new.id, ${strSchema}.history_transaction_create(), tsTimestamp, ''i'',\\n' ||
            E'                 (select coalesce(\\n' ||
            E'                      (select (''{'' || string_agg(to_json(key) || '':'' || value, '','') || ''}'')\\n' ||
            E'                         from json_each(row_to_json(new.*))\\n' ||
            E'                        where key <> ''id''\\n' ||
            E'                              and json_typeof(value) <> ''null''),\\n' ||
            E'                      ''{}'')::jsonb));\\n';

    end if;

    -- Create the insert before trigger
    if strBody is not null then
        execute
            E'create or replace function ' || strTriggerPrefix || E'insert_before_trf()\\n' ||
            E'    returns trigger as \\\$\\\$\\n' ||
            E'-- ${strDoNoModifyComment}\\n' ||
            E'declare\\n' ||
            E'    tsTimestamp timestamp with time zone = clock_timestamp();\\n' ||
            E'begin\\n' ||
            strBody ||
            E'\\n' ||
            E'    return new;\\n' ||
            E'end\\n' ||
            E'\\\$\\\$ language plpgsql security definer';

        execute
            E'create trigger ' || strSchemaTableAbbr || E'_express_insert_before_trg\\n' ||
            E'    before insert on ' || strSchemaTableName || E'\\n' ||
            E'    for each row execute procedure ' || strTriggerPrefix || 'insert_before_trf()';

        strBody = null;
    end if;

    -- Generate the update before trigger
    if lHistoryTableId is not null then
        strBody =
            E'    if new.id <> old.id then' || E'\\n' ||
            E'        raise exception ''Cannot alter ID on ' || strSchemaTableName || ''';' || E'\\n' ||
            E'    end if;\\n' ||
            E'\\n' ||
            E'    update ${strSchema}.history_object\\n' ||
            E'       set timestamp_update = tsTimestamp\\n' ||
            E'     where id = new.id;\\n' ||
            E'\\n' ||
            E'    insert into ${strSchema}.history (history_object_id, history_transaction_id, timestamp, type, data)\\n' ||
            E'         values (new.id, ${strSchema}.history_transaction_create(), tsTimestamp, ''u'',\\n' ||
            E'                 (select coalesce(\\n' ||
            E'                      (select (''{'' || string_agg(to_json(new_field.key) || '':'' || new_field.value, '','') || ''}'')\\n' ||
            E'                         from json_each(row_to_json(new.*)) as new_field\\n' ||
            E'                              inner join json_each(row_to_json(old.*)) as old_field\\n' ||
            E'                                   on new_field.key = old_field.key\\n' ||
            E'                                  and new_field.value::text is distinct from old_field.value::text\\n' ||
            E'                        where new_field.key <> ''id''),\\n' ||
            E'                      ''{}'')::jsonb));\\n';
    end if;

    -- Create the update before trigger
    if strBody is not null then
        execute
            E'create or replace function ' || strTriggerPrefix || E'update_before_trf()\\n' ||
            E'    returns trigger as \\\$\\\$\\n' ||
            E'-- ${strDoNoModifyComment}\\n' ||
            E'declare\\n' ||
            E'    tsTimestamp timestamp with time zone = clock_timestamp();\\n' ||
            E'begin\\n' ||
            strBody ||
            E'\\n' ||
            E'    return new;\\n' ||
            E'end\\n' ||
            E'\\\$\\\$ language plpgsql security definer';

        execute
            E'create trigger ' || strSchemaTableAbbr || E'_express_update_before_trg\\n' ||
            E'    before update on ' || strSchemaTableName || E'\\n' ||
            E'    for each row execute procedure ' || strTriggerPrefix || 'update_before_trf()';

        strBody = null;
    end if;

    -- Generate the delete after trigger
    if lHistoryTableId is not null then
        strBody =
            E'    update ${strSchema}.history_object\\n' ||
            E'       set timestamp_delete = tsTimestamp\\n' ||
            E'     where id = old.id;\\n' ||
            E'\\n' ||
            E'    insert into ${strSchema}.history (history_object_id, history_transaction_id, timestamp, type)\\n' ||
            E'         values (old.id, ${strSchema}.history_transaction_create(), tsTimestamp, ''d'');\\n';
    end if;

    -- Create the delete after trigger
    if strBody is not null then
        execute
            E'create or replace function ' || strTriggerPrefix || E'delete_after_trf()\\n' ||
            E'    returns trigger as \\\$\\\$\\n' ||
            E'-- ${strDoNoModifyComment}\\n' ||
            E'declare\\n' ||
            E'    tsTimestamp timestamp with time zone = clock_timestamp();\\n' ||
            E'begin\\n' ||
            strBody ||
            E'\\n' ||
            E'    return old;\\n' ||
            E'end\\n' ||
            E'\\\$\\\$ language plpgsql security definer';

        execute
            E'create trigger ' || strSchemaTableAbbr || E'_express_delete_after_trg\\n' ||
            E'    after delete on ' || strSchemaTableName || E'\\n' ||
            E'    for each row execute procedure ' || strTriggerPrefix || 'delete_after_trf()';

        strBody = null;
    end if;
end;
\$\$ language plpgsql security definer;
");
    }

    $strScript .= (defined($strScript) ? "\n\n" : '') . trim("
/***********************************************************************************************************************************
HISTORY_TABLE_ADD Function
**********************************************************************************************************************************/;
create function _build.history_table_add
(
    strSchemaName text,
    strTableName text
)
    returns void as \$\$
declare
    strSchemaTableName text = strSchemaName || '.' || strTableName;
    strSchemaTableAbbr text = replace(strTableName, '_', '');
begin
    -- Insert the table into history_table so it can be tracked
    insert into ${strSchema}.history_table (schema_name, table_name)
                values (strSchemaName, strTableName);

    -- Create a foreign key from the table's primary key to history_object
    execute 'alter table ' || strSchemaTableName || ' add constraint ' || strSchemaTableAbbr || '_id_fk ' ||
            'foreign key (id) references ${strSchema}.history_object (id)';

    -- Update the triggers
    perform ${strSchema}.express_trigger_maintain(strSchemaName, strTableName);
end;
\$\$ language plpgsql security definer;
");

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strScript', value => $strScript, trace => true}
    );
}

push @EXPORT, qw(scriptHistoryRender);

1;
