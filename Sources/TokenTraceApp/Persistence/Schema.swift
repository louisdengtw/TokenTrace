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

    static let allDDL: [String] = [createSamplesTable, createBucketTsIndex]
}
