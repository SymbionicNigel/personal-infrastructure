import { pgTable, pgSchema, varchar } from "drizzle-orm/pg-core"
import { sql } from "drizzle-orm"

export const astarte = pgSchema("astarte");


export const alembicVersionInAstarte = astarte.table("alembic_version", {
	versionNum: varchar("version_num", { length: 32 }).primaryKey().notNull(),
});
