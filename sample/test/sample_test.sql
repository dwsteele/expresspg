--rollback; begin; set role cd_sample; update _scd.account set comment = false; savepoint unit_test;
rollback to unit_test;

/***********************************************************************************************************************************
* Unit test
***********************************************************************************************************************************/
do $$
begin
    perform _test.unit_begin('Sample Unit');

    perform _test.test_begin('Sample Unit Test');
    perform _test.test_pass();
    -- perform _test.test_fail('It didn''t work');

    perform _test.unit_end();
end $$;
