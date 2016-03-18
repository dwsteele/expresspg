-- Create a sample schema
create schema sample;

-- reset role;

-- Create a sample table
create table sample.master
(
    id bigint,
    name text not null,
    description text,

    constraint mst_pk primary key (id)
);

do $$
begin
    perform _build.object_name_exception('sample', 'mst_pk');
    perform _build.history_table_add('sample', 'master');
exception
    when invalid_schema_name then null;
end $$;

insert into sample.master (name) values ('test1');
insert into sample.master (name, description) values ('test2', 'test');
insert into sample.master (name) values ('test3');

update sample.master set description = 'dude' where name = 'test2';
update sample.master set description = null where name = 'test2';
update sample.master set description = 'dude' where name = 'test2';

delete from sample.master where name = 'test2';

create table sample.detail
(
    id int
        constraint detail_id_fk references sample.master (id)
);

do $$
begin
    perform _build.foreign_key_exception('sample', 'detail_id_fk');
exception
    when invalid_schema_name then null;
end $$;

-- reset role;

create table sample.other_owner
(
    id int
);

set role sample;

do $$
begin
    perform _build.object_owner_exception('sample', 'other_owner', 'vagrant');
exception
    when invalid_schema_name then null;
end $$;
