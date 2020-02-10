import MySQLKit

class ViiMySQLConnection: ViiConnection {

    var connection: MySQLConnection
    var schema: String

    init(eventLoop: EventLoop, credentials: Credential) throws {
        self.connection = try MySQLConnection.create(on: eventLoop, credentials: credentials).wait()
        self.schema = credentials.database
    }

    func getTables() -> EventLoopFuture<[Table]> {
        return self.connection.withConnection { db in
            return db.sql()
                .raw("SELECT table_name as tableName FROM information_schema.tables WHERE table_schema = \(bind: self.schema)")
                .all(decoding: Table.self)
        }
    }

    func close() {
         try! self.connection.close().wait()
    }

    func getColumns(table: Table) -> EventLoopFuture<[Column]> {
        return self.connection.withConnection { db in
            return db.sql()
                     .raw("""
                        SELECT
                            COLUMN_NAME AS columnName,
                            DATA_TYPE AS dataType,
                            CASE WHEN IS_NULLABLE = 'NO' THEN
                                FALSE
                            ELSE
                                TRUE
                            END AS isNullable
                        FROM
                            information_schema.columns
                        WHERE
                            table_schema = \(bind: self.schema)
                        AND TABLE_NAME = \(bind: table.tableName)
                        ORDER BY
                            table_name,
                            ordinal_position;
                    """)
                .all(decoding: Column.self)
        }
    }

    func getPrimaryKey(table: Table) -> EventLoopFuture<Column?> {
        return self.connection.withConnection { db in
            return db.sql()
                     .raw("""
                     SELECT
                         kcu.column_name AS columnName,
                         c.DATA_TYPE AS dataType,
                         CASE WHEN c.IS_NULLABLE = 'NO' THEN
                             FALSE
                         ELSE
                             TRUE
                         END AS isNullable,
                         NULL AS constrainedTable
                     FROM
                         information_schema.KEY_COLUMN_USAGE kcu
                         INNER JOIN information_schema.columns c ON c.table_name = kcu.table_name
                     WHERE
                         kcu.table_schema = schema()
                         AND constraint_name = 'PRIMARY'
                         AND kcu.table_name = 'demo'
                         AND kcu.column_name = c.column_name;
                     """)
                    .first(decoding: Column.self)
        }
    }
    
    func getForeignKeys(table: Table) -> EventLoopFuture<[Column]> {
        return self.connection.withConnection { db in
            return db.sql()
                     .raw("""
                     SELECT
                         c.COLUMN_NAME AS columnName,
                         c.DATA_TYPE AS dataType,
                         CASE WHEN IS_NULLABLE = 'NO' THEN
                             FALSE
                         ELSE
                             TRUE
                         END AS isNullable,
                         kcu.REFERENCED_TABLE_NAME as constrainedTable
                     FROM
                         information_schema.TABLE_CONSTRAINTS tc
                         INNER JOIN information_schema.KEY_COLUMN_USAGE kcu ON kcu.TABLE_NAME = tc.TABLE_NAME
                         INNER JOIN information_schema.COLUMNS c ON tc.TABLE_NAME = c.TABLE_NAME
                     WHERE
                         tc.CONSTRAINT_TYPE = 'FOREIGN KEY'
                         AND c.EXTRA != 'auto_increment'
                         AND tc.TABLE_SCHEMA = 'vapor'
                         AND c.TABLE_NAME = '\(table.tableName)'
                         AND kcu.REFERENCED_TABLE_NAME IS NOT NULL;
                     """)
                    .all(decoding: Column.self)
        }
    }
}
