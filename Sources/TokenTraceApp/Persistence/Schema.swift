import Foundation

enum Schema {
    static let createSamplesTable = """
    CREATE TABLE IF NOT EXISTS samples (
      ts          INTEGER NOT NULL,
      bucket      TEXT    NOT NULL,
      util        REAL    NOT NULL,
      resets_at   INTEGER NOT NULL,
      PRIMARY KEY (ts, bucket)
    );
    """

    static let createBucketTsIndex = """
    CREATE INDEX IF NOT EXISTS idx_samples_bucket_ts ON samples(bucket, ts);
    """

    // MARK: - Claude Code usage (claude-code-usage change)

    static let createCCMessageTable = """
    CREATE TABLE IF NOT EXISTS cc_message (
      uuid                  TEXT    PRIMARY KEY,
      ts                    INTEGER NOT NULL,
      cwd                   TEXT    NOT NULL,
      model                 TEXT    NOT NULL,
      input_tokens          INTEGER NOT NULL DEFAULT 0,
      output_tokens         INTEGER NOT NULL DEFAULT 0,
      cache_creation_tokens INTEGER NOT NULL DEFAULT 0,
      cache_read_tokens     INTEGER NOT NULL DEFAULT 0,
      session_id            TEXT    NOT NULL,
      request_id            TEXT,
      is_sidechain          INTEGER NOT NULL DEFAULT 0,
      file_path             TEXT    NOT NULL
    );
    """

    static let createCCMessageTsIndex = """
    CREATE INDEX IF NOT EXISTS idx_ccm_ts ON cc_message(ts);
    """

    static let createCCMessageCwdTsIndex = """
    CREATE INDEX IF NOT EXISTS idx_ccm_cwd_ts ON cc_message(cwd, ts);
    """

    static let createCCIngestCheckpointTable = """
    CREATE TABLE IF NOT EXISTS cc_ingest_checkpoint (
      file_path    TEXT    PRIMARY KEY,
      byte_offset  INTEGER NOT NULL,
      file_size    INTEGER NOT NULL,
      mtime        INTEGER NOT NULL
    );
    """

    static let createProjectAliasTable = """
    CREATE TABLE IF NOT EXISTS project_alias (
      cwd          TEXT PRIMARY KEY,
      display_name TEXT NOT NULL
    );
    """

    static let allDDL: [String] = [
        createSamplesTable,
        createBucketTsIndex,
        createCCMessageTable,
        createCCMessageTsIndex,
        createCCMessageCwdTsIndex,
        createCCIngestCheckpointTable,
        createProjectAliasTable,
    ]
}
