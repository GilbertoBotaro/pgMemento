-- TEST_INIT.sql
--
-- Author:      Felix Kunde <felix-kunde@gmx.de>
--
--              This script is free software under the LGPL Version 3
--              See the GNU Lesser General Public License at
--              http://www.gnu.org/copyleft/lgpl.html
--              for more details.
-------------------------------------------------------------------------------
-- About:
-- Script that initializes pgMemento for a single table in the test database
-------------------------------------------------------------------------------
--
-- ChangeLog:
--
-- Version | Date       | Description                                    | Author
-- 0.3.0     2020-03-05   reflect new_data column in row_log               FKun
-- 0.2.0     2017-09-08   moved drop parts to TEST_UNINSTALL.sql           FKun
-- 0.1.0     2017-07-20   initial commit                                   FKun
--

-- get test number
SELECT nextval('pgmemento.test_seq') AS n \gset

\echo
\echo 'TEST ':n': pgMemento initializaton'

\echo
\echo 'TEST ':n'.1: Create event trigger'
DO
$$
BEGIN
  -- create the event triggers
  PERFORM pgmemento.create_schema_event_trigger(TRUE, TRUE);

  -- query for event triggers
  ASSERT (
    SELECT NOT EXISTS (
      SELECT
        1
      FROM (
        VALUES
          ('schema_drop_pre_trigger'),
          ('table_alter_post_trigger'),
          ('table_alter_post_trigger_full'),
          ('table_alter_pre_trigger'),
          ('table_create_post_trigger_full'),
          ('table_drop_post_trigger'),
          ('table_drop_pre_trigger')
        ) AS p (pgm_event_trigger)
      LEFT JOIN (
        SELECT
          evtname
        FROM
          pg_event_trigger
        ) t
        ON t.evtname = p.pgm_event_trigger
      WHERE
        t.evtname IS NULL
    )
  ), 'Error: Did not find all necessary event trigger!';
END;
$$
LANGUAGE plpgsql;

\echo
\echo 'TEST ':n'.2: Create log trigger'
DO
$$
DECLARE
  tab TEXT := 'object';
BEGIN
  -- create log trigger
  PERFORM pgmemento.create_table_log_trigger(tab, 'public', TRUE);

  -- query for log trigger
  ASSERT (
    SELECT NOT EXISTS (
      SELECT
        1
      FROM (
        VALUES
          ('log_delete_trigger'),
          ('log_insert_trigger'),
          ('log_transaction_trigger'),
          ('log_truncate_trigger'),
          ('log_update_trigger')
        ) AS p (pgm_trigger)
      LEFT JOIN (
        SELECT
          tg.tgname
        FROM
          pg_trigger tg,
          pg_class c
        WHERE
          tg.tgrelid = c.oid
          AND c.relname = 'object'
        ) t
        ON t.tgname = p.pgm_trigger
      WHERE
        t.tgname IS NULL
    )
  ), 'Error: Did not find all necessary trigger for % table!', tab;
END;
$$
LANGUAGE plpgsql;

\echo
\echo 'TEST ':n'.3: Create audit_id column'
DO
$$
DECLARE
  tab TEXT := 'object';
BEGIN
  -- add audit_id column. It should fire a DDL trigger to fill audit_table_log and audit column_log table
  PERFORM pgmemento.create_table_audit_id(tab, 'public');

  -- test if audit_id column exists
  ASSERT (
    SELECT EXISTS(
      SELECT
        audit_id
      FROM
        public.object
    )
  ), 'Error: Did not find audit_id column in % table!', tab;

  -- test if entry was made in audit_table_log table
  ASSERT (
    SELECT EXISTS(
      SELECT
        1
      FROM
        pgmemento.audit_table_log
      WHERE
        table_name = tab
    )
  ), 'Error: Did not find entry for % table in audit_table_log!', tab;

  -- test if entry was made for each column of given table in audit_column_log table
  ASSERT (
    SELECT NOT EXISTS(
      SELECT
        a.attname
      FROM
        pg_attribute a
      LEFT JOIN
        pgmemento.audit_column_log c
        ON c.column_name = a.attname
      WHERE
        a.attrelid = pgmemento.get_table_oid(tab, 'public')
        AND a.attname <> 'audit_id'
        AND a.attnum > 0
        AND NOT a.attisdropped
        AND c.column_name IS NULL
    )
  ), 'Error: Did not find entries for all columns of % table in audit_column_log!', tab;
END;
$$
LANGUAGE plpgsql;
