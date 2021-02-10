ALTER TABLE "test" ALTER COLUMN "jsontest" TYPE jsonb USING "jsontest"::jsonb;
ALTER TABLE "logentry" ALTER COLUMN "savedstate" TYPE jsonb USING "savedstate"::jsonb;
